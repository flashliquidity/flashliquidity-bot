// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFlashBot {
    function rewardToken() external view returns (address);

    function flashSwapFarm() external view returns (address);

    function flashPool() external view returns (address);

    function extPools(uint256 _index) external view returns (address);

    function feeTo() external view returns (address);

    function reserveProfitRatio() external view returns (uint256);

    function gasProfitMultiplier() external view returns (uint256);

    event DepositedProfits(address indexed _to, uint256 indexed _value);
    event OwnershipTransferred(address indexed _owner);
    event ExtPoolsChanged(address[] indexed _oldPools, address[] indexed _newPools);
    event ReserveProfitRatioChanged(uint256 indexed _oldRatio, uint256 indexed _newRatio);
    event GasProfitMultiplierChanged(uint256 indexed _oldProfit, uint256 indexed _newProfit);

    function getProfit(address pool0, address pool1) external view returns (uint256 profit);

    function getProfitThreshold(uint256 _rewardTokenPriceInWeth) external view returns (uint256);

    function setExtPools(address[] memory _extPools) external;

    function setReserveProfitRatio(uint256 _reserveProfitRatio) external;

    function setGasProfitMultiplier(uint16 _gasProfitMultiplier) external;

    function setFastGasFeed(address _fastGasFeed) external;

    function setWethPriceFeed(address _wethPriceFeed) external;

    function setRewardTokenPriceFeed(address _rewardTokenPriceFeed) external;

    function flashArbitrage(address pool0, address pool1) external;

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) external;
}
