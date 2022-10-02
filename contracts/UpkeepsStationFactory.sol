//SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {IUpkeepsStationFactory} from "./interfaces/IUpkeepsStationFactory.sol";
import {KeeperCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import {KeeperRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperRegistryInterface.sol";
import {KeeperRegistryWithdrawInterface} from "./interfaces/KeeperRegistryWithdrawInterface.sol";
import {UpkeepsStation} from "./UpkeepsStation.sol";
import {UpkeepsCreator} from "./types/UpkeepsCreator.sol";
import {BastionConnector} from "./types/BastionConnector.sol";

struct StationInfo {
    uint256 upkeepId;
    uint256 lastTimestamp;
    uint8 registeredUpkeeps;
}

contract UpkeepsStationFactory is
    IUpkeepsStationFactory,
    BastionConnector,
    UpkeepsCreator,
    KeeperCompatibleInterface
{
    address[] public stations;
    mapping(address => StationInfo) public stationsInfo;
    mapping(address => address) public flashBotRegisteredStation;
    uint256 public factoryUpkeepId;
    uint256 public minWaitNext = 6 hours;
    uint96 public minStationBalance;
    uint96 public minUpkeepBalance;
    uint96 public toStationAmount;
    uint96 public toUpkeepAmount;
    uint8 public maxStationUpkeeps;

    constructor(
        address _governor,
        address _registrar,
        address _linkToken,
        address _keeperRegistry,
        uint256 _transferGovernanceDelay,
        uint256 _minWaitNext,
        uint96 _minStationBalance,
        uint96 _minUpkeepBalance,
        uint96 _toStationAmount,
        uint96 _toUpkeepAmount,
        uint8 _maxStationUpkeeps
    )
        BastionConnector(_governor, _transferGovernanceDelay)
        UpkeepsCreator(_registrar, _linkToken, _keeperRegistry)
    {
        minWaitNext = _minWaitNext;
        minStationBalance = _minStationBalance;
        minUpkeepBalance = _minUpkeepBalance;
        toStationAmount = _toStationAmount;
        toUpkeepAmount = _toUpkeepAmount;
        maxStationUpkeeps = _maxStationUpkeeps;
    }

    function getLessBusyStation() public view returns (address station) {
        address _station = stations[0];
        uint8 _min = stationsInfo[_station].registeredUpkeeps;
        if (_min == 0 || stations.length == 1) {
            return _station;
        }

        for (uint32 i = 1; i < stations.length; i++) {
            uint8 _temp = stationsInfo[stations[i]].registeredUpkeeps;
            if (_min > _temp) {
                _min = _temp;
                _station = stations[i];
            }
        }
        return _station;
    }

    function getFlashBotUpkeepId(address _flashbot) external view returns (uint256) {
        UpkeepsStation _station = UpkeepsStation(flashBotRegisteredStation[_flashbot]);
        if (address(_station) == address(0)) {
            return 0;
        }
        return _station.flashbotUpkeep(_flashbot);
    }

    function initialize(
        address _bastion,
        string calldata name,
        uint32 gasLimit,
        bytes calldata checkData,
        uint96 _toUpkeepAmount
    ) external onlyGovernor onlyWhenNotInitialized {
        initializeConnector(_bastion);
        factoryUpkeepId = registerUpkeep(
            name,
            address(this),
            gasLimit,
            address(this),
            checkData,
            _toUpkeepAmount,
            0,
            address(this)
        );
    }

    function revokeFundsFromStation(
        address _station,
        address[] calldata _tokens,
        uint256[] calldata _amounts
    ) external onlyGovernor {
        UpkeepsStation(_station).transferToStation(_tokens, _amounts);
        emit RevokedFromStation(_station, _tokens, _amounts);
    }

    function setMinWaitNext(uint256 _minWaitNext) external onlyGovernor {
        minWaitNext = _minWaitNext;
    }

    function setMinStationBalance(uint96 _minStationBalance) external onlyGovernor {
        minStationBalance = _minStationBalance;
    }

    function setMinUpkeepBalance(uint96 _minUpkeepBalance) external onlyGovernor {
        minUpkeepBalance = _minUpkeepBalance;
    }

    function setToStationAmount(uint96 _toStationAmount) external onlyGovernor {
        toStationAmount = _toStationAmount;
    }

    function setToUpkeepAmount(uint96 _toUpkeepAmount) external onlyGovernor {
        toUpkeepAmount = _toUpkeepAmount;
    }

    function selfDismantle() external onlyGovernor onlyWhenInitialized {
        require(stations.length == 0, "Stations still registered");
        iRegistry.cancelUpkeep(factoryUpkeepId);
    }

    function withdrawStationFactoryUpkeep() external onlyGovernor onlyWhenInitialized {
        KeeperRegistryWithdrawInterface(address(iRegistry)).withdrawFunds(
            factoryUpkeepId,
            address(this)
        );
    }

    function deployUpkeepsStation(
        string memory name,
        uint32 gasLimit,
        bytes calldata checkData,
        uint96 _toUpkeepAmount
    ) external onlyGovernor onlyWhenInitialized {
        address _station = address(new UpkeepsStation(address(iLink), address(iRegistry)));
        stations.push(_station);
        StationInfo storage _stationInfo = stationsInfo[_station];
        _stationInfo.lastTimestamp = block.timestamp;
        _stationInfo.upkeepId = registerUpkeep(
            name,
            _station,
            gasLimit,
            address(this),
            checkData,
            _toUpkeepAmount,
            0,
            address(this)
        );
    }

    function disableUpkeepsStation(address _station, uint256 _index) external onlyGovernor {
        StationInfo storage _info = stationsInfo[_station];
        require(_station == stations[_index], "Wrong index");
        require(_info.lastTimestamp > 0 && _info.upkeepId != 0, "Not Registered Station");
        require(_info.registeredUpkeeps == 0, "Registered Upkeeps Must Be Zero");
        _info.lastTimestamp = 0;
        if (stations.length > 1) {
            stations[_index] = stations[stations.length - 1];
        }
        stations.pop();
        iRegistry.cancelUpkeep(_info.upkeepId);
    }

    function withdrawUpkeepsStation(address _station) external onlyGovernor {
        StationInfo storage _info = stationsInfo[_station];
        require(_info.lastTimestamp == 0 && _info.upkeepId != 0, "Must Be Disabled First");
        uint256 _upkeepId = _info.upkeepId;
        _info.upkeepId = 0;
        KeeperRegistryWithdrawInterface(address(iRegistry)).withdrawFunds(_upkeepId, address(this));
    }

    function automateFlashBot(
        string memory name,
        address _flashbot,
        uint32 _gasLimit,
        bytes calldata checkData,
        uint96 amount
    ) external onlyBastion onlyWhenInitialized {
        address _station = getLessBusyStation();
        flashBotRegisteredStation[_flashbot] = _station;
        StationInfo storage _info = stationsInfo[_station];
        _info.registeredUpkeeps += 1;
        uint256 _newUpkeepId = registerUpkeep(
            name,
            _flashbot,
            _gasLimit,
            _station,
            checkData,
            amount,
            0,
            address(this)
        );
        UpkeepsStation(_station).addUpkeep(_newUpkeepId, _flashbot);
    }

    function disableFlashBot(address _flashbot) external onlyGovernor onlyWhenInitialized {
        address _station = flashBotRegisteredStation[_flashbot];
        require(_station != address(0), "Invalid Flashbot");
        flashBotRegisteredStation[_flashbot] = address(0);
        StationInfo storage _info = stationsInfo[_station];
        _info.registeredUpkeeps -= 1;
        UpkeepsStation(_station).removeUpkeep(_flashbot);
    }

    function withdrawCanceledFlashBotUpkeeps(address _station, uint256 _upkeepsNumber)
        external
        onlyGovernor
    {
        require(stationsInfo[_station].lastTimestamp > 0, "Not Registered Station");
        UpkeepsStation(_station).withdrawCanceledUpkeeps(_upkeepsNumber);
    }

    function withdrawAllCanceledFlashBotUpkeeps() external onlyGovernor {
        for (uint256 i = 0; i < stations.length; i++) {
            UpkeepsStation(stations[i]).withdrawCanceledUpkeeps(0);
        }
    }

    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 linkBalance = iLink.balanceOf(address(this));
        (, , , uint96 _factoryBalance, , , , ) = iRegistry.getUpkeep(factoryUpkeepId);
        if (_factoryBalance < minUpkeepBalance && linkBalance > toUpkeepAmount) {
            upkeepNeeded = true;
            performData = abi.encode(uint8(0), uint256(0));
        } else if (linkBalance > toUpkeepAmount) {
            for (uint256 i = 0; i < stations.length; i++) {
                address _station = stations[i];
                uint96 _balance = uint96(iLink.balanceOf(_station));
                StationInfo memory _info = stationsInfo[stations[i]];
                (, , , uint96 upkeepBalance, , , , ) = iRegistry.getUpkeep(_info.upkeepId);
                if (upkeepBalance < minUpkeepBalance) {
                    upkeepNeeded = true;
                    performData = abi.encode(uint8(1), i);
                    break;
                } else if (_balance < minStationBalance) {
                    upkeepNeeded = true;
                    performData = abi.encode(uint8(2), i);
                    break;
                }
            }
        }
    }

    function performUpkeep(bytes calldata performData) external override onlyWhenInitialized {
        (uint8 _mode, uint256 _index) = abi.decode(performData, (uint8, uint256));
        uint96 amount;
        if (_mode == 0) {
            amount = toStationAmount;
            (, , , uint96 _factoryBalance, , , , ) = iRegistry.getUpkeep(factoryUpkeepId);
            require(_factoryBalance < minUpkeepBalance, "Not Needed");
            iLink.approve(address(iRegistry), amount);
            iRegistry.addFunds(factoryUpkeepId, amount);
            emit FactoryUpkeepRefueled(factoryUpkeepId, amount);
        } else if (_mode == 1) {
            amount = toUpkeepAmount;
            iLink.approve(address(iRegistry), amount);
            uint256 _upkeepId = stationsInfo[stations[_index]].upkeepId;
            (, , , uint96 _upkeepBalance, , , , ) = iRegistry.getUpkeep(_upkeepId);
            require(_upkeepBalance < minUpkeepBalance, "Not Needed");
            iRegistry.addFunds(_upkeepId, amount);
            emit StationUpkeepRefueled(_upkeepId, amount);
        } else if (_mode == 2) {
            amount = toStationAmount;
            address _station = stations[_index];
            uint96 _stationBalance = uint96(iLink.balanceOf(_station));
            require(_stationBalance < minStationBalance, "Not Needed");
            iLink.transfer(_station, toStationAmount);
            emit TransferredToStation(_station, amount);
        } else {
            revert("INVALID");
        }
    }
}
