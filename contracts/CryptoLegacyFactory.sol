/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./CryptoLegacy.sol";
import "./libraries/LibCreate2Deploy.sol";
import "./interfaces/ICryptoLegacyFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CryptoLegacyFactory
 * @notice Deploys new CryptoLegacy contracts using CREATE2, ensuring deterministic addresses and secure deployment.
 */
contract CryptoLegacyFactory is ICryptoLegacyFactory, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  // Storage for build operators, which are addresses authorized to deploy new CryptoLegacy contracts.
  EnumerableSet.AddressSet private buildOperators;

  /**
   * @notice Constructor that sets the initial owner.
   * @dev Transfers ownership to _owner.
   * @param _owner The address to be assigned as the owner.
   */
  constructor(address _owner) Ownable() {
    _transferOwnership(_owner);
  }

  /**
   * @notice Sets the given `_operator` as a build operator or removes it.
   * @dev This is a setter for `buildOperators` used to control who can deploy new CryptoLegacy contracts.
   * @param _operator The address to add or remove.
   * @param _isAdd If true, adds the operator; if false, removes it.
   */
  function setBuildOperator(address _operator, bool _isAdd) public onlyOwner {
    if (_isAdd) {
      buildOperators.add(_operator);
      emit AddBuildOperator(_operator);
    } else {
      buildOperators.remove(_operator);
      emit RemoveBuildOperator(_operator);
    }
  }

  /**
   * @notice Creates a new CryptoLegacy contract using CREATE2.
   * @dev Only callable by authorized build operators. Deploys a new contract with bytecode constructed by cryptoLegacyBytecode().
   * @param _owner The owner of the new CryptoLegacy contract.
   * @param _plugins An array of plugin addresses to be integrated.
   * @param _create2Args The parameters for CREATE2 deployment including the target address and salt.
   * @return The payable address of the newly deployed CryptoLegacy contract.
   */
  function createCryptoLegacy(
    address _owner,
    address[] memory _plugins,
    Create2Args memory _create2Args
  ) external returns(address payable) {
    if (!buildOperators.contains(msg.sender)) {
      revert NotBuildOperator();
    }
    address clAddress = LibCreate2Deploy._deployByCreate2(
      _create2Args.create2Address,
      _create2Args.create2Salt,
      cryptoLegacyBytecode(msg.sender, _owner, _plugins)
    );
    return payable(clAddress);
  }

  /**
   * @notice Returns the bytecode used to deploy a new CryptoLegacy contract.
   * @dev Combines CryptoLegacy.creationCode with encoded constructor parameters.
   * @param _buildManager The build manager address.
   * @param _owner The owner address for the deployed contract.
   * @param _plugins The array of plugin addresses.
   * @return The complete bytecode to deploy.
   */
  function cryptoLegacyBytecode(
    address _buildManager,
    address _owner,
    address[] memory _plugins
  ) public virtual pure returns (bytes memory) {
    return abi.encodePacked(
      type(CryptoLegacy).creationCode,
      abi.encode(_buildManager, _owner, _plugins)
    );
  }

  /**
   * @notice Computes the deterministic address of a contract deployed via CREATE2.
   * @param _salt The salt used during deployment.
   * @param _bytecodeHash The hash of the contract's bytecode.
   * @return The computed contract address.
   */
  function computeAddress(bytes32 _salt, bytes32 _bytecodeHash) public view returns (address) {
    return LibCreate2Deploy._computeAddress(_salt, _bytecodeHash);
  }
}
