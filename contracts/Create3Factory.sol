// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./libraries/LibCreate3.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Create3Factory
 * @notice Deploys contracts deterministically using CREATE3, ensuring deterministic addresses and secure deployment.
 */
contract Create3Factory is Ownable {
    /**
     * @notice Emitted after deploying a contract using CREATE3.
     */
    event Create3Contract(address contractAddress);

    /**
     * @notice Constructor that sets the initial owner.
     * @param _owner The address to be assigned as the contract’s owner.
     */
    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    /**
     * @notice Builds (deploys) a new contract using CREATE3 with a given salt and contract bytecode.
     * @dev Only the contract owner can invoke this. Uses the LibCreate3 library for the deterministic address.
     * @param _create3Salt The salt used to derive the deterministic address.
     * @param _contractBytecode The bytecode of the contract to deploy.
     * @return result The address of the deployed contract.
     */
    function build(bytes32 _create3Salt, bytes calldata _contractBytecode) external onlyOwner returns (address result) {
        result = LibCreate3.create3(_create3Salt, _contractBytecode);
        emit Create3Contract(result);
    }

    /**
     * @notice Computes the CREATE3-based deterministic address for a given salt, without deploying.
     * @param _create3Salt The salt used for CREATE3 derivation.
     * @return The predicted address of the contract once deployed.
     */
    function computeAddress(bytes32 _create3Salt) public view returns (address) {
        return LibCreate3.addressOf(_create3Salt);
    }
}
