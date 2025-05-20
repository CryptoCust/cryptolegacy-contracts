/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./libraries/LibDiamond.sol";
import "./libraries/LibCryptoLegacy.sol";
import "./interfaces/ICryptoLegacyOwnable.sol";

/**
 * @title CryptoLegacyOwnable
 * @notice Extends ownership and pause control for the CryptoLegacy contract, referencing the diamond’s internal owner storage.
 */
contract CryptoLegacyOwnable is ICryptoLegacyOwnable {
    /**
     * @notice Modifier to restrict function execution to the owner.
     * @dev Uses LibCryptoLegacy._checkOwner() to validate that msg.sender is the contract owner.
     */
    modifier onlyOwner() {
        LibCryptoLegacy._checkOwner();
        _;
    }

    /**
     * @notice Transfers ownership to a new address, updates pendingOwner, and emits event.
     * @dev Internal function used by `transferOwnership` in child classes.
     * @param cls A reference to the CryptoLegacy storage.
     * @param _owner The new owner address.
     */
    function _transferOwnership(ICryptoLegacy.CryptoLegacyStorage storage cls, address _owner) internal virtual {
        if (_owner == address(0)) {
            revert ICryptoLegacy.ZeroAddress();
        }
        cls.pendingOwner = _owner;
        emit OwnershipTransferStarted(LibDiamond.contractOwner(), _owner);
    }

    /**
     * @notice Allows the pendingOwner to accept ownership and become the new owner.
     * @dev Reverts if msg.sender is not the pendingOwner.
     */
    function acceptOwnership() public virtual {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        if (cls.pendingOwner != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
        LibDiamond.setContractOwner(cls.pendingOwner);
        cls.pendingOwner = address(0);
    }

    /**
     * @notice Sets the pause state of the contract.
     * @dev Public setter callable only by the owner; stores the pause flag.
     * @param _isPaused True to pause the contract; false to unpause.
     */
    function setPause(bool _isPaused) public virtual onlyOwner {
        LibCryptoLegacy._setPause(LibCryptoLegacy.getCryptoLegacyStorage(), _isPaused);
    }

    /**
     * @notice Returns the address of the pending owner.
     * @return The pending owner address, or zero if none.
     */
    function pendingOwner() public view virtual returns (address) {
        return LibCryptoLegacy.getCryptoLegacyStorage().pendingOwner;
    }
}