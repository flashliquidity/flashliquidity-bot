//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Governable} from "./Governable.sol";

abstract contract BastionConnector is Governable {
    using SafeERC20 for IERC20;
    bool private initialized;
    address public bastion;

    event ConnectorInitialized(address indexed _bastion);
    event TransferredToBastion(address[] indexed _tokens, uint256[] indexed _amounts);

    constructor(address _governor, uint256 _transferGovernanceDelay)
        Governable(_governor, _transferGovernanceDelay)
    {
        initialized = false;
    }

    function initializeConnector(address _bastion) internal onlyGovernor onlyWhenNotInitialized {
        initialized = true;
        bastion = _bastion;
        emit ConnectorInitialized(_bastion);
    }

    function transferToBastion(address[] calldata _tokens, uint256[] calldata _amounts)
        external
        onlyGovernor
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).safeTransfer(bastion, _amounts[i]);
        }
        emit TransferredToBastion(_tokens, _amounts);
    }

    modifier onlyBastion() {
        require(msg.sender == bastion, "Not Bastion");
        _;
    }

    modifier onlyWhenInitialized() {
        require(initialized, "Not Initialized");
        _;
    }

    modifier onlyWhenNotInitialized() {
        require(!initialized, "Already Initialized");
        _;
    }
}
