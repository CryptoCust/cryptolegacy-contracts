/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "./LibCreate3.sol";

library LibCryptoLegacyDeploy {
    event CryptoLegacyCreation(address addr, bytes32 salt);
   /**
     * @dev Deploys a contract using CREATE3 if it does not already exist.
     * @param _contractOwner The expected deployed contract owner.
     * @param _factorySalt The nonce of the factory at the time of original deployment.
     * @param _contractAddress The expected deployed contract address.
     * @param _contractBytecode The bytecode of the contract to be deployed.
     * @return addr The address of the deployed contract.
     */
    function _deployByCreate3(
        address _contractOwner,
        bytes32 _factorySalt,
        address _contractAddress,
        bytes memory _contractBytecode
    ) internal returns (address addr) {
        if (_contractBytecode.length == 0) {
            revert BytecodeEmpty();
        }

        if (_factorySalt == 0) {
            _factorySalt = blockhash(block.number - 1);
        }
        // Compute the expected contract address
        address predictedAddress = _computeAddress(_factorySalt, _contractOwner);
        // Ensure the computed address matches the expected deployed contract address
        if (_contractAddress != address(0) && predictedAddress != _contractAddress) {
            revert AddressMismatch();
        }
        bytes32 salt = _getContractOwnerSalt(_factorySalt, _contractOwner);
        
        addr = LibCreate3.create3(salt, _contractBytecode);
        emit CryptoLegacyCreation(addr, salt);
    }

    function _getContractOwnerSalt(bytes32 _salt, address _contractOwner) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(_salt, _contractOwner));
    }

   /**
     * @dev Computes the expected contract address based on CREATE3 formula.
     * @param _salt The salt used for CREATE3 deployment (same as _factoryNonce).
     * @param _contractOwner The expected contract owner.
     * @return The computed contract address.
     */
    function _computeAddress(bytes32 _salt, address _contractOwner) internal view returns (address) {
        return LibCreate3.addressOf(_getContractOwnerSalt(_salt, _contractOwner));
    }

    error BytecodeEmpty();
    error AddressMismatch();
    error Create3Failed();
}