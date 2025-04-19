/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./libraries/LibDiamond.sol";
import "./libraries/LibCryptoLegacy.sol";
import "./libraries/LibCryptoLegacy.sol";
import "./interfaces/ICryptoLegacyOwnable.sol";

/**
 * @title CryptoLegacyOwnable
 * @notice Provides basic ownership and pause control for the CryptoLegacy contract.
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
     * @notice Transfers ownership to a new address.
     * @dev Internal function that updates the owner using LibDiamond.setContractOwner().
     * @param _owner The address of the new owner.
     */
    function _transferOwnership(address _owner) internal virtual {
        address oldOwner = LibDiamond.contractOwner();
        LibDiamond.setContractOwner(_owner);
        emit OwnershipTransferred(oldOwner, _owner);
    }

    /**
     * @notice Sets the pause state of the contract.
     * @dev Public setter callable only by the owner; stores the pause flag.
     * @param _isPaused True to pause the contract; false to unpause.
     */
    function setPause(bool _isPaused) public virtual onlyOwner {
        LibCryptoLegacy._setPause(LibCryptoLegacy.getCryptoLegacyStorage(), _isPaused);
    }
}