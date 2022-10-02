//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {KeeperCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IFlashBot} from "./interfaces/IFlashBot.sol";
import {IFlashLiquidityPair} from "./interfaces/IFlashLiquidityPair.sol";
import {Decimal} from "./libraries/Decimal.sol";
import {Governable} from "./types/Governable.sol";

struct OrderedReserves {
    uint256 a1; // base asset
    uint256 b1;
    uint256 a2;
    uint256 b2;
}

struct CallbackData {
    address debtPool;
    address targetPool;
    bool debtTokenSmaller;
    address borrowedToken;
    address debtToken;
    uint256 debtAmount;
    uint256 debtTokenOutAmount;
}

contract FlashBot is IFlashBot, Governable, KeeperCompatibleInterface {
    using Decimal for Decimal.D256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address private immutable WETH;
    address public immutable rewardToken;
    address public immutable flashSwapFarm;

    address public immutable flashPool;
    address[] public extPools;
    address public immutable feeTo;
    address private permissionedPairAddress = address(1);
    uint256 private immutable gasLimit;
    uint256 public reserveProfitRatio;
    uint256 public gasProfitMultiplier;

    AggregatorV3Interface private fastGasFeed;
    AggregatorV3Interface private wethPriceFeed;
    AggregatorV3Interface private rewardTokenPriceFeed;

    constructor(
        address _governor,
        address _WETH,
        address _rewardToken,
        address _flashSwapFarm,
        address _flashPool,
        address[] memory _extPools,
        address _feeTo,
        address _fastGasFeed,
        address _wethPriceFeed,
        address _rewardTokenPriceFeed,
        uint256 _reserveProfitRatio,
        uint256 _gasProfitMultiplier,
        uint256 _transferGovernanceDelay,
        uint32 _gasLimit
    ) Governable(_governor, _transferGovernanceDelay) {
        WETH = _WETH;
        rewardToken = _rewardToken;
        flashSwapFarm = _flashSwapFarm;
        flashPool = _flashPool;
        extPools = _extPools;
        feeTo = _feeTo;
        fastGasFeed = AggregatorV3Interface(_fastGasFeed);
        wethPriceFeed = AggregatorV3Interface(_wethPriceFeed);
        rewardTokenPriceFeed = AggregatorV3Interface(_rewardTokenPriceFeed);
        reserveProfitRatio = _reserveProfitRatio;
        gasProfitMultiplier = _gasProfitMultiplier;
        gasLimit = _gasLimit;
    }

    receive() external payable {}

    /// @dev Redirect uniswap callback function
    /// The callback function on different DEX are not same, so use a fallback to redirect to uniswapV2Call
    fallback(bytes calldata _input) external returns (bytes memory) {
        (address sender, uint256 amount0, uint256 amount1, bytes memory data) = abi.decode(
            _input[4:],
            (address, uint256, uint256, bytes)
        );
        uniswapV2Call(sender, amount0, amount1, data);
        return hex"";
    }

    /// @notice Calculate how much profit we can by arbitraging between two pools
    function getProfit(address pool0, address pool1) public view returns (uint256 profit) {
        (bool baseTokenSmaller, , ) = isbaseTokenSmaller(pool0, pool1);
        //baseToken = baseTokenSmaller ? IUniswapV2Pair(pool0).token0() : IUniswapV2Pair(pool0).token1();

        (, , OrderedReserves memory orderedReserves) = getOrderedReserves(
            pool0,
            pool1,
            baseTokenSmaller
        );

        uint256 borrowAmount = calcBorrowAmount(orderedReserves);
        // borrow quote token on lower price pool,
        uint256 debtAmount = getAmountIn(borrowAmount, orderedReserves.a1, orderedReserves.b1);
        // sell borrowed quote token on higher price pool
        uint256 baseTokenOutAmount = getAmountOut(
            borrowAmount,
            orderedReserves.b2,
            orderedReserves.a2
        );
        if (baseTokenOutAmount < debtAmount) {
            profit = 0;
        } else {
            profit = baseTokenOutAmount - debtAmount;
        }
    }

    // @notice Calculate the profit threshold above which arbitrage operation is triggered
    function getProfitThreshold(uint256 _rewardTokenPriceInWeth) public view returns (uint256) {
        uint256 minProfitInWeth = IERC20(rewardToken)
            .balanceOf(flashPool)
            .div(reserveProfitRatio)
            .mul(_rewardTokenPriceInWeth)
            .div(1e10);

        if (address(fastGasFeed) != address(0)) {
            (, int256 gasPrice, , , ) = fastGasFeed.latestRoundData();
            if (gasPrice > 0) {
                minProfitInWeth += gasProfitMultiplier.mul(uint256(gasPrice)).mul(gasLimit).mul(
                    1e8
                );
            }
        }
        return minProfitInWeth;
    }

    function getDerivedPrice() internal view returns (int256) {
        int256 decimals = int256(10**uint256(18));
        (, int256 basePrice, , , ) = rewardTokenPriceFeed.latestRoundData();
        uint8 baseDecimals = rewardTokenPriceFeed.decimals();
        basePrice = scalePrice(basePrice, baseDecimals, 18);

        (, int256 quotePrice, , , ) = wethPriceFeed.latestRoundData();
        uint8 quoteDecimals = wethPriceFeed.decimals();
        quotePrice = scalePrice(quotePrice, quoteDecimals, 18);

        return (basePrice * decimals) / quotePrice;
    }

    function scalePrice(
        int256 _price,
        uint8 _priceDecimals,
        uint8 _decimals
    ) internal pure returns (int256) {
        if (_priceDecimals < _decimals) {
            return _price * int256(10**uint256(_decimals - _priceDecimals));
        } else if (_priceDecimals > _decimals) {
            return _price / int256(10**uint256(_priceDecimals - _decimals));
        }
        return _price;
    }

    function isbaseTokenSmaller(address pool0, address pool1)
        internal
        view
        returns (
            bool baseSmaller,
            address baseToken,
            address quoteToken
        )
    {
        require(pool0 != pool1, "Same pair address");
        (address pool0Token0, address pool0Token1) = (
            IFlashLiquidityPair(pool0).token0(),
            IFlashLiquidityPair(pool0).token1()
        );
        (address pool1Token0, address pool1Token1) = (
            IFlashLiquidityPair(pool1).token0(),
            IFlashLiquidityPair(pool1).token1()
        );
        require(
            pool0Token0 < pool0Token1 && pool1Token0 < pool1Token1,
            "Non standard uniswap AMM pair"
        );
        require(
            pool0Token0 == pool1Token0 && pool0Token1 == pool1Token1,
            "Require same token pair"
        );
        require(rewardToken == pool0Token0 || rewardToken == pool0Token1, "No base token in pair");

        (baseSmaller, baseToken, quoteToken) = (rewardToken == pool0Token0)
            ? (true, pool0Token0, pool0Token1)
            : (false, pool0Token1, pool0Token0);
    }

    /// @dev Compare price denominated in quote token between two pools
    /// We borrow base token by using flash swap from lower price pool and sell them to higher price pool
    function getOrderedReserves(
        address pool0,
        address pool1,
        bool baseTokenSmaller
    )
        internal
        view
        returns (
            address lowerPool,
            address higherPool,
            OrderedReserves memory orderedReserves
        )
    {
        (uint256 pool0Reserve0, uint256 pool0Reserve1, ) = IFlashLiquidityPair(pool0).getReserves();
        (uint256 pool1Reserve0, uint256 pool1Reserve1, ) = IFlashLiquidityPair(pool1).getReserves();

        // Calculate the price denominated in quote asset token
        (Decimal.D256 memory price0, Decimal.D256 memory price1) = baseTokenSmaller
            ? (
                Decimal.from(pool0Reserve0).div(pool0Reserve1),
                Decimal.from(pool1Reserve0).div(pool1Reserve1)
            )
            : (
                Decimal.from(pool0Reserve1).div(pool0Reserve0),
                Decimal.from(pool1Reserve1).div(pool1Reserve0)
            );

        // get a1, b1, a2, b2 with following rule:
        // 1. (a1, b1) represents the pool with lower price, denominated in quote asset token
        // 2. (a1, a2) are the base tokens in two pools
        if (price0.lessThan(price1)) {
            (lowerPool, higherPool) = (pool0, pool1);
            (
                orderedReserves.a1,
                orderedReserves.b1,
                orderedReserves.a2,
                orderedReserves.b2
            ) = baseTokenSmaller
                ? (pool0Reserve0, pool0Reserve1, pool1Reserve0, pool1Reserve1)
                : (pool0Reserve1, pool0Reserve0, pool1Reserve1, pool1Reserve0);
        } else {
            (lowerPool, higherPool) = (pool1, pool0);
            (
                orderedReserves.a1,
                orderedReserves.b1,
                orderedReserves.a2,
                orderedReserves.b2
            ) = baseTokenSmaller
                ? (pool1Reserve0, pool1Reserve1, pool0Reserve0, pool0Reserve1)
                : (pool1Reserve1, pool1Reserve0, pool0Reserve1, pool0Reserve0);
        }
    }

    /// @dev calculate the maximum base asset amount to borrow in order to get maximum profit during arbitrage
    function calcBorrowAmount(OrderedReserves memory reserves)
        internal
        pure
        returns (uint256 amount)
    {
        // we can't use a1,b1,a2,b2 directly, because it will result overflow/underflow on the intermediate result
        // so we:
        //    1. divide all the numbers by d to prevent from overflow/underflow
        //    2. calculate the result by using above numbers
        //    3. multiply d with the result to get the final result
        // Note: this workaround is only suitable for ERC20 token with 18 decimals, which I believe most tokens do

        uint256 min1 = reserves.a1 < reserves.b1 ? reserves.a1 : reserves.b1;
        uint256 min2 = reserves.a2 < reserves.b2 ? reserves.a2 : reserves.b2;
        uint256 min = min1 < min2 ? min1 : min2;

        // choose appropriate number to divide based on the minimum number
        uint256 d;
        if (min > 1e24) {
            d = 1e20;
        } else if (min > 1e23) {
            d = 1e19;
        } else if (min > 1e22) {
            d = 1e18;
        } else if (min > 1e21) {
            d = 1e17;
        } else if (min > 1e20) {
            d = 1e16;
        } else if (min > 1e19) {
            d = 1e15;
        } else if (min > 1e18) {
            d = 1e14;
        } else if (min > 1e17) {
            d = 1e13;
        } else if (min > 1e16) {
            d = 1e12;
        } else if (min > 1e15) {
            d = 1e11;
        } else {
            d = 1e10;
        }

        (int256 a1, int256 a2, int256 b1, int256 b2) = (
            int256(reserves.a1 / d),
            int256(reserves.a2 / d),
            int256(reserves.b1 / d),
            int256(reserves.b2 / d)
        );

        int256 a = a1 * b1 - a2 * b2;
        int256 b = 2 * b1 * b2 * (a1 + a2);
        int256 c = b1 * b2 * (a1 * b2 - a2 * b1);

        (int256 x1, int256 x2) = calcSolutionForQuadratic(a, b, c);

        // 0 < x < b1 and 0 < x < b2
        require(
            (x1 > 0 && x1 < b1 && x1 < b2) || (x2 > 0 && x2 < b1 && x2 < b2),
            "Wrong input order"
        );
        amount = (x1 > 0 && x1 < b1 && x1 < b2) ? uint256(x1) * d : uint256(x2) * d;
    }

    /// @dev find solution of quadratic equation: ax^2 + bx + c = 0, only return the positive solution
    function calcSolutionForQuadratic(
        int256 a,
        int256 b,
        int256 c
    ) internal pure returns (int256 x1, int256 x2) {
        int256 m = b**2 - 4 * a * c;
        // m < 0 leads to complex number
        require(m > 0, "Complex number");

        int256 sqrtM = int256(sqrt(uint256(m)));
        x1 = (-b + sqrtM) / (2 * a);
        x2 = (-b - sqrtM) / (2 * a);
    }

    /// @dev Newton’s method for caculating square root of n
    function sqrt(uint256 n) internal pure returns (uint256 res) {
        assert(n > 1);

        // The scale factor is a crude way to turn everything into integer calcs.
        // Actually do (n * 10 ^ 4) ^ (1/2)
        uint256 _n = n * 10**6;
        uint256 c = _n;
        res = _n;

        uint256 xi;
        while (true) {
            xi = (res + c / res) / 2;
            // don't need be too precise to save gas
            if (res - xi < 1000) {
                break;
            }
            res = xi;
        }
        res = res / 10**3;
    }

    // copy from UniswapV2Library
    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "FlashBot: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "FlashBot: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // copy from UniswapV2Library
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "FlashBot: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "FlashBot: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function setExtPools(address[] memory _extPools) external onlyGovernor {
        address[] memory _oldPools = extPools;
        extPools = _extPools;
        emit ExtPoolsChanged(_oldPools, _extPools);
    }

    function setReserveProfitRatio(uint256 _reserveProfitRatio) external onlyGovernor {
        uint256 _oldRatio = reserveProfitRatio;
        reserveProfitRatio = _reserveProfitRatio;
        emit ReserveProfitRatioChanged(_oldRatio, _reserveProfitRatio);
    }

    function setGasProfitMultiplier(uint16 _gasProfitMultiplier) external onlyGovernor {
        uint256 _oldGasMultiplier = gasProfitMultiplier;
        gasProfitMultiplier = _gasProfitMultiplier;
        emit GasProfitMultiplierChanged(_oldGasMultiplier, _gasProfitMultiplier);
    }

    function setFastGasFeed(address _fastGasFeed) external onlyGovernor {
        fastGasFeed = AggregatorV3Interface(_fastGasFeed);
    }

    function setWethPriceFeed(address _wethPriceFeed) external onlyGovernor {
        wethPriceFeed = AggregatorV3Interface(_wethPriceFeed);
    }

    function setRewardTokenPriceFeed(address _rewardTokenPriceFeed) external onlyGovernor {
        rewardTokenPriceFeed = AggregatorV3Interface(_rewardTokenPriceFeed);
    }

    function withdraw() internal {
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if (balance > 0) {
            uint256 fee = balance.div(50); // 2%
            balance = balance.sub(fee);
            IERC20(rewardToken).safeTransfer(feeTo, fee);
            IERC20(rewardToken).safeTransfer(flashSwapFarm, balance);
            emit DepositedProfits(flashSwapFarm, balance);
        }
    }

    /// @notice Do an arbitrage between two Uniswap-like AMM pools
    /// @dev Two pools must contains same token pair
    function flashArbitrage(address pool0, address pool1) public {
        address _baseToken;
        address _quoteToken;
        bool _baseTokenSmaller;
        address _lowerPool; // pool with lower price, denominated in quote asset
        address _higherPool; // pool with higher price, denominated in quote asset

        (_baseTokenSmaller, _baseToken, _quoteToken) = isbaseTokenSmaller(pool0, pool1);

        OrderedReserves memory orderedReserves;
        (_lowerPool, _higherPool, orderedReserves) = getOrderedReserves(
            pool0,
            pool1,
            _baseTokenSmaller
        );

        // this must be updated every transaction for callback origin authentication
        permissionedPairAddress = _lowerPool;

        uint256 balanceBefore = IERC20(_baseToken).balanceOf(address(this));

        // avoid stack too deep error
        {
            uint256 borrowAmount = calcBorrowAmount(orderedReserves);
            (uint256 amount0Out, uint256 amount1Out) = _baseTokenSmaller
                ? (uint256(0), borrowAmount)
                : (borrowAmount, uint256(0));
            // borrow quote token on lower price pool, calculate how much debt we need to pay demoninated in base token
            uint256 debtAmount = getAmountIn(borrowAmount, orderedReserves.a1, orderedReserves.b1);
            // sell borrowed quote token on higher price pool, calculate how much base token we can get
            uint256 baseTokenOutAmount = getAmountOut(
                borrowAmount,
                orderedReserves.b2,
                orderedReserves.a2
            );
            require(baseTokenOutAmount > debtAmount, "Arbitrage fail, no profit");

            // can only initialize this way to avoid stack too deep error
            CallbackData memory callbackData;
            callbackData.debtPool = _lowerPool;
            callbackData.targetPool = _higherPool;
            callbackData.debtTokenSmaller = _baseTokenSmaller;
            callbackData.borrowedToken = _quoteToken;
            callbackData.debtToken = _baseToken;
            callbackData.debtAmount = debtAmount;
            callbackData.debtTokenOutAmount = baseTokenOutAmount;

            bytes memory data = abi.encode(callbackData);
            IFlashLiquidityPair(_lowerPool).swap(amount0Out, amount1Out, address(this), data);
        }

        uint256 balanceAfter = IERC20(_baseToken).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "Losing money");
        permissionedPairAddress = address(1);
        withdraw();
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) public {
        // access control
        require(msg.sender == permissionedPairAddress, "Non permissioned address call");
        require(sender == address(this), "Not from this contract");

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        CallbackData memory info = abi.decode(data, (CallbackData));

        IERC20(info.borrowedToken).safeTransfer(info.targetPool, borrowedAmount);

        (uint256 amount0Out, uint256 amount1Out) = info.debtTokenSmaller
            ? (info.debtTokenOutAmount, uint256(0))
            : (uint256(0), info.debtTokenOutAmount);
        IFlashLiquidityPair(info.targetPool).swap(
            amount0Out,
            amount1Out,
            address(this),
            new bytes(0)
        );

        IERC20(info.debtToken).safeTransfer(info.debtPool, info.debtAmount);
    }

    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint8 bestProfitIndex;
        uint256 bestProfit;
        uint256 tempProfit;
        int256 rewardTokenPriceInWeth = 1e18;
        if (rewardToken != WETH) {
            rewardTokenPriceInWeth = getDerivedPrice();
        }

        for (uint8 i = 0; i < extPools.length; i++) {
            tempProfit = getProfit(flashPool, extPools[i]);
            if (tempProfit > bestProfit) {
                bestProfitIndex = i;
                bestProfit = tempProfit;
            }
        }
        if (
            bestProfit.div(1e10).mul(uint256(rewardTokenPriceInWeth)) >
            getProfitThreshold(uint256(rewardTokenPriceInWeth))
        ) {
            upkeepNeeded = true;
            performData = abi.encode(extPools[bestProfitIndex]);
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        flashArbitrage(flashPool, abi.decode(performData, (address)));
    }
}
