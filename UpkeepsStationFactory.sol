//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Governable {

    address public governor;
    address public pendingGovernor;
    uint256 public requestTimestamp;
    uint256 public immutable transferGovernanceDelay;

    event GovernanceTrasferred(address indexed _oldGovernor, address indexed _newGovernor);
    event PendingGovernorChanged(address indexed _pendingGovernor);

    constructor(address _governor, uint256 _transferGovernanceDelay) {
        governor = _governor;
        transferGovernanceDelay = _transferGovernanceDelay;
        emit GovernanceTrasferred(address(0), _governor);
    }

    modifier onlyGovernor() {
        require(msg.sender == governor, "Only Governor");
        _;
    }

    function setPendingGovernor(address _pendingGovernor) external onlyGovernor {
        require(_pendingGovernor != address(0), "Zero Address");
        pendingGovernor = _pendingGovernor;
        requestTimestamp = block.timestamp;
        emit PendingGovernorChanged(_pendingGovernor);
    }

    function transferGovernance() external {
        address _newGovernor = pendingGovernor;
        address _oldGovernor = governor;
        require(_newGovernor != address(0), "Zero Address");
        require(msg.sender == _oldGovernor || msg.sender == _newGovernor, "Forbidden");
        require(block.timestamp - requestTimestamp > transferGovernanceDelay, "Too Early");
        pendingGovernor = address(0);
        governor = _newGovernor;
        emit GovernanceTrasferred(_oldGovernor, _newGovernor);
    }
}

interface KeeperRegistrarInterface {
  function register(
    string memory name,
    bytes calldata encryptedEmail,
    address upkeepContract,
    uint32 gasLimit,
    address adminAddress,
    bytes calldata checkData,
    uint96 amount,
    uint8 source,
    address sender
  ) external;
}

interface IUpkeepsStation {

    event UpkeepRegistered(uint256 indexed _id);
    event UpkeepRemoved(uint256 indexed _id);
    event UpkeepRefueled(uint256 indexed _id, uint96 indexed _amount);
    event TransferredToStation(address[] indexed _tokens, uint256[] indexed _amounts);

    function isRegisteredUpkeep(uint256 _upkeepId) external view returns(bool);
    function doesUpkeepNeedFunds(uint256 _upkeepId) external view returns(bool needFunds);

    function transferToStation(
        address[] calldata _tokens, 
        uint256[] calldata _amounts
    ) external;

    function addUpkeep(uint256 _upkeepId, address _flashbot) external;
    function removeUpkeep(address _flashbot) external;
    function withdrawCanceledUpkeeps(uint256 _upkeepsNumber) external;
}

interface LinkTokenInterface {
  function allowance(address owner, address spender) external view returns (uint256 remaining);

  function approve(address spender, uint256 value) external returns (bool success);

  function balanceOf(address owner) external view returns (uint256 balance);

  function decimals() external view returns (uint8 decimalPlaces);

  function decreaseApproval(address spender, uint256 addedValue) external returns (bool success);

  function increaseApproval(address spender, uint256 subtractedValue) external;

  function name() external view returns (string memory tokenName);

  function symbol() external view returns (string memory tokenSymbol);

  function totalSupply() external view returns (uint256 totalTokensIssued);

  function transfer(address to, uint256 value) external returns (bool success);

  function transferAndCall(
    address to,
    uint256 value,
    bytes calldata data
  ) external returns (bool success);

  function transferFrom(
    address from,
    address to,
    uint256 value
  ) external returns (bool success);
}

library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly
                /// @solidity memory-safe-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/draft-IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    function safePermit(
        IERC20Permit token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

