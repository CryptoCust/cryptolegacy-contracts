/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./interfaces/Flags.sol";
import "./interfaces/ICallProxy.sol";
import "./interfaces/IFeeRegistry.sol";
import "./interfaces/ILifetimeNft.sol";
import "./interfaces/IDeBridgeGate.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title LockChainGate
 * @notice Handles cross-chain locking, unlocking, and transfer of lifetime NFTs.
 */
contract LockChainGate is Ownable, ReentrancyGuardUpgradeable, ILockChainGate {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Flags for uint256;

    bytes32 constant internal LCG_STORAGE_POSITION = keccak256("crypto_legacy.lock_chain_gate.storage");

    /**
     * @notice Constructs the LockChainGate contract.
     * @dev Disables initializers to prevent re-initialization.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Returns the storage pointer for LockChainGate.
     * @dev Uses inline assembly to access the storage slot defined by LCG_STORAGE_POSITION.
     * @return ls The LCGStorage struct stored at the designated slot.
     */
    function lockChainGateStorage() internal pure returns (LCGStorage storage ls) {
        bytes32 position = LCG_STORAGE_POSITION;
        assembly {
            ls.slot := position
        }
    }

    /**
     * @notice Internal initializer for LockChainGate.
     * @dev Sets the LifetimeNft contract, NFT lock period, and transfers ownership.
     * @param _lifetimeNft The LifetimeNft contract address.
     * @param _lockPeriod The NFT lock period in seconds.
     * @param _transferTimeout The timeout between lock and transfer.
     * @param _owner The address to become the owner.
     */
    function _initializeLockChainGate(ILifetimeNft _lifetimeNft, uint64 _lockPeriod, uint64 _transferTimeout, address _owner) internal {
        LCGStorage storage ls = lockChainGateStorage();
        ls.lifetimeNft = _lifetimeNft;
        ls.lockPeriod = _lockPeriod;
        ls.transferTimeout = _transferTimeout;
        emit SetLockPeriodConfig(_lockPeriod, _transferTimeout);
        _transferOwnership(_owner);
    }

    /**
     * @notice Sets or unsets an operator authorized to perform NFT lock operations.
     * @dev Updates the lockOperators set.
     * @param _operator The address to add or remove.
     * @param _isAdd True to add the operator; false to remove.
     */
    function setLockOperator(address _operator, bool _isAdd) external onlyOwner {
        LCGStorage storage ls = lockChainGateStorage();
        if (_isAdd) {
            ls.lockOperators.add(_operator);
            emit AddLockOperator(_operator);
        } else {
            ls.lockOperators.remove(_operator);
            emit RemoveLockOperator(_operator);
        }
    }

    /**
     * @notice Sets the deBridgeGate contract.
     * @param _deBridgeGate The address of the deBridgeGate contract.
     */
    function setDebridgeGate(address _deBridgeGate) external onlyOwner {
        LCGStorage storage ls = lockChainGateStorage();
        ls.deBridgeGate = IDeBridgeGate(_deBridgeGate);
        emit SetDeBridgeGate(_deBridgeGate);
    }

    /**
     * @notice Sets the native fee for a specific chain for cross-chain messages.
     * @dev Updates the deBridgeNativeFee mapping for the given chain ID.
     * @param _chainId The target chain ID.
     * @param _nativeFee The fee amount in native currency.
     */
    function setDebridgeNativeFee(uint256 _chainId, uint256 _nativeFee) external onlyOwner {
        LCGStorage storage ls = lockChainGateStorage();
        ls.deBridgeNativeFee[_chainId] = _nativeFee;
        emit SetDeBridgeNativeFee(_chainId, _nativeFee);
    }

    /**
     * @notice Internal function to set the destination chain contract.
     * @param _chainId The destination chain ID.
     * @param _chainContract The contract address on the destination chain.
     */
    function _setDestinationChainContract(uint256 _chainId, address _chainContract) internal {
        LCGStorage storage ls = lockChainGateStorage();
        ls.destinationChainContracts[_chainId] = _chainContract;
        emit SetDestinationChainContract(_chainId, _chainContract);
    }

    /**
     * @notice Sets the destination chain contract.
     * @param _chainId The destination chain ID.
     * @param _chainContract The contract address on the destination chain.
     */
    function setDestinationChainContract(uint256 _chainId, address _chainContract) external onlyOwner {
        _setDestinationChainContract(_chainId, _chainContract);
    }

    /**
    * @notice Internal function to set the source chain contract.
     * @param _chainId The source chain ID.
     * @param _chainContract The contract address on the source chain.
     */
    function _setSourceChainContract(uint256 _chainId, address _chainContract) internal {
        LCGStorage storage ls = lockChainGateStorage();
        ls.sourceChainsContracts[_chainId] = _chainContract;
        emit SetSourceChainContract(_chainId, _chainContract);
    }

    /**
     * @notice Sets the source chain contract.
     * @param _chainId The source chain ID.
     * @param _chainContract The contract address on the source chain.
     */
    function setSourceChainContract(uint256 _chainId, address _chainContract) external onlyOwner {
        _setSourceChainContract(_chainId, _chainContract);
    }

    /**
     * @notice Sets both the source and destination chain contracts to the same address.
     * @param _chainId The chain ID.
     * @param _chainContract The contract address.
     */
    function setSourceAndDestinationChainContract(uint256 _chainId, address _chainContract) external onlyOwner {
        _setSourceChainContract(_chainId, _chainContract);
        _setDestinationChainContract(_chainId, _chainContract);
    }

    /**
     * @notice Sets the NFT lock period.
     * @param _lockPeriod The new lock period.
     * @param _transferTimeout The timeout between lock and transfer.
     */
    function setLockPeriod(uint64 _lockPeriod, uint64 _transferTimeout) external onlyOwner {
        LCGStorage storage ls = lockChainGateStorage();
        ls.lockPeriod = _lockPeriod;
        ls.transferTimeout = _transferTimeout;
        emit SetLockPeriodConfig(_lockPeriod, _transferTimeout);
    }

    /**
     * @notice Sets the referral code for deBridge.
     * @param _referralCode The new referral code.
     */
    function setReferralCode(uint32 _referralCode) external onlyOwner {
        LCGStorage storage ls = lockChainGateStorage();
        ls.referralCode = _referralCode;
        emit SetReferralCode(_referralCode);
    }

    /**
     * @notice Sets a custom chain ID.
     * @param _customChainId The new custom chain ID.
     */
    function setCustomChainId(uint256 _customChainId) external onlyOwner {
        LCGStorage storage ls = lockChainGateStorage();
        ls.customChainId = _customChainId;
        emit SetCustomChainId(_customChainId);
    }

    /**
     * @notice Internal function to record an NFT lock for a holder.
     * @param _holder The address that will hold the locked NFT.
     * @param _tokenId The NFT token ID.
     */
    function _writeLockLifetimeNft(address _holder, uint256 _tokenId) internal {
        LCGStorage storage ls = lockChainGateStorage();
        if (ls.lockedNft[_holder].tokenId != 0) {
            revert AlreadyLocked();
        }
        ls.lockedNft[_holder] = LockedNft(block.timestamp, _tokenId);
        ls.ownerOfTokenId[_tokenId] = _holder;
    }

    /**
     * @notice Locks a lifetime NFT to grant the holder lifetime access to their CryptoLegacy contract, thereby eliminating recurring update fees. Optionally, the NFT can be additionally locked to specific chains to support cross-chain functionality.
     * @param _tokenId The NFT token ID.
     * @param _holder The address that will receive lifetime access.
     * @param _lockToChainIds (Optional) Array of chain IDs to which the NFT is to be locked.
     * @param _crossChainFees (Optional) Array of fees corresponding to each chain for additional cross-chain locking.
     */
    function lockLifetimeNft(uint256 _tokenId, address _holder, uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable nonReentrant returns(uint256 returnValue) {
        LCGStorage storage ls = lockChainGateStorage();
        IERC721(address(ls.lifetimeNft)).transferFrom(msg.sender, address(this), _tokenId);
        _writeLockLifetimeNft(_holder, _tokenId);

        uint256 totalFee = _lockLifetimeNftToChains(ls, _holder, _lockToChainIds, _crossChainFees);
        returnValue = _calcAndReturnFee(totalFee);

        emit LockNft(block.timestamp, _tokenId, _holder);
    }

    /**
     * @notice Calculates the surplus (remaining value) after subtracting a total fee, then returns that surplus to the caller.
     * @param _totalFee The total fee amount in wei that needs to be deducted from `msg.value`.
     * @return returnValue The surplus amount returned to the caller (`msg.sender`).
     */
    function _calcAndReturnFee(uint256 _totalFee) internal returns(uint256 returnValue) {
        returnValue = msg.value - _totalFee;
        _returnFee(returnValue); 
    }

    /**
     * @notice Returns a specified amount of ether back to the caller, if greater than zero.
     * @dev Uses a low-level call to `msg.sender`. Reverts on failure with `TransferFeeFailed`.
     * @param _returnValue The amount of ether to send to `msg.sender`.
     */
    function _returnFee(uint256 _returnValue) internal {
        if (_returnValue > 0) {
            (bool success, bytes memory data) = payable(msg.sender).call{value: _returnValue}(new bytes(0));
            if (!success) {
                revert ILockChainGate.TransferFeeFailed(data);
            }
        }
    }

    /**
     * @notice Cross-chain locks a lifetime NFT.
     * @param _fromChainID The source chain ID.
     * @param _tokenId The NFT token ID.
     * @param _holder The address for which the NFT is locked.
     */
    function crossLockLifetimeNft(uint256 _fromChainID, uint256 _tokenId, address _holder) external nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        _checkSource(ls, _fromChainID);
        _onlyCrossChain(ls, _fromChainID);

        _writeLockLifetimeNft(_holder, _tokenId);
        ls.lockedNftFromChainId[_tokenId] = _fromChainID;

        emit CrossLockNft(ls.lockedNft[_holder].lockedAt, _tokenId, _holder, _fromChainID);
    }

    /**
     * @notice Internal function to lock an NFT to multiple chains.
     * @param _holder The NFT holder.
     * @param _toChainIDs Array of destination chain IDs.
     * @param _crossChainFees Array of fees for each chain.
     */
    function _lockLifetimeNftToChains(LCGStorage storage ls, address _holder, uint256[] memory _toChainIDs, uint256[] memory _crossChainFees) internal returns(uint256 totalFee) {
        if (_toChainIDs.length != _crossChainFees.length) {
            revert ArrayLengthMismatch();
        }
        uint256 tokenId = _checkTokenLocked(ls, _holder);
        _checkCrossChainLock(ls, tokenId);

        for (uint256 i = 0; i < _toChainIDs.length; i++) {
            uint256 sendFee = _getDeBridgeChainNativeFee(ls, _toChainIDs[i], _crossChainFees[i]);
            _lockLifetimeNftToChain(ls, _toChainIDs[i], _holder, tokenId, sendFee);
            totalFee += sendFee;
        }
        _checkFee(totalFee);
    }

    function _checkFee(uint256 _fee) internal {
        if (msg.value < _fee || msg.value - _fee > 0.00001 ether) {
            revert IncorrectFee(_fee);
        }
    }

    /**
     * @notice Locks an NFT to multiple chains using the caller as holder.
     * @param _toChainIDs Array of destination chain IDs.
     * @param _crossChainFees Array of fees for each chain.
     */
    function lockLifetimeNftToChains(uint256[] memory _toChainIDs, uint256[] memory _crossChainFees) external payable nonReentrant returns(uint256 returnValue) {
        uint256 totalFee = _lockLifetimeNftToChains(lockChainGateStorage(), msg.sender, _toChainIDs, _crossChainFees);
        returnValue = _calcAndReturnFee(totalFee);
    }

    /**
     * @notice Internal function to lock an NFT to a single chain.
     * @param _toChainID The destination chain ID.
     * @param _holder The NFT holder.
     * @param _sendFee The fee to send.
     */
    function _lockLifetimeNftToChain(LCGStorage storage ls, uint256 _toChainID, address _holder, uint256 _tokenId, uint256 _sendFee) internal {
        _checkDestinationLockedChain(ls, _toChainID);

        if (ls.lockedToChainsIds[_tokenId].contains(_toChainID)) {
            revert AlreadyLockedToChain();
        }

        bytes memory dstTxCall = _encodeCrossLockCommand(ls, _tokenId, _holder);
        bytes32 submissionId = _send(ls, dstTxCall, _toChainID, _sendFee);
        ls.lockedToChainsIds[_tokenId].add(_toChainID);
        emit LockToChain(_holder, _tokenId, _toChainID, submissionId);
    }

    /**
     * @notice Unlocks a lifetime NFT, returning it to the caller, if all conditions are met.
     * @dev The NFT can only be unlocked by the original holder or an approved address. In addition, all of the following conditions must be satisfied:
     *  - The caller must be either the NFT’s recorded owner (via `ownerOfTokenId`) or an address approved via `approveLifetimeNftTo`.
     *  - The NFT must not be locked to any additional chains (i.e., `lockedToChainsIds[_tokenId]` must be empty).
     *  - The current block timestamp must be at least `lockPeriod` seconds greater than the timestamp when the NFT was locked (checked via `_checkTooEarly`).
     *  - There must be no active cross-chain lock on the NFT (i.e., `_checkCrossChainLock` must pass).
     * @param _tokenId The NFT token ID to unlock.
     */
    function unlockLifetimeNft(uint256 _tokenId) external nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        address holder = ls.ownerOfTokenId[_tokenId];
        if (holder != msg.sender && ls.lockedNftApprovedTo[_tokenId] != msg.sender) {
            revert NotAvailable();
        }
        if (ls.lockedToChainsIds[_tokenId].length() != 0) {
            revert LockedToChains();
        }
        _checkTooEarly(holder);
        _checkCrossChainLock(ls, _tokenId);

        IERC721(address(ls.lifetimeNft)).transferFrom(address(this), msg.sender, _tokenId);

        _deleteTokenData(holder, _tokenId);

        emit UnlockNft(ls.lockedNft[holder].lockedAt, _tokenId, holder, msg.sender);
    }

    /**
     * @notice Unlocks an NFT from a cross-chain lock.
     * @param _tokenId The NFT token ID.
     */
    function unlockLifetimeNftFromChain(uint256 _tokenId) external payable nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        uint256 fromChainID = ls.lockedNftFromChainId[_tokenId];
        if (fromChainID == 0) {
            revert NotLockedByChain();
        }
        _checkDestinationLockedChain(ls, fromChainID);
        _checkTooEarly(msg.sender);
        _checkHolderTokenLock(ls, msg.sender, _tokenId);

        bytes memory dstTxCall = _encodeCrossUnlockCommand(ls, _tokenId, msg.sender);
        bytes32 submissionId = _send(ls, dstTxCall, fromChainID, _getDeBridgeChainNativeFeeAndCheck(ls, fromChainID, msg.value));

        _deleteTokenData(msg.sender, _tokenId);

        emit UnlockFromChain(msg.sender, _tokenId, fromChainID, submissionId);
    }

    /**
     * @notice Cross-chain unlocks an NFT.
     * @param _fromChainID The source chain ID.
     * @param _tokenId The NFT token ID.
     * @param _holder The address of the NFT holder.
     */
    function crossUnlockLifetimeNft(uint256 _fromChainID, uint256 _tokenId, address _holder) external nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        _checkSource(ls, _fromChainID);
        _onlyCrossChain(ls, _fromChainID);
        _checkHolderTokenLock(ls, _holder, _tokenId);

        ls.lockedToChainsIds[_tokenId].remove(_fromChainID);

        emit CrossUnlockNft(ls.lockedNft[_holder].lockedAt, _tokenId, _holder, _fromChainID);
    }

    /**
     * @notice Cross-chain transfers NFT ownership.
     * @param _fromChainID The source chain ID.
     * @param _tokenId The NFT token ID.
     * @param _transferTo The address to transfer the NFT to.
     */
    function crossUpdateNftOwner(uint256 _fromChainID, uint256 _tokenId, address _transferTo) external nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        _checkSource(ls, _fromChainID);
        _onlyCrossChain(ls, _fromChainID);

        _transferLifetimeNftTo(ls, _tokenId, ls.ownerOfTokenId[_tokenId], _transferTo, _fromChainID);
        ls.lockedNftFromChainId[_tokenId] = _fromChainID;
        emit CrossUpdateNftOwner(_fromChainID, _tokenId, _transferTo);
    }

    /**
     * @notice Internal function to delete NFT lock data.
     * @param _holder The NFT holder.
     * @param _tokenId The NFT token ID.
     */
    function _deleteTokenData(address _holder, uint256 _tokenId) internal {
        LCGStorage storage ls = lockChainGateStorage();
        delete ls.lockedNft[_holder];
        delete ls.lockedNftFromChainId[_tokenId];
        delete ls.lockedNftApprovedTo[_tokenId];
        delete ls.ownerOfTokenId[_tokenId];
    }

    /**
     * @notice Internal function that enforces that a cross‑chain call originates from the expected source.
     * @dev Requires that the caller is the CallProxy and that chain and sender information match the stored source contract.
     * @param ls The LockChainGate storage pointer.
     * @param _fromChainID The expected source chain ID.
     */
    function _onlyCrossChain(LCGStorage storage ls, uint256 _fromChainID) internal {
        ICallProxy callProxy = ICallProxy(ls.deBridgeGate.callProxy());

        // caller is CallProxy?
        if (address(callProxy) != msg.sender) {
            revert NotCallProxy();
        }

        uint256 chainIdFrom = callProxy.submissionChainIdFrom();
        if (chainIdFrom != _fromChainID) {
            revert ChainIdMismatch();
        }
        bytes memory nativeSender = callProxy.submissionNativeSender();
        if (keccak256(abi.encodePacked(ls.sourceChainsContracts[chainIdFrom])) != keccak256(nativeSender)) {
            revert NotValidSender();
        }
    }

    /**
     * @notice Internal function to send a cross‑chain message.
     * @dev Encodes the target contract call, sets flags for reverting on failure and proxying with sender,
     *      and sends the message via the deBridgeGate.
     * @param ls The LockChainGate storage pointer.
     * @param _dstTransactionCall The calldata for the destination chain.
     * @param _toChainId The destination chain ID.
     * @param _value The amount of native fee to send.
     * @return submissionId The ID of the cross‑chain message submission.
     */
    function _send(LCGStorage storage ls, bytes memory _dstTransactionCall, uint256 _toChainId, uint256 _value) internal returns(bytes32 submissionId) {
        uint flags = uint(0)
            .setFlag(Flags.REVERT_IF_EXTERNAL_FAIL, true)
            .setFlag(Flags.PROXY_WITH_SENDER, true);
        submissionId = ls.deBridgeGate.sendMessage{value: _value}(
            _toChainId, // _chainIdTo
            abi.encodePacked(ls.destinationChainContracts[_toChainId]), // _targetContractAddress
            _dstTransactionCall, // _targetContractCalldata
            flags, // _flags
            ls.referralCode // _referralCode
        );
        emit SendToChain(_toChainId, submissionId, _value, _dstTransactionCall);
    }

    /**
     * @notice Approves a specific address to unlock an NFT.
     * @param _tokenId The NFT token ID.
     * @param _approveTo The address to approve.
     */
    function approveLifetimeNftTo(uint256 _tokenId, address _approveTo) external nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        _checkHolderTokenLock(ls, msg.sender, _tokenId);
        _checkCrossChainLock(ls, _tokenId);
        ls.lockedNftApprovedTo[_tokenId] = _approveTo;
        emit ApproveNft(_tokenId, msg.sender, _approveTo);
    }

    /**
     * @notice Internal function to transfer NFT ownership.
     * @param _tokenId The NFT token ID.
     * @param _holder The current owner.
     * @param _transferTo The new owner.
     * @param _fromChain The originating chain ID.
     */
    function _transferLifetimeNftTo(LCGStorage storage ls, uint256 _tokenId, address _holder, address _transferTo, uint256 _fromChain) internal {
        if (_holder == _transferTo) {
            revert SameAddress();
        }
        if (ls.lockedNft[_transferTo].tokenId != 0) {
            revert RecipientLocked();
        }
        if (ls.lockedNft[_holder].lockedAt + ls.transferTimeout > block.timestamp) {
            revert TransferLockTimeout();
        }
        ls.ownerOfTokenId[_tokenId] = _transferTo;
        ls.lockedNft[_transferTo].tokenId = _tokenId;
        ls.lockedNft[_transferTo].lockedAt = block.timestamp;
        delete ls.lockedNftApprovedTo[_tokenId];
        delete ls.lockedNft[_holder];
        emit TransferNft(_tokenId, _holder, _transferTo, _fromChain);
    }

    /**
     * @notice Transfers NFT ownership and locks it on specified chains.
     * @param _tokenId The NFT token ID.
     * @param _transferTo The address to transfer the NFT to.
     * @param _toChainIDs Array of destination chain IDs.
     * @param _crossChainFees Array of fees for each chain.
     */
    function transferLifetimeNftTo(uint256 _tokenId, address _transferTo, uint256[] memory _toChainIDs, uint256[] memory _crossChainFees) external payable nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        address holder = ls.ownerOfTokenId[_tokenId];
        _checkCrossChainLock(ls, _tokenId);
        if (holder != msg.sender && ls.lockedNftApprovedTo[_tokenId] != msg.sender) {
            revert NotAvailable();
        }
        _checkHolderTokenLock(ls, holder, _tokenId);
        _transferLifetimeNftTo(ls, _tokenId, holder, _transferTo, 0);

        _updateNftOwnerOnChainList(ls, _tokenId, _toChainIDs, _crossChainFees, _transferTo);
    }

    /**
     * @notice Updates NFT owner on-chain list.
     * @param _tokenId The NFT token ID.
     * @param _toChainIDs Array of destination chain IDs.
     * @param _crossChainFees Array of fees for each chain.
     */
    function updateNftOwnerOnChainList(uint256 _tokenId, uint256[] memory _toChainIDs, uint256[] memory _crossChainFees) external payable nonReentrant {
        LCGStorage storage ls = lockChainGateStorage();
        _checkCrossChainLock(ls, _tokenId);
        if (ls.ownerOfTokenId[_tokenId] != msg.sender) {
            revert NotAvailable();
        }

        _updateNftOwnerOnChainList(ls, _tokenId, _toChainIDs, _crossChainFees, msg.sender);
    }

    /**
     * @notice Internal function to update the NFT owner on specified chains.
     * @param _tokenId The NFT token ID.
     * @param _toChainIDs Array of destination chain IDs.
     * @param _crossChainFees Array of fees for each chain.
     * @param _holder The NFT owner address.
     */
    function _updateNftOwnerOnChainList(LCGStorage storage ls, uint256 _tokenId, uint256[] memory _toChainIDs, uint256[] memory _crossChainFees, address _holder) internal {
        if (_toChainIDs.length != _crossChainFees.length) {
            revert ArrayLengthMismatch();
        }
        uint256 totalFee = 0;
        for (uint256 i = 0; i < _toChainIDs.length; i++) {
            uint256 sendFee = _getDeBridgeChainNativeFee(ls, _toChainIDs[i], _crossChainFees[i]);
            _updateLifetimeNftOwnerOnChain(ls, _tokenId, _toChainIDs[i], _holder, sendFee);
            totalFee += sendFee;
        }
        _checkFee(totalFee);
    }

    /**
     * @notice Internal function to update the NFT owner on a single chain.
     * @param _tokenId The NFT token ID.
     * @param _toChainID The destination chain ID.
     * @param _holder The NFT owner address.
     * @param _sendFee The fee to send.
     */
    function _updateLifetimeNftOwnerOnChain(LCGStorage storage ls, uint256 _tokenId, uint256 _toChainID, address _holder, uint256 _sendFee) internal returns(bytes32 submissionId) {
        uint256 checkTokenId = _checkTokenLocked(ls, _holder);
        _checkDestinationLockedChain(ls, _toChainID);
        if (checkTokenId != _tokenId) {
            revert TokenIdMismatch(checkTokenId);
        }
        bytes memory dstTxCall = _encodeCrossUpdateOwnerCommand(ls, checkTokenId, _holder);
        submissionId = _send(ls, dstTxCall, _toChainID, _sendFee);
        ls.lockedToChainsIds[checkTokenId].add(_toChainID);
        emit UpdateLockToChain(msg.sender, _tokenId, _toChainID, submissionId);
    }

    /**
     * @notice Encodes the cross‑chain lock command.
     * @dev Uses abi.encodeWithSelector with the crossLockLifetimeNft selector.
     * @param ls The LockChainGate storage pointer.
     * @param _tokenId The NFT token ID.
     * @param _holder The NFT holder.
     * @return The encoded call data.
     */
    function _encodeCrossLockCommand(LCGStorage storage ls, uint256 _tokenId, address _holder) internal view returns (bytes memory) {
        return abi.encodeWithSelector(LockChainGate.crossLockLifetimeNft.selector, _getChainId(ls), _tokenId, _holder);
    }

    /**
     * @notice Encodes the cross‑chain unlock command.
     * @dev Uses abi.encodeWithSelector with the crossUnlockLifetimeNft selector.
     * @param ls The LockChainGate storage pointer.
     * @param _tokenId The NFT token ID.
     * @param _holder The NFT holder.
     * @return The encoded call data.
     */
    function _encodeCrossUnlockCommand(LCGStorage storage ls, uint256 _tokenId, address _holder) internal view returns (bytes memory) {
        return abi.encodeWithSelector(LockChainGate.crossUnlockLifetimeNft.selector, _getChainId(ls), _tokenId, _holder);
    }

    /**
     * @notice Encodes the cross‑chain update owner command.
     * @dev Uses abi.encodeWithSelector with the crossUpdateNftOwner selector.
     * @param ls The LockChainGate storage pointer.
     * @param _tokenId The NFT token ID.
     * @param _transferTo The new owner address.
     * @return The encoded call data.
     */
    function _encodeCrossUpdateOwnerCommand(LCGStorage storage ls, uint256 _tokenId, address _transferTo) internal view returns (bytes memory) {
        return abi.encodeWithSelector(LockChainGate.crossUpdateNftOwner.selector, _getChainId(ls), _tokenId, _transferTo);
    }

    /**
     * @notice Checks that the destination chain for an NFT lock is properly configured.
     * @dev Reverts if no destination chain contract is specified.
     * @param ls The LockChainGate storage pointer.
     * @param _toChainID The destination chain ID.
     */
    function _checkDestinationLockedChain(LCGStorage storage ls, uint256 _toChainID) internal view {
        if (ls.destinationChainContracts[_toChainID] == address(0)) {
            revert DestinationChainNotSpecified();
        }
    }

    /**
     * @notice Checks that the NFT is locked.
     * @dev Reverts if the holder does not have a locked NFT.
     * @param ls The LockChainGate storage pointer.
     * @param _holder The NFT holder.
     * @return tokenId The token ID that is locked.
     */
    function _checkTokenLocked(LCGStorage storage ls, address _holder) internal view returns(uint256 tokenId) {
        tokenId = ls.lockedNft[_holder].tokenId;
        if (tokenId == 0) {
            revert TokenNotLocked();
        }
    }

    /**
     * @notice Checks that the NFT is not cross‑chain locked.
     * @dev Reverts if the lockedNftFromChainId for the token is nonzero.
     * @param ls The LockChainGate storage pointer.
     * @param _tokenId The NFT token ID.
     */
    function _checkCrossChainLock(LCGStorage storage ls, uint256 _tokenId) internal view {
        if (ls.lockedNftFromChainId[_tokenId] != 0) {
            revert CrossChainLock();
        }
    }

    /**
     * @notice Checks that the lock period has elapsed for the NFT.
     * @dev Reverts if the current block timestamp is less than the locked time plus the lock period.
     * @param _holder The NFT holder.
     */
    function _checkTooEarly(address _holder) internal view {
        if (block.timestamp < _getLockedUntil(lockChainGateStorage(), _holder)) {
            revert TooEarly();
        }
    }

    /**
     * @notice Validates that the source chain contract is specified.
     * @dev Reverts if no source contract is configured for the given chain.
     * @param ls The LockChainGate storage pointer.
     * @param _fromChainID The source chain ID.
     */
    function _checkSource(LCGStorage storage ls, uint256 _fromChainID) internal view {
        if (ls.sourceChainsContracts[_fromChainID] == address(0)) {
            revert SourceNotSpecified();
        }
    }

    /**
     * @notice Checks that the provided holder truly owns the locked NFT.
     * @dev Reverts if the locked tokenId for the holder does not match _tokenId.
     * @param ls The LockChainGate storage pointer.
     * @param _holder The NFT holder.
     * @param _tokenId The expected locked NFT token ID.
     */
    function _checkHolderTokenLock(LCGStorage storage ls, address _holder, uint256 _tokenId) internal view {
        if (ls.lockedNft[_holder].tokenId != _tokenId) {
            revert TokenNotLocked();
        }
    }

    /**
     * @notice Retrieves the list of destination chain IDs to which a holder's NFT is locked.
     * @param _holder The NFT holder.
     * @return An array of chain IDs.
     */
    function getLockedToChainsIdsOfAccount(address _holder) external virtual view returns (uint256[] memory) {
        return _getLockedToChainsIdsOfAccount(lockChainGateStorage(), _holder);
    }

    /**
     * @notice Internal function to get the list of destination chain IDs for a locked NFT.
     * @param ls The LockChainGate storage pointer.
     * @param _holder The NFT holder.
     * @return An array of chain IDs.
     */
    function _getLockedToChainsIdsOfAccount(LCGStorage storage ls, address _holder) internal view returns (uint256[] memory) {
        return ls.lockedToChainsIds[ls.lockedNft[_holder].tokenId].values();
    }

    /**
     * @notice Retrieves the timestamp until which a holder’s NFT remains locked.
     * @param _holder The NFT holder.
     * @return The unlock timestamp (lockedAt + lockPeriod).
     */
    function getLockedUntil(address _holder) external view returns (uint256) {
        return _getLockedUntil(lockChainGateStorage(), _holder);
    }

    /**
     * @notice Internal function to compute the unlock timestamp.
     * @param ls The LockChainGate storage pointer.
     * @param _holder The NFT holder.
     * @return The timestamp until which the NFT remains locked.
     */
    function _getLockedUntil(LCGStorage storage ls, address _holder) internal view returns (uint256) {
        return ls.lockedNft[_holder].lockedAt + uint256(ls.lockPeriod);
    }

    /**
     * @notice Retrieves the list of destination chain IDs for a given NFT token.
     * @param _tokenId The NFT token ID.
     * @return An array of chain IDs.
     */
    function getLockedToChainsIds(uint256 _tokenId) external view returns (uint256[] memory) {
        return lockChainGateStorage().lockedToChainsIds[_tokenId].values();
    }

    /**
     * @notice Retrieves the current NFT lock period.
     * @return The lock period in seconds.
     */
    function lockPeriod() external view returns (uint256) {
        return uint256(lockChainGateStorage().lockPeriod);
    }

    function transferTimeout() external view returns (uint256) {
        return uint256(lockChainGateStorage().transferTimeout);
    }

    /**
     * @notice Retrieves the referral code configured for cross‑chain messages.
     * @return The referral code.
     */
    function referralCode() external view returns (uint256) {
        return lockChainGateStorage().referralCode;
    }

    /**
     * @notice Returns the recorded owner of a specific NFT token.
     * @param _tokenId The NFT token ID.
     * @return The address of the owner.
     */
    function ownerOfTokenId(uint256 _tokenId) external view returns(address) {
        return lockChainGateStorage().ownerOfTokenId[_tokenId];
    }

    /**
     * @notice Retrieves the source chain ID from which the NFT was locked.
     * @param _tokenId The NFT token ID.
     * @return The source chain ID.
     */
    function lockedNftFromChainId(uint256 _tokenId) external view returns(uint256) {
        return lockChainGateStorage().lockedNftFromChainId[_tokenId];
    }

    /**
     * @notice Returns the address approved to unlock or transfer a specific NFT.
     * @param _tokenId The NFT token ID.
     * @return The approved address.
     */
    function lockedNftApprovedTo(uint256 _tokenId) external view returns(address) {
        return lockChainGateStorage().lockedNftApprovedTo[_tokenId];
    }

    /**
     * @notice Retrieves the lock record for a specific NFT holder.
     * @param _holder The NFT holder.
     * @return The LockedNft struct containing lock information.
     */
    function lockedNft(address _holder) external view returns(LockedNft memory) {
        return lockChainGateStorage().lockedNft[_holder];
    }

    /**
     * @notice Returns the native fee for a given chain ID and user value; reverts if msg.value is insufficient.
     * @param _chainId The chain ID.
     * @param _userValue The user-supplied value.
     * @return nativeFee The required native fee.
     */
    function getDeBridgeChainNativeFeeAndCheck(uint256 _chainId, uint256 _userValue) external payable returns(uint256 nativeFee) {
        return _getDeBridgeChainNativeFeeAndCheck(lockChainGateStorage(), _chainId, _userValue);
    }
    /**
     * @notice Internal function to compute and check the required native fee.
     * @param ls The LockChainGate storage pointer.
     * @param _chainId The destination chain ID.
     * @param _userValue The value provided by the user.
     * @return nativeFee The calculated native fee.
     */
    function _getDeBridgeChainNativeFeeAndCheck(LCGStorage storage ls, uint256 _chainId, uint256 _userValue) internal returns(uint256 nativeFee) {
        nativeFee = _getDeBridgeChainNativeFee(ls, _chainId, _userValue);
        _checkFee(nativeFee);
    }

    /**
     * @notice Returns the native fee for a given chain.
     * @param _chainId The chain ID.
     * @param _userValue The user-supplied value.
     * @return nativeFee The native fee.
     */
    function getDeBridgeChainNativeFee(uint256 _chainId, uint256 _userValue) external view returns(uint256 nativeFee) {
        return _getDeBridgeChainNativeFee(lockChainGateStorage(), _chainId, _userValue);
    }

    /**
     * @notice Internal function to compute the native fee for a chain.
     * @dev If no fee is set for _chainId, uses the globalFixedNativeFee from deBridgeGate.
     *      If _userValue exceeds the computed fee, returns _userValue.
     * @param ls The LockChainGate storage pointer.
     * @param _chainId The destination chain ID.
     * @param _userValue The value provided by the user.
     * @return nativeFee The computed native fee.
     */
    function _getDeBridgeChainNativeFee(LCGStorage storage ls, uint256 _chainId, uint256 _userValue) internal view returns(uint256 nativeFee) {
        nativeFee = ls.deBridgeNativeFee[_chainId];
        if (nativeFee == 0) {
            nativeFee = ls.deBridgeGate.globalFixedNativeFee();
        }
        if (_userValue > nativeFee) {
            nativeFee = _userValue;
        }
        return nativeFee;
    }

    /**
     * @notice Returns the address of the deBridgeGate contract.
     * @return The deBridgeGate contract address.
     */
    function deBridgeGate() external view returns (address) {
        return address(lockChainGateStorage().deBridgeGate);
    }

    /**
     * @notice Returns the address of the associated LifetimeNft contract.
     * @return The LifetimeNft contract address.
     */
    function lifetimeNft() external view returns (address) {
        return address(lockChainGateStorage().lifetimeNft);
    }

    /**
     * @notice Returns cross-chain configuration for a given chain ID.
     * @param _chainId The destination chain ID.
     * @return nativeFee The native fee for the chain.
     * @return destinationChain The destination chain contract address.
     * @return sourceChain The source chain contract address.
     */
    function deBridgeChainConfig(uint256 _chainId) external view returns (uint256 nativeFee, address destinationChain, address sourceChain) {
        LCGStorage storage ls = lockChainGateStorage();
        return (ls.deBridgeNativeFee[_chainId], ls.destinationChainContracts[_chainId], ls.sourceChainsContracts[_chainId]);
    }

    /**
     * @notice Returns the list of addresses designated as lock operators.
     * @return An array of lock operator addresses.
     */
    function getLockOperatorsList() external view returns (address[] memory) {
        return lockChainGateStorage().lockOperators.values();
    }

    /**
     * @notice Checks if a given address is a lock operator.
     * @param _addr The address to check.
     * @return True if the address is a lock operator, false otherwise.
     */
    function isLockOperator(address _addr) external view returns(bool) {
        return lockChainGateStorage().lockOperators.contains(_addr);
    }

    /**
     * @notice Calculates the total native fee required for cross-chain referral creation.
     * @param _chainIds Array of chain IDs.
     * @param _crossChainFees Array of cross-chain fees.
     * @return The total native fee.
     */
    function calculateCrossChainCreateRefNativeFee(uint256[] memory _chainIds, uint256[] memory _crossChainFees) external view returns(uint256) {
        LCGStorage storage ls = lockChainGateStorage();
        uint256 totalNativeFee = 0;
        for (uint256 i = 0; i < _chainIds.length; i++) {
            totalNativeFee += _getDeBridgeChainNativeFee(ls, _chainIds[i], _crossChainFees[i]);
        }
        return totalNativeFee;
    }

    /**
     * @notice Checks whether the NFT for a given owner is locked.
     * @param _holder The owner address.
     * @return True if locked, false otherwise.
     */
    function isNftLocked(address _holder) external view returns(bool) {
        return _isNftLocked(lockChainGateStorage(), _holder);
    }
    /**
     * @notice Internal function to determine if a holder’s NFT is locked.
     * @param ls The LockChainGate storage pointer.
     * @param _holder The NFT holder address.
     * @return True if a tokenId is recorded as locked, false otherwise.
     */
    function _isNftLocked(LCGStorage storage ls, address _holder) internal view returns(bool) {
        return ls.lockedNft[_holder].tokenId != 0;
    }

    /**
     * @notice Checks whether an NFT is locked for `_holder` and updates the locked timestamp if the lockPeriod has passed.
     * @dev Useful for refreshing lock time. Reverts if caller is not the lock operator or the NFT holder/approved address.
     * @param _holder The address to check.
     * @return True if the NFT is locked, false otherwise.
     */
    function isNftLockedAndUpdate(address _holder) external returns(bool) {
        LCGStorage storage ls = lockChainGateStorage();
        uint256 tokenId = ls.lockedNft[_holder].tokenId;
        if (tokenId == 0) {
            return false;
        }
        if (!ls.lockOperators.contains(msg.sender) && _holder != msg.sender && ls.lockedNftApprovedTo[tokenId] != msg.sender) {
            revert NotAllowed();
        }
        bool isLocked = _isNftLocked(ls, _holder);
        if (isLocked && block.timestamp > _getLockedUntil(ls, _holder)) {
            ls.lockedNft[_holder].lockedAt = block.timestamp;
        }
        return isLocked;
    }

    /**
     * @notice Returns the current chain ID or a custom one if set.
     * @return cid The chain ID.
     */
    function getChainId() external virtual view returns (uint256 cid) {
        return _getChainId(lockChainGateStorage());
    }
    /**
     * @notice Internal function to retrieve the chain ID.
     * @dev If a customChainId is set, returns it; otherwise returns the blockchain chainid.
     * @param ls The LockChainGate storage pointer.
     * @return cid The effective chain ID.
     */
    function _getChainId(LCGStorage storage ls) internal view returns (uint256 cid) {
        if (ls.customChainId != 0) {
            return ls.customChainId;
        }
        assembly {
            cid := chainid()
        }
    }
}