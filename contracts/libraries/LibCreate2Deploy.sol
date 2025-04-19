/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

library LibCreate2Deploy {
    event CryptoLegacyCreation(address addr, bytes32 salt);
   /**
   * @dev Deploys a contract using CREATE2 if it does not already exist.
   * @param _contractAddress The expected deployed contract address.
   * @param _factorySalt The nonce of the factory at the time of original deployment.
   * @param _contractBytecode The bytecode of the contract to be deployed.
   * @return The address of the deployed contract.
   */
    function _deployByCreate2(
        address _contractAddress,
        bytes32 _factorySalt,
        bytes memory _contractBytecode
    ) internal returns (address) {
        if (_contractBytecode.length == 0) {
            revert BytecodeEmpty();
        }

        // Compute the expected contract address
        bytes32 bytecodeHash = keccak256(_contractBytecode);
        address predictedAddress = _computeAddress(_factorySalt, bytecodeHash);

        // Check if the contract already exists at the predicted address
        uint256 size;
        assembly {
            size := extcodesize(predictedAddress)
        }
        if (size != 0) {
            revert AlreadyExists();
        }

        // Ensure the computed address matches the expected deployed contract address
        if (_contractAddress != address(0) && predictedAddress != _contractAddress) {
            revert AddressMismatch();
        }

        // Store bytecode length for gas efficiency
        uint256 bytecodeLength = _contractBytecode.length;

        bytes32 salt;
        if (_factorySalt == 0) {
            salt = blockhash(block.number - 1);
        } else {
            salt = _factorySalt;
        }

        address addr;
        assembly {
        // CREATE2 deploys a contract with deterministic address
            addr := create2(0, add(_contractBytecode, 0x20), bytecodeLength, salt)
        }
        if (addr == address(0)) {
            revert Create2Failed();
        }
        emit CryptoLegacyCreation(addr, salt);
        return addr;
    }

   /**
   * @dev Computes the expected contract address based on CREATE2 formula.
   * @param _salt The salt used for CREATE2 deployment (same as _factoryNonce).
   * @param _bytecodeHash The keccak256 hash of the contract's bytecode.
   * @return The computed contract address.
   */
    function _computeAddress(bytes32 _salt, bytes32 _bytecodeHash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),    // Fixed prefix for CREATE2
            address(this),              // Factory contract address (must be the same across networks)
            _salt,                      // Derived from _factoryNonce
            _bytecodeHash               // Hash of the contract bytecode
        )))));
    }

    error BytecodeEmpty();
    error AlreadyExists();
    error AddressMismatch();
    error Create2Failed();
}