abstract contract BastionConnector is Governable {
    using SafeERC20 for IERC20;
    bool private initialized;
    address public bastion;

    event ConnectorInitialized(address indexed _bastion);
    event TransferredToBastion(address[] indexed _tokens, uint256[] indexed _amounts);

    constructor(
        address _governor,
        uint256 _transferGovernanceDelay
    ) Governable(_governor, _transferGovernanceDelay) {
        initialized = false;
    }

    function isInitialized() internal view returns (bool) {
        return initialized;
    }

    function initializeConnector(
        address _bastion
    ) internal onlyGovernor onlyWhenNotInitialized {
        initialized = true;
        bastion = _bastion;
        emit ConnectorInitialized(_bastion);
    }

    function transferToBastion(
        address[] calldata _tokens, 
        uint256[] calldata _amounts
    ) external onlyGovernor {
        for(uint256 i = 0;i < _tokens.length; i++) {
            IERC20(_tokens[i]).safeTransfer(bastion, _amounts[i]);
        }
        emit TransferredToBastion(_tokens, _amounts);
    }

    modifier onlyBastion() {
        require(msg.sender == bastion, "Not Initialized");
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

interface IUpkeepsStationFactory {

    event StationCreated(address indexed station);
    event StationDisabled(address indexed station);
    event UpkeepCreated(uint256 indexed id);
    event UpkeepCanceled(uint256 indexed id);
    event FactoryUpkeepRefueled(uint256 indexed id, uint96 indexed amount);
    event StationUpkeepRefueled(uint256 indexed id, uint96 indexed amount);
    event TransferredToStation(address indexed station, uint96 indexed amount);
    event RevokedFromStation(
        address indexed station, 
        address[] indexed tokens,
        uint256[] indexed amount
    );

    function stations(uint256) external view returns (address);
    function factoryUpkeepId() external view returns (uint256);
    function minWaitNext() external view returns (uint256);
    function minStationBalance() external view returns (uint96);
    function minUpkeepBalance() external view returns (uint96);
    function toStationAmount() external view returns (uint96);
    function toUpkeepAmount() external view returns (uint96);
    function maxStationUpkeeps() external view returns (uint8);
    function getLessBusyStation() external view returns (address station);
    function getFlashBotUpkeepId(address _flashbot) external view returns (uint256);

    function setMinWaitNext(uint256 _interval) external;
    function setMinStationBalance(uint96 _minStationBalance) external;
    function setMinUpkeepBalance(uint96 _minUpkeepBalance) external;
    function setToStationAmount(uint96 _toStationAmount) external;
    function setToUpkeepAmount(uint96 _toUpkeepAmount) external;
    function selfDismantle() external;
    function withdrawStationFactoryUpkeep() external;

    function deployUpkeepsStation(
        string memory name,
        uint32 gasLimit,
        bytes calldata checkData,
        uint96 amount
    ) external;

    function disableUpkeepsStation(address _station) external;
    function withdrawUpkeepsStation(address _station) external;

    function automateFlashBot(
        string memory name,
        address flashbot,
        uint32 gasLimit,
        bytes calldata checkData,
        uint96 amount
    ) external;

    function disableFlashBot(address _flashbot) external;

    function withdrawCanceledFlashBotUpkeeps(address _station, uint256 _upkeepsNumber) external;
    function withdrawAllCanceledFlashBotUpkeeps() external; 
}

interface KeeperRegistryWithdrawInterface {
  function withdrawFunds(uint256 _id, address _to) external;
}

interface KeeperCompatibleInterface {
  /**
   * @notice method that is simulated by the keepers to see if any work actually
   * needs to be performed. This method does does not actually need to be
   * executable, and since it is only ever simulated it can consume lots of gas.
   * @dev To ensure that it is never called, you may want to add the
   * cannotExecute modifier from KeeperBase to your implementation of this
   * method.
   * @param checkData specified in the upkeep registration so it is always the
   * same for a registered upkeep. This can easily be broken down into specific
   * arguments using `abi.decode`, so multiple upkeeps can be registered on the
   * same contract and easily differentiated by the contract.
   * @return upkeepNeeded boolean to indicate whether the keeper should call
   * performUpkeep or not.
   * @return performData bytes that the keeper should call performUpkeep with, if
   * upkeep is needed. If you would like to encode data to decode later, try
   * `abi.encode`.
   */
  function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);

  /**
   * @notice method that is actually executed by the keepers, via the registry.
   * The data returned by the checkUpkeep simulation will be passed into
   * this method to actually be executed.
   * @dev The input to this method should not be trusted, and the caller of the
   * method should not even be restricted to any single registry. Anyone should
   * be able call it, and the input should be validated, there is no guarantee
   * that the data passed in is the performData returned from checkUpkeep. This
   * could happen due to malicious keepers, racing keepers, or simply a state
   * change while the performUpkeep transaction is waiting for confirmation.
   * Always validate the data passed in.
   * @param performData is the data which was passed back from the checkData
   * simulation. If it is encoded, it can easily be decoded into other types by
   * calling `abi.decode`. This data should not be trusted, and should be
   * validated against the contract's current state.
   */
  function performUpkeep(bytes calldata performData) external;
}

/**
 * @notice config of the registry
 * @dev only used in params and return values
 * @member paymentPremiumPPB payment premium rate oracles receive on top of
 * being reimbursed for gas, measured in parts per billion
 * @member flatFeeMicroLink flat fee paid to oracles for performing upkeeps,
 * priced in MicroLink; can be used in conjunction with or independently of
 * paymentPremiumPPB
 * @member blockCountPerTurn number of blocks each oracle has during their turn to
 * perform upkeep before it will be the next keeper's turn to submit
 * @member checkGasLimit gas limit when checking for upkeep
 * @member stalenessSeconds number of seconds that is allowed for feed data to
 * be stale before switching to the fallback pricing
 * @member gasCeilingMultiplier multiplier to apply to the fast gas feed price
 * when calculating the payment ceiling for keepers
 * @member minUpkeepSpend minimum LINK that an upkeep must spend before cancelling
 * @member maxPerformGas max executeGas allowed for an upkeep on this registry
 * @member fallbackGasPrice gas price used if the gas price feed is stale
 * @member fallbackLinkPrice LINK price used if the LINK price feed is stale
 * @member transcoder address of the transcoder contract
 * @member registrar address of the registrar contract
 */
struct Config {
  uint32 paymentPremiumPPB;
  uint32 flatFeeMicroLink; // min 0.000001 LINK, max 4294 LINK
  uint24 blockCountPerTurn;
  uint32 checkGasLimit;
  uint24 stalenessSeconds;
  uint16 gasCeilingMultiplier;
  uint96 minUpkeepSpend;
  uint32 maxPerformGas;
  uint256 fallbackGasPrice;
  uint256 fallbackLinkPrice;
  address transcoder;
  address registrar;
}

/**
 * @notice config of the registry
 * @dev only used in params and return values
 * @member nonce used for ID generation
 * @ownerLinkBalance withdrawable balance of LINK by contract owner
 * @numUpkeeps total number of upkeeps on the registry
 */
struct State {
  uint32 nonce;
  uint96 ownerLinkBalance;
  uint256 expectedLinkBalance;
  uint256 numUpkeeps;
}

interface KeeperRegistryBaseInterface {
  function registerUpkeep(
    address target,
    uint32 gasLimit,
    address admin,
    bytes calldata checkData
  ) external returns (uint256 id);

  function performUpkeep(uint256 id, bytes calldata performData) external returns (bool success);

  function cancelUpkeep(uint256 id) external;

  function addFunds(uint256 id, uint96 amount) external;

  function setUpkeepGasLimit(uint256 id, uint32 gasLimit) external;

  function getUpkeep(uint256 id)
    external
    view
    returns (
      address target,
      uint32 executeGas,
      bytes memory checkData,
      uint96 balance,
      address lastKeeper,
      address admin,
      uint64 maxValidBlocknumber,
      uint96 amountSpent
    );

  function getActiveUpkeepIDs(uint256 startIndex, uint256 maxCount) external view returns (uint256[] memory);

  function getKeeperInfo(address query)
    external
    view
    returns (
      address payee,
      bool active,
      uint96 balance
    );

  function getState()
    external
    view
    returns (
      State memory,
      Config memory,
      address[] memory
    );
}

/**
 * @dev The view methods are not actually marked as view in the implementation
 * but we want them to be easily queried off-chain. Solidity will not compile
 * if we actually inherit from this interface, so we document it here.
 */
interface KeeperRegistryInterface is KeeperRegistryBaseInterface {
  function checkUpkeep(uint256 upkeepId, address from)
    external
    view
    returns (
      bytes memory performData,
      uint256 maxLinkPayment,
      uint256 gasLimit,
      int256 gasWei,
      int256 linkEth
    );
}

interface KeeperRegistryExecutableInterface is KeeperRegistryBaseInterface {
  function checkUpkeep(uint256 upkeepId, address from)
    external
    returns (
      bytes memory performData,
      uint256 maxLinkPayment,
      uint256 gasLimit,
      uint256 adjustedGasWei,
      uint256 linkEth
    );
}

abstract contract UpkeepsCreator {
    address public immutable registrar;
    LinkTokenInterface public immutable iLink;
    KeeperRegistryInterface public immutable iRegistry;

    constructor(
        address _registrar,
        address _linkToken,
        address _keeperRegistry
    ){
        registrar = _registrar;
        iLink = LinkTokenInterface(_linkToken);
        iRegistry = KeeperRegistryInterface(_keeperRegistry);
    }

    function registerUpkeep(
        string memory name,
        address upkeepContract,
        uint32 gasLimit,
        address adminAddress,
        bytes calldata checkData,
        uint96 amount,
        uint8 source,
        address sender
    ) internal returns (uint256 upkeepID) {
        (State memory state, Config memory _c, address[] memory _k) = iRegistry.getState();
        uint256 oldNonce = state.nonce;

        bytes memory payload = abi.encode(
          name,
          hex'',
          upkeepContract,
          gasLimit,
          adminAddress,
          checkData,
          amount,
          source,
          sender
        );

        iLink.transferAndCall(
            registrar, 
            amount, 
            bytes.concat(KeeperRegistrarInterface.register.selector, payload)
        );
        (state, _c, _k) = iRegistry.getState();
        uint256 newNonce = state.nonce;
        if (newNonce == oldNonce + 1) {
            upkeepID = uint256(
                keccak256(abi.encodePacked(blockhash(block.number - 1), address(iRegistry), uint32(oldNonce)))
            );
        } else {
            revert("auto-approve disabled");
        }
    }
}

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

    constructor(
        address _iLink,
        address _iRegistry
    ){
        stationsFactory = msg.sender;
        iLink = LinkTokenInterface(_iLink);
        iRegistry = KeeperRegistryInterface(_iRegistry);
    }

    function isRegisteredUpkeep(uint256 _upkeepId) public view returns(bool) {
        return upkeepsInfo[_upkeepId].lastTimestamp > 0;
    }

    function doesUpkeepNeedFunds(uint256 _upkeepId) public view returns(bool needFunds) {
        uint256 _minWaitNext = IUpkeepsStationFactory(stationsFactory).minWaitNext();
        uint256 _timestamp = upkeepsInfo[_upkeepId].lastTimestamp;        
        if(_timestamp > 0 && block.timestamp - _timestamp > _minWaitNext) {
            ( , , , uint96 balance, , , , ) = iRegistry.getUpkeep(_upkeepId);
            uint96 _minUpkeepBalance = IUpkeepsStationFactory(stationsFactory).minUpkeepBalance();
            if(balance < _minUpkeepBalance) {
                return true;
            }            
        }
        return false;
    }

    function transferToStation(
        address[] calldata _tokens, 
        uint256[] calldata _amounts
    ) external onlyStationFactory {
        for(uint256 i = 0;i < _tokens.length; i++) {
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
        require(_upkeepId != 0, "No Upkeep Registered");
        flashbotUpkeep[_flashbot] = 0;
        UpkeepInfo storage _infoDel = upkeepsInfo[_upkeepId];
        UpkeepInfo storage _infoMove = upkeepsInfo[upkeepsRegistered[upkeepsRegistered.length - 1]];
        require(_infoDel.lastTimestamp > 0, "Not Registered Upkeep");
        _infoMove.arrayIndex = _infoDel.arrayIndex;
        _infoDel.lastTimestamp = 0;
        _infoDel.arrayIndex = 0;
        upkeepsRegistered[_infoDel.arrayIndex] = upkeepsRegistered[upkeepsRegistered.length - 1];
        upkeepsRegistered.pop();
        canceledToWithdraw.push(_upkeepId);
        iRegistry.cancelUpkeep(_upkeepId);
        emit UpkeepRemoved(_upkeepId);
    }

    function withdrawCanceledUpkeeps(uint256 _upkeepsNumber) external onlyStationFactory {
        uint canceledToWithdrawLength = canceledToWithdraw.length;
        if(canceledToWithdrawLength > 0) {
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
        override
        view
        returns (
            bool upkeepNeeded, 
            bytes memory performData
        )
    {
        uint96 _toUpkeepAmount = IUpkeepsStationFactory(stationsFactory).toUpkeepAmount();
        uint256 linkBalance = iLink.balanceOf(address(this));     
        if(linkBalance > _toUpkeepAmount) {
            for(uint256 i = 0; i < upkeepsRegistered.length; i++) {
                if(doesUpkeepNeedFunds(upkeepsRegistered[i])) {
                    upkeepNeeded = true;
                    performData = abi.encode(i);
                    return(upkeepNeeded, performData);
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
    ) BastionConnector(_governor, _transferGovernanceDelay) UpkeepsCreator(_registrar, _linkToken, _keeperRegistry) {
        minWaitNext = _minWaitNext;
        minStationBalance = _minStationBalance;
        minUpkeepBalance = _minUpkeepBalance;
        toStationAmount = _toStationAmount;
        toUpkeepAmount = _toUpkeepAmount;
        maxStationUpkeeps = _maxStationUpkeeps;
    }

    function getLessBusyStation() public view returns(address station) {
        address _station = stations[0];
        uint8 _min = stationsInfo[_station].registeredUpkeeps;
        if(_min == 0 || stations.length == 1) {
            return _station;
        }

        for(uint32 i = 1; i < stations.length; i++) {
            uint8 _temp = stationsInfo[stations[i]].registeredUpkeeps;
            if(_min > _temp) {
                _min = _temp;
                _station = stations[i]; 
            }
        }
        return _station;
    }

    function getFlashBotUpkeepId(address _flashbot) external view returns(uint256) {
        UpkeepsStation _station = UpkeepsStation(flashBotRegisteredStation[_flashbot]);
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
        require(stations.length == 0, "Stations Registered Must Be Zero");
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
        address _station = address(
            new UpkeepsStation(
                address(iLink),
                address(iRegistry) 
            )
        );
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

    function disableUpkeepsStation(address _station) external onlyGovernor {
        StationInfo storage _info = stationsInfo[_station];
        require(_info.lastTimestamp > 0 && _info.upkeepId != 0, "Not Registered Station");
        require(_info.registeredUpkeeps == 0, "Registered Upkeeps Must Be Zero");
        _info.lastTimestamp = 0;
        iRegistry.cancelUpkeep(_info.upkeepId);
    }

    function withdrawUpkeepsStation(address _station) external onlyGovernor {
        StationInfo storage _info = stationsInfo[_station];
        require(_info.lastTimestamp == 0 && _info.upkeepId != 0, "Must Be Disabled First");
        uint256 _upkeepId = _info.upkeepId;
        _info.upkeepId = 0;
        KeeperRegistryWithdrawInterface(address(iRegistry)).withdrawFunds(
            _upkeepId, 
            address(this)
        );        
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

    function withdrawCanceledFlashBotUpkeeps(address _station, uint256 _upkeepsNumber) external onlyGovernor {
        require(stationsInfo[_station].lastTimestamp > 0, "Not Registered Station");
        UpkeepsStation(_station).withdrawCanceledUpkeeps(_upkeepsNumber);
    }

    function withdrawAllCanceledFlashBotUpkeeps() external onlyGovernor {
        for(uint256 i = 0; i < stations.length; i++) {
            UpkeepsStation(stations[i]).withdrawCanceledUpkeeps(0);
        }
    }
    
    function checkUpkeep(bytes calldata) 
        external
        override
        view
        returns (
            bool upkeepNeeded, 
            bytes memory performData
        )
    {
        uint256 linkBalance = iLink.balanceOf(address(this));
        ( , , , uint96 _factoryBalance, , , , ) = iRegistry.getUpkeep(factoryUpkeepId);
        if(_factoryBalance < minUpkeepBalance && linkBalance > toUpkeepAmount) {
            upkeepNeeded = true;
            performData = abi.encode(uint8(0), uint256(0));
        } else if(linkBalance > toUpkeepAmount) {
            for(uint256 i = 0; i < stations.length; i++) {
                address _station = stations[i];
                uint96 _balance = uint96(iLink.balanceOf(_station));
                StationInfo memory _info = stationsInfo[stations[i]];
                ( , , , uint96 upkeepBalance, , , , ) = iRegistry.getUpkeep(_info.upkeepId);
                if(upkeepBalance < minUpkeepBalance) {
                    upkeepNeeded = true;
                    performData = abi.encode(uint8(1), i);
                    break;
                } else if(_balance < minStationBalance) {
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
            ( , , , uint96 _factoryBalance, , , , ) = iRegistry.getUpkeep(factoryUpkeepId);
            require(
                _factoryBalance < minUpkeepBalance,
                "Not Needed"
            );
            iLink.approve(address(iRegistry), amount);
            iRegistry.addFunds(factoryUpkeepId, amount);
            emit FactoryUpkeepRefueled(factoryUpkeepId, amount);
        } else if (_mode == 1) {
            amount = toUpkeepAmount;
            iLink.approve(address(iRegistry), amount);
            uint256 _upkeepId = stationsInfo[stations[_index]].upkeepId;
            ( , , , uint96 _upkeepBalance, , , , ) = iRegistry.getUpkeep(_upkeepId);
            require(
                _upkeepBalance < minUpkeepBalance,
                "Not Needed"
            );
            iRegistry.addFunds(_upkeepId, amount);
            emit StationUpkeepRefueled(_upkeepId, amount);
        } else if(_mode == 2) {
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