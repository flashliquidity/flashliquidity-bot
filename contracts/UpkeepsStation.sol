//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {KeeperRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperRegistryInterface.sol";
import {KeeperCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {KeeperRegistryWithdrawInterface} from "./interfaces/KeeperRegistryWithdrawInterface.sol";
import {IUpkeepsStationFactory} from "./interfaces/IUpkeepsStationFactory.sol";
import {IUpkeepsStation} from "./interfaces/IUpkeepsStation.sol";

struct UpkeepInfo {
    uint256 lastTimestamp;
    uint256 arrayIndex;
}

contract UpkeepsStation is IUpkeepsStation, KeeperCompatibleInterface {
    using SafeERC20 for IERC20;

    address public immutable stationsFactory;
    uint256[] public upkeepsRegistered;
    uint256[] public canceledToWithdraw;
    mapping(uint256 => UpkeepInfo) public upkeepsInfo;
    mapping(address => uint256) public flashbotUpkeep;
    LinkTokenInterface public immutable iLink;
    KeeperRegistryInterface public immutable iRegistry;

    constructor(address _iLink, address _iRegistry) {
        stationsFactory = msg.sender;
        iLink = LinkTokenInterface(_iLink);
        iRegistry = KeeperRegistryInterface(_iRegistry);
    }

    function isRegisteredUpkeep(uint256 _upkeepId) public view returns (bool) {
        return upkeepsInfo[_upkeepId].lastTimestamp > 0;
    }

    function doesUpkeepNeedFunds(uint256 _upkeepId) public view returns (bool needFunds) {
        uint256 _minWaitNext = IUpkeepsStationFactory(stationsFactory).minWaitNext();
        uint256 _timestamp = upkeepsInfo[_upkeepId].lastTimestamp;
        if (_timestamp > 0 && block.timestamp - _timestamp > _minWaitNext) {
            (, , , uint96 balance, , , , ) = iRegistry.getUpkeep(_upkeepId);
            uint96 _minUpkeepBalance = IUpkeepsStationFactory(stationsFactory).minUpkeepBalance();
            if (balance < _minUpkeepBalance) {
                return true;
            }
        }
        return false;
    }

    function transferToStation(address[] calldata _tokens, uint256[] calldata _amounts)
        external
        onlyStationFactory
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).safeTransfer(stationsFactory, _amounts[i]);
        }
        emit TransferredToStation(_tokens, _amounts);
    }

    function addUpkeep(uint256 _upkeepId, address _flashbot) external onlyStationFactory {
        require(!isRegisteredUpkeep(_upkeepId), "Already Registered");
        UpkeepInfo storage _info = upkeepsInfo[_upkeepId];
        _info.lastTimestamp = block.timestamp;
        _info.arrayIndex = upkeepsRegistered.length;
        flashbotUpkeep[_flashbot] = _upkeepId;
        upkeepsRegistered.push(_upkeepId);
        emit UpkeepRegistered(_upkeepId);
    }

    function removeUpkeep(address _flashbot) external onlyStationFactory {
        uint256 _upkeepId = flashbotUpkeep[_flashbot];
        uint256 _popIndex = upkeepsRegistered.length - 1;
        require(_upkeepId != 0, "No Upkeep Registered");
        UpkeepInfo storage _infoDel = upkeepsInfo[_upkeepId];
        require(_infoDel.lastTimestamp > 0, "Not Registered Upkeep");
        if (_infoDel.arrayIndex != _popIndex) {
            UpkeepInfo storage _infoMove = upkeepsInfo[upkeepsRegistered[_popIndex]];
            _infoMove.arrayIndex = _infoDel.arrayIndex;
            upkeepsRegistered[_infoDel.arrayIndex] = upkeepsRegistered[
                upkeepsRegistered.length - 1
            ];
        }
        flashbotUpkeep[_flashbot] = 0;
        _infoDel.lastTimestamp = 0;
        _infoDel.arrayIndex = 0;
        upkeepsRegistered.pop();
        canceledToWithdraw.push(_upkeepId);
        iRegistry.cancelUpkeep(_upkeepId);
        emit UpkeepRemoved(_upkeepId);
    }

    function withdrawCanceledUpkeeps(uint256 _upkeepsNumber) external onlyStationFactory {
        uint256 canceledToWithdrawLength = canceledToWithdraw.length;
        if (canceledToWithdrawLength > 0) {
            require(_upkeepsNumber <= canceledToWithdraw.length, "Not Enough Canceled Upkeeps");
            uint256 _index = _upkeepsNumber == 0 ? canceledToWithdraw.length : _upkeepsNumber;
            do {
                _index -= 1;
                KeeperRegistryWithdrawInterface(address(iRegistry)).withdrawFunds(
                    canceledToWithdraw[_index],
                    stationsFactory
                );
                canceledToWithdraw.pop();
            } while (_index > 0);
        }
    }

    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint96 _toUpkeepAmount = IUpkeepsStationFactory(stationsFactory).toUpkeepAmount();
        uint256 linkBalance = iLink.balanceOf(address(this));
        if (linkBalance > _toUpkeepAmount) {
            for (uint256 i = 0; i < upkeepsRegistered.length; i++) {
                if (doesUpkeepNeedFunds(upkeepsRegistered[i])) {
                    upkeepNeeded = true;
                    performData = abi.encode(i);
                    return (upkeepNeeded, performData);
                }
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256 _upkeepIndex = abi.decode(performData, (uint256));
        uint256 _upkeepId = upkeepsRegistered[_upkeepIndex];
        require(doesUpkeepNeedFunds(_upkeepId), "Add Funds Not Needed");
        uint96 _toUpkeepAmount = IUpkeepsStationFactory(stationsFactory).toUpkeepAmount();
        iLink.approve(address(iRegistry), _toUpkeepAmount);
        iRegistry.addFunds(_upkeepId, _toUpkeepAmount);
        emit UpkeepRefueled(_upkeepId, _toUpkeepAmount);
    }

    modifier onlyStationFactory() {
        require(msg.sender == stationsFactory, "Only Stations Factory");
        _;
    }
}
