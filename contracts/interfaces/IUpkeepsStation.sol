// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IUpkeepsStation {
    event UpkeepRegistered(uint256 indexed _id);
    event UpkeepRemoved(uint256 indexed _id);
    event UpkeepRefueled(uint256 indexed _id, uint96 indexed _amount);
    event TransferredToStation(address[] indexed _tokens, uint256[] indexed _amounts);

    function isRegisteredUpkeep(uint256 _upkeepId) external view returns (bool);

    function doesUpkeepNeedFunds(uint256 _upkeepId) external view returns (bool needFunds);

    function transferToStation(address[] calldata _tokens, uint256[] calldata _amounts) external;

    function addUpkeep(uint256 _upkeepId, address _flashbot) external;

    function removeUpkeep(address _flashbot) external;

    function withdrawCanceledUpkeeps(uint256 _upkeepsNumber) external;
}
