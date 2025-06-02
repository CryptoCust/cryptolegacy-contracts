
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/ISignatureRoleTimelock.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title SignatureRoleTimelock
 * @notice Provides timelocked role-based signature authorization for executing calls.
 *         Role assignments and signature role associations are enforced with a timelock delay.
 * @dev Inherits from AccessControl for role management and ReentrancyGuard for security.
 */
contract SignatureRoleTimelock is ISignatureRoleTimelock, AccessControl, ReentrancyGuardUpgradeable {
    /// @notice The administrator role is the default admin role.
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    /// @notice The maximum timelock duration is 7 days.
    uint128 public constant MAX_TIMELOCK_DURATION = 7 days;

    uint128 public constant MAX_EXECUTION_PERIOD_LOWER_BOUND = 7 days;
    uint128 public constant MAX_EXECUTION_PERIOD_UPPER_BOUND = 21 days;

    /// @notice The maximum period during which an executed call remains valid is initially set to 14 days.
    uint128 public maxExecutionPeriod = 14 days;

    /// @notice Mapping from role identifier to array of accounts holding that role.
    mapping(bytes32 => address[]) public roleAccounts;
    /// @notice Mapping from a target contract and function selector to its assigned signature attributes.
    mapping(address => mapping(bytes4 => SignatureAttr)) public signatureRoles;
    /// @notice Mapping from a target address to an array of its function selectors with assigned signature roles.
    mapping(address => bytes4[]) public targetSigs;
    /// @notice An array of target addresses that have signature roles.
    address[] public targets;

    /// @notice Mapping from a scheduled call ID to its call request details.
    mapping(bytes32 => CallRequest) public pendingCalls;
    /// @notice Array of scheduled call IDs.
    bytes32[] public callsIds;

    /**
     * @notice Constructor for the SignatureRoleTimelock contract.
     * @dev Assigns the deployer as an ADMIN_ROLE and assigns initial signature roles.
     *      It also accepts an array of AddressRoleInput to add role accounts and an array of SignatureToAdd
     *      to add associated signature roles with a timelock.
     * @param _adminTimelock The timelock duration for admin-related signatures.
     * @param _roles An array of AddressRoleInput structs for initial role account assignments.
     * @param _sigs An array of SignatureToAdd structs for initial signature role configuration.
     */
    constructor(
        uint128 _adminTimelock,
        ISignatureRoleTimelock.AddressRoleInput[] memory _roles,
        SignatureToAdd[] memory _sigs,
        address _adminAccount
    ) initializer {
        _addRoleAccount(ADMIN_ROLE, _adminAccount);
        // Add signature roles for functions that manage signature roles.
        _addSignatureRole(address(this), SignatureRoleTimelock(this).setRoleAccounts.selector, ADMIN_ROLE, _adminTimelock);
        _addSignatureRole(address(this), SignatureRoleTimelock(this).addSignatureRoleList.selector, ADMIN_ROLE, _adminTimelock);
        _addSignatureRole(address(this), SignatureRoleTimelock(this).removeSignatureRoleList.selector, ADMIN_ROLE, _adminTimelock);
        _addSignatureRole(address(this), SignatureRoleTimelock(this).setMaxExecutionPeriod.selector, ADMIN_ROLE, _adminTimelock);
        // Assign additional role accounts provided in the input.
        for (uint256 i = 0; i < _roles.length; i++) {
            _addRoleAccount(_roles[i].role, _roles[i].newAccount);
        }
        // Add initial signature roles for target contracts.
        for (uint256 i = 0; i < _sigs.length; i++) {
            _addSignatureRole(_sigs[i].target, _sigs[i].signature, _sigs[i].role, _sigs[i].timelock);
        }
        __ReentrancyGuard_init();
    }

    /**
     * @notice Modifier that restricts calls to be made only by the contract itself.
     * @dev Reverts with CallerNotCurrentAddress if msg.sender is not address(this).
     */
    modifier onlyCurrentAddress() {
        if (msg.sender != address(this))
            revert CallerNotCurrentAddress();
        _;
    }

    /**
     * @notice Sets the maximum execution period for scheduled calls.
     * @dev Can only be called by the contract itself (via onlyCurrentAddress). Reverts if _maxExecutionPeriod is less
     *      than MAX_EXECUTION_PERIOD_LOWER_BOUND or more than MAX_EXECUTION_PERIOD_UPPER_BOUND.
     * @param _maxExecutionPeriod The maximum period (in seconds) during which a scheduled call remains valid.
     */
    function setMaxExecutionPeriod(uint128 _maxExecutionPeriod) external onlyCurrentAddress {
        if (_maxExecutionPeriod < MAX_EXECUTION_PERIOD_LOWER_BOUND || _maxExecutionPeriod > MAX_EXECUTION_PERIOD_UPPER_BOUND) {
            revert OutOfMaxExecutionPeriodBounds(MAX_EXECUTION_PERIOD_LOWER_BOUND, MAX_EXECUTION_PERIOD_UPPER_BOUND);
        }
        maxExecutionPeriod = _maxExecutionPeriod;
        emit SetMaxExecutionPeriod(_maxExecutionPeriod);
    }

    /**
     * @notice Sets the role accounts for various roles.
     * @dev Can only be called by the contract itself (via onlyCurrentAddress).
     *      The input list allows addition (if prevAccount is address(0)) and removal (if newAccount is address(0)) of role accounts,
     *      otherwise replace prevAccount with newAccount.
     * @param _list An array of AddressRoleInput structs describing changes to role accounts.
     */
    function setRoleAccounts(AddressRoleInput[] memory _list) external onlyCurrentAddress {
        for (uint256 i = 0; i < _list.length; i++) {
            if (_list[i].prevAccount == address(0)) {
                _addRoleAccount(_list[i].role, _list[i].newAccount);
            } else if (_list[i].newAccount == address(0)) {
                _removeRoleAccount(_list[i].role, _list[i].prevAccount);
            } else {
                _removeRoleAccount(_list[i].role, _list[i].prevAccount);
                _addRoleAccount(_list[i].role, _list[i].newAccount);
            }
        }
    }

    /**
     * @notice Adds a new account to a role.
     * @dev Internal function that reverts if the account already holds the role.
     *      It adds the account to the roleAccounts mapping and grants the role using AccessControl.
     * @param _role The role identifier.
     * @param _account The account address to add.
     */
    function _addRoleAccount(bytes32 _role, address _account) internal {
        if (hasRole(_role, _account))
            revert AlreadyHaveRole();

        roleAccounts[_role].push(_account);
        _grantRole(_role, _account);
        emit AddRoleAccount(_role, _account);
    }

    /**
     * @notice Internal helper that returns the index of an address in an array.
     * @dev Returns type(uint256).max if the address is not found.
     * @param _list The array of addresses.
     * @param _addr The address to search for.
     * @return index The index of _addr in _list.
     */
    function _getAddressIndex(address[] memory _list, address _addr) internal pure returns(uint){
        for (uint256 i = 0; i < _list.length; i++) {
            if (_list[i] == _addr) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @notice Internal helper that returns the index of a bytes4 value in an array.
     * @dev Returns type(uint256).max if the value is not found.
     * @param _list The array of bytes4 values.
     * @param _hash The bytes4 value to search for.
     * @return index The index of _hash in _list.
     */
    function _getBytes4Index(bytes4[] memory _list, bytes4 _hash) internal pure returns(uint){
        for (uint256 i = 0; i < _list.length; i++) {
            if (_list[i] == _hash) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @notice Removes an account from a role.
     * @dev Reverts if the account does not have the role.
     *      Removes the account from the roleAccounts mapping and revokes the role.
     * @param _role The role identifier.
     * @param _account The account address to remove.
     */
    function _removeRoleAccount(bytes32 _role, address _account) internal {
        if (!hasRole(_role, _account))
            revert DoesntHaveRole();
        uint256 removeIndex = _getAddressIndex(roleAccounts[_role], _account);
        if (roleAccounts[_role][removeIndex] != _account)
            revert IncorrectRoleIndex();

        uint256 lastIndex = roleAccounts[_role].length - 1;
        if (removeIndex != lastIndex) {
            roleAccounts[_role][removeIndex] = roleAccounts[_role][lastIndex];
        }
        roleAccounts[_role].pop();
        _revokeRole(_role, _account);
        emit RemoveRoleAccount(_role, _account);
    }

    function renounceRole(bytes32, address) public pure override {
        revert DisabledFunction();
    }

    /**
     * @notice Adds signature roles for a list of target functions.
     * @dev Can only be called by the contract itself (via onlyCurrentAddress).
     * @param _sigs An array of SignatureToAdd structs containing target, signature, role, and timelock.
     */
    function addSignatureRoleList(SignatureToAdd[] memory _sigs) external onlyCurrentAddress {
        for (uint256 i = 0; i < _sigs.length; i++) {
            _addSignatureRole(_sigs[i].target, _sigs[i].signature, _sigs[i].role, _sigs[i].timelock);
        }
    }

    /**
     * @notice Internal function to add a signature role for a given target and function selector.
     * @dev Reverts if the role does not exist, the signature already exists, or the timelock exceeds MAX_TIMELOCK_DURATION.
     *      If _timelock is 0, it is set to 1.
     * @param _target The target contract address.
     * @param _signature The function selector.
     * @param _role The required role for this signature.
     * @param _timelock The timelock duration in seconds.
     */
    function _addSignatureRole(address _target, bytes4 _signature, bytes32 _role, uint128 _timelock) internal {
        if (roleAccounts[_role].length == 0)
            revert RoleDontExist();

        if (signatureRoles[_target][_signature].role != bytes32(0))
            revert SignatureAlreadyExists();

        if (_timelock > MAX_TIMELOCK_DURATION)
            revert OutOfTimelockBounds(MAX_TIMELOCK_DURATION);

        if(_timelock == 0)
            _timelock = 1;

        signatureRoles[_target][_signature] = SignatureAttr(_role, _timelock);
        targetSigs[_target].push(_signature);
        uint256 targetIndex = _getAddressIndex(targets, _target);
        if (targetIndex == type(uint256).max) {
            targets.push(_target);
            emit AddTarget(_target);
        }
        emit AddSignatureRole(_target, _signature, _role, _timelock);
    }

    /**
     * @notice Removes signature roles for a list of target functions.
     * @dev Can only be called by the contract itself (via onlyCurrentAddress).
     * @param _sigsToRemove An array of SignatureToRemove structs containing target and signature.
     */
    function removeSignatureRoleList(SignatureToRemove[] memory _sigsToRemove) external onlyCurrentAddress {
        for (uint256 i = 0; i < _sigsToRemove.length; i++) {
            _removeSignatureRole(_sigsToRemove[i].target, _sigsToRemove[i].signature);
        }
    }

    /**
     * @notice Internal function to remove a signature role from a target.
     * @dev Deletes the signature role and removes the selector from the targetSigs array.
     *      If the target has no more signature selectors, it is removed from the targets array.
     * @param _target The target contract address.
     * @param _signature The function selector to remove.
     */
    function _removeSignatureRole(address _target, bytes4 _signature) internal {
        delete signatureRoles[_target][_signature];
        uint256 signatureIndex = _getBytes4Index(targetSigs[_target], _signature);
        if (targetSigs[_target][signatureIndex] != _signature)
            revert IncorrectSignatureIndex();

        uint256 lastIndex = targetSigs[_target].length - 1;
        if (signatureIndex != lastIndex) {
            targetSigs[_target][signatureIndex] = targetSigs[_target][lastIndex];
        }
        targetSigs[_target].pop();

        if (targetSigs[_target].length == 0) {
            uint256 targetIndex = _getAddressIndex(targets, _target);
            uint256 lastTargetIndex = targets.length - 1;
            if (targetIndex != lastTargetIndex) {
                targets[targetIndex] = targets[lastTargetIndex];
            }
            targets.pop();
            emit RemoveTarget(_target);
        }
        emit RemoveSignatureRole(_target, _signature);
    }

    /**
     * @notice Schedules a batch of calls by storing their required execution time and data.
     * @dev If `_executeAfter` is not yet reached, the calls remain pending. The calls can be canceled before execution or executed later.
     * @param _calls An array of CallToAdd, each specifying target and encoded call data.
     * @return callIds An array of identifiers for the scheduled calls.
     */
    function scheduleCallList(CallToAdd[] calldata _calls) external nonReentrant returns(bytes32[] memory callIds) {
        callIds = new bytes32[](_calls.length);
        for (uint256 i = 0; i < _calls.length; i++) {
            bytes4 sig = bytes4(_calls[i].data[:4]);
            callIds[i] = _scheduleCall(_calls[i].target, sig, _calls[i].data);
        }
    }

    /**
     * @notice Internal function to check that the caller holds the required role.
     * @param _role The required role identifier.
     */
    function _checkRole(bytes32 _role) internal view override {
        if (!hasRole(_role, msg.sender))
            revert CallerHaveNoRequiredRole(_role);
    }

    /**
     * @notice Internal function to schedule a call with a timelock.
     * @dev Checks that a signature timelock is set and that the caller holds the required role.
     *      Computes an executeAfter timestamp and creates a call request stored in pendingCalls.
     * @param _target The target contract address.
     * @param _sig The function selector.
     * @param _data The call data.
     * @return callId The identifier for the scheduled call.
     */
    function _scheduleCall(address _target, bytes4 _sig, bytes memory _data) internal returns(bytes32 callId) {
        SignatureAttr storage signAttr = signatureRoles[_target][_sig];

        if (signAttr.timelock == 0)
            revert SignatureTimeLockNotSet(_sig);

        _checkRole(signAttr.role);

        uint128 executeAfter = uint128(block.timestamp) + signAttr.timelock;
        callId = keccak256(abi.encode(_target, _data, msg.sender, executeAfter));

        if (pendingCalls[callId].executeAfter != 0)
            revert CallAlreadyScheduled();

        pendingCalls[callId] = CallRequest({
            caller: msg.sender,
            target: _target,
            data: _data,
            executeAfter: executeAfter,
            executeBefore: executeAfter + maxExecutionPeriod,
            pending: true
        });
        callsIds.push(callId);

        emit CallScheduled(callId, msg.sender, _target, _sig, executeAfter);
    }

    /**
     * @notice Executes a list of calls that have satisfied their timelock period.
     * @dev Iterates over `_callIds` and calls `_executeCall` for each.
     * @param _callIds An array of call IDs previously scheduled.
     */
    function executeCallList(bytes32[] memory _callIds) external nonReentrant {
        for (uint256 i = 0; i < _callIds.length; i++) {
            _executeCall(_callIds[i]);
        }
    }

    /**
     * @notice Internal function that executes a scheduled call.
     * @dev Verifies that the call is scheduled, pending, and that the timelock period has passed.
     *      The call is executed via a low-level call; revert reasons are bubbled up.
     * @param callId The identifier of the call to execute.
     */
    function _executeCall(bytes32 callId) internal {
        CallRequest storage request = pendingCalls[callId];

        if (request.executeAfter == 0)
            revert CallNotScheduled();

        if (!request.pending)
            revert NotPending();

        if (block.timestamp < request.executeAfter)
            revert TimelockActive();

        if (block.timestamp > request.executeBefore)
            revert TimelockExpired();

        request.pending = false;

        (bool success, bytes memory returnData) = request.target.call(request.data);
        if (!success)
            revert CallFailed(returnData);

        emit CallExecuted(callId, msg.sender, returnData);
    }

    /**
     * @notice Cancels a set of scheduled calls, preventing them from being executed later.
     * @dev Only ADMIN_ROLE can cancel. Calls `_cancelCall` on each ID.
     * @param _callIds An array of call IDs to cancel.
     */
    function cancelCallList(bytes32[] memory _callIds) external onlyRole(ADMIN_ROLE) nonReentrant {
        for (uint256 i = 0; i < _callIds.length; i++) {
            _cancelCall(_callIds[i]);
        }
    }

    /**
     * @notice Internal function that cancels a scheduled call.
     * @dev Verifies that the call is scheduled and pending before canceling it.
     * @param callId The identifier of the call to cancel.
     */
    function _cancelCall(bytes32 callId) internal {
        CallRequest storage request = pendingCalls[callId];

        if (request.executeAfter == 0)
            revert CallNotScheduled();
        if (!request.pending)
            revert NotPending();

        request.pending = false;

        emit CallCanceled(callId, msg.sender);
    }

    /**
     * @notice Returns the list of accounts assigned to a role.
     * @param _role The role identifier.
     * @return An array of addresses holding the role.
     */
    function getRoleAccounts(bytes32 _role) external view returns(address[] memory) {
        return roleAccounts[_role];
    }

    /**
     * @notice Returns the list of targets that have signature roles assigned.
     * @return An array of target contract addresses.
     */
    function getTargets() external view returns(address[] memory) {
        return targets;
    }

    /**
     * @notice Returns signature role details for a given target contract.
     * @param _target The target contract address.
     * @return result An array of TargetSigRes structs containing each function selector, its required role, and timelock.
     */
    function getTargetSigs(address _target) external view returns(TargetSigRes[] memory result) {
        bytes4[] memory sigs = targetSigs[_target];
        result = new TargetSigRes[](sigs.length);
        for (uint256 i = 0; i < sigs.length; i++) {
            result[i] = TargetSigRes(sigs[i], signatureRoles[_target][sigs[i]].role, signatureRoles[_target][sigs[i]].timelock);
        }
    }

    /**
     * @notice Helper function to compute a call ID based on target, call data, caller, and execution time.
     * @param target The target contract.
     * @param data The call data.
     * @param caller The account scheduling the call.
     * @param executeAfter The timestamp after which the call can be executed.
     * @return The computed call ID.
     */
    function getCallId(address target, bytes calldata data, address caller, uint256 executeAfter) public pure returns (bytes32) {
        return keccak256(abi.encode(target, data, caller, executeAfter));
    }

    /**
     * @notice Returns the details of a scheduled call.
     * @param _callId The call ID.
     * @return The CallRequest struct containing call details.
     */
    function getCall(bytes32 _callId) external view returns(CallRequest memory){
        return pendingCalls[_callId];
    }

    /**
     * @notice Returns a list of scheduled call IDs and their details starting from an offset.
     * @param _offset The starting index.
     * @param _limit The maximum number of calls to return.
     * @return ids An array of call IDs.
     * @return resCalls An array of CallRequest structs.
     */
    function getCallsList(uint256 _offset, uint256 _limit) external view returns(bytes32[] memory ids, CallRequest[] memory resCalls){
        resCalls = new CallRequest[](_limit);
        ids = new bytes32[](_limit);
        for (uint256 i = 0; i < _limit; i++) {
            ids[i] = callsIds[_offset + i];
            resCalls[i] = pendingCalls[ids[i]];
        }
    }

    /**
     * @notice Returns all scheduled call IDs.
     * @return An array of all call IDs.
     */
    function getCallIds() external view returns(bytes32[] memory){
        return callsIds;
    }

    /**
     * @notice Returns the number of scheduled calls.
     * @return The length of the callsIds array.
     */
    function getCallsLength() external view returns(uint256){
        return callsIds.length;
    }
}