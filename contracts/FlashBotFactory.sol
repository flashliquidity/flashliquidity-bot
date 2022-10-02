//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {FlashBot} from "./FlashBot.sol";
import {IFlashBotFactory} from "./interfaces/IFlashBotFactory.sol";
import {IUpkeepsStation} from "./interfaces/IUpkeepsStation.sol";
import {BastionConnector} from "./types/BastionConnector.sol";

contract FlashBotFactory is IFlashBotFactory, BastionConnector {
    address private immutable WETH;
    mapping(address => address) public poolFlashbot;

    constructor(
        address _WETH,
        address _governor,
        uint256 _transferGovernanceDelay
    ) BastionConnector(_governor, _transferGovernanceDelay) {
        WETH = _WETH;
    }

    function initialize(address _bastion) external onlyGovernor {
        initializeConnector(_bastion);
    }

    function deployFlashbot(
        address _rewardToken,
        address _flashSwapFarm,
        address _flashPool,
        address[] calldata _extPools,
        address _fastGasFeed,
        address _wethPriceFeed,
        address _rewardTokenPriceFeed,
        uint256 _reserveProfitRatio,
        uint256 _gasProfitMultiplier,
        uint32 _gasLimit
    ) external onlyWhenInitialized onlyBastion returns (address _flashbot) {
        _flashbot = address(
            new FlashBot(
                governor,
                WETH,
                _rewardToken,
                _flashSwapFarm,
                _flashPool,
                _extPools,
                bastion,
                _fastGasFeed,
                _wethPriceFeed,
                _rewardTokenPriceFeed,
                _reserveProfitRatio,
                _gasProfitMultiplier,
                transferGovernanceDelay,
                _gasLimit
            )
        );
        poolFlashbot[_flashPool] = _flashbot;
        emit FlashBotDeployed(_flashPool, _flashbot);
    }
}
