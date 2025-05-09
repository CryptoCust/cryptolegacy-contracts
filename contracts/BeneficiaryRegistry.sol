/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./BuildManagerOwnable.sol";
import "./interfaces/IBeneficiaryRegistry.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title BeneficiaryRegistry
 * @notice Maintains a mapping between beneficiary hashes and the addresses of CryptoLegacy contracts.
 */
contract BeneficiaryRegistry is IBeneficiaryRegistry, BuildManagerOwnable {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @dev Maps a beneficiary hash to the set of associated CryptoLegacy contract addresses.
  mapping(bytes32 => EnumerableSet.AddressSet) internal cryptoLegacyByBeneficiary;
  mapping(bytes32 => EnumerableSet.AddressSet) internal cryptoLegacyByOwner;
  mapping(bytes32 => EnumerableSet.AddressSet) internal cryptoLegacyByGuardian;
  mapping(bytes32 => EnumerableSet.AddressSet) internal cryptoLegacyByRecovery;
  mapping(address => uint256[]) internal blockNumberChangesByCryptoLegacy;

  /**
   * @notice Constructor that transfers ownership.
   * @param _owner The initial owner.
   */
  constructor(address _owner) BuildManagerOwnable() {
    _transferOwnership(_owner);
  }

  /**
   * @notice Records the current block number for a given CryptoLegacy contract.
   * @dev Appends the current block number to the history if the last recorded block number is different.
   * @param _cryptoLegacy The address of the CryptoLegacy contract making the change.
   */
  function _setBlockNumberChange(address _cryptoLegacy) internal {
    uint256[] storage blockNumbers = blockNumberChangesByCryptoLegacy[_cryptoLegacy];
    if (blockNumbers.length == 0 || blockNumbers[blockNumbers.length - 1] != block.number) {
      blockNumbers.push(block.number);
    }
  }

  /**
   * @notice Adds or removes the calling CryptoLegacy contract from the beneficiary registry.
   * @dev Only callable from a valid CryptoLegacy contract built by an approved buildManager.
   *      If `_isAdd` is true, the contract is recorded under `_beneficiary` in the registry.
   *      Otherwise, the entry is removed.
   * @param _beneficiary The keccak256 hash of the beneficiary's identifier.
   * @param _isAdd Boolean indicating add (true) or remove (false).
   */
  function setCryptoLegacyBeneficiary(bytes32 _beneficiary, bool _isAdd) external {
    address _cryptoLegacy = msg.sender;
    _checkBuildManagerValid(_cryptoLegacy, address(0));
    if (_isAdd) {
      cryptoLegacyByBeneficiary[_beneficiary].add(_cryptoLegacy);
      emit AddCryptoLegacyForBeneficiary(_beneficiary, _cryptoLegacy);
    } else {
      cryptoLegacyByBeneficiary[_beneficiary].remove(_cryptoLegacy);
      emit RemoveCryptoLegacyForBeneficiary(_beneficiary, _cryptoLegacy);
    }
    _setBlockNumberChange(_cryptoLegacy);
  }

  /**
   * @notice Adds or removes the calling CryptoLegacy contract from the beneficiary registry under a guardian role.
   * @dev Similar to setCryptoLegacyBeneficiary but for guardian hashes.
   * @param _guardian The keccak256 hash of the guardian's identifier.
   * @param _isAdd Boolean indicating add (true) or remove (false).
   */
  function setCryptoLegacyGuardian(bytes32 _guardian, bool _isAdd) external {
    address _cryptoLegacy = msg.sender;
    _checkBuildManagerValid(_cryptoLegacy, address(0));
    if (_isAdd) {
      cryptoLegacyByGuardian[_guardian].add(_cryptoLegacy);
      emit AddCryptoLegacyForGuardian(_guardian, _cryptoLegacy);
    } else {
      cryptoLegacyByGuardian[_guardian].remove(_cryptoLegacy);
      emit RemoveCryptoLegacyForGuardian(_guardian, _cryptoLegacy);
    }
    _setBlockNumberChange(_cryptoLegacy);
  }

  /**
   * @notice Adds or removes the calling CryptoLegacy contract from the beneficiary registry under an owner role.
   * @dev Similar to setCryptoLegacyBeneficiary but for owner hashes.
   * @param _owner The keccak256 hash of the owner's identifier.
   * @param _isAdd Boolean indicating add (true) or remove (false).
   */
  function setCryptoLegacyOwner(bytes32 _owner, bool _isAdd) external {
    address _cryptoLegacy = msg.sender;
    _checkBuildManagerValid(_cryptoLegacy, address(0));
    if (_isAdd) {
      cryptoLegacyByOwner[_owner].add(_cryptoLegacy);
      emit AddCryptoLegacyForOwner(_owner, _cryptoLegacy);
    } else {
      cryptoLegacyByOwner[_owner].remove(_cryptoLegacy);
      emit RemoveCryptoLegacyForOwner(_owner, _cryptoLegacy);
    }
    _setBlockNumberChange(_cryptoLegacy);
  }

  /**
   * @notice Updates the recovery addresses for the calling CryptoLegacy contract in the registry.
   * @dev Removes the contract from old recovery hash sets and adds it to new ones.
   * @param _oldRecoveryHashes An array of old recovery hashes to remove.
   * @param _newRecoveryHashes An array of new recovery hashes to add.
   */
  function setCryptoLegacyRecoveryAddresses(bytes32[] memory _oldRecoveryHashes, bytes32[] memory _newRecoveryHashes) external {
    address _cryptoLegacy = msg.sender;
    _checkBuildManagerValid(_cryptoLegacy, address(0));
    for (uint256 i = 0; i < _oldRecoveryHashes.length; i++) {
      cryptoLegacyByRecovery[_oldRecoveryHashes[i]].remove(_cryptoLegacy);
      emit RemoveCryptoLegacyForRecovery(_oldRecoveryHashes[i], _cryptoLegacy);
    }
    for (uint256 i = 0; i < _newRecoveryHashes.length; i++) {
      cryptoLegacyByRecovery[_newRecoveryHashes[i]].add(_cryptoLegacy);
      emit AddCryptoLegacyForRecovery(_newRecoveryHashes[i], _cryptoLegacy);
    }
    _setBlockNumberChange(_cryptoLegacy);
  }

  /**
   * @notice Returns the list of CryptoLegacy contract addresses for a given beneficiary.
   * @param _hash The account hash.
   * @return An array of CryptoLegacy contract addresses.
   */
  function getCryptoLegacyListByBeneficiary(bytes32 _hash) public view returns(address[] memory) {
    return cryptoLegacyByBeneficiary[_hash].values();
  }

  /**
   * @notice Returns the list of CryptoLegacy contract addresses for a given owner.
   * @param _hash The account hash.
   * @return An array of CryptoLegacy contract addresses.
   */
  function getCryptoLegacyListByOwner(bytes32 _hash) external view returns(address[] memory) {
    return cryptoLegacyByOwner[_hash].values();
  }

  function getCryptoLegacyListByGuardian(bytes32 _hash) external view returns(address[] memory) {
    return cryptoLegacyByGuardian[_hash].values();
  }

  function getCryptoLegacyListByRecovery(bytes32 _hash) external view returns(address[] memory) {
    return cryptoLegacyByRecovery[_hash].values();
  }

  function getCryptoLegacyBlockNumberChanges(address _cryptoLegacy) external view returns(uint256[] memory) {
    return blockNumberChangesByCryptoLegacy[_cryptoLegacy];
  }

  /**
   * @notice Returns the list of CryptoLegacy contracts corresponding to `_hash` in a single call.
   * @dev Aggregates results for beneficiary, owner, guardian, and recovery roles.
   * @param _hash The keccak256 hash representing the user or role.
   * @return listByBeneficiary Array of CryptoLegacy addresses set under beneficiary role.
   * @return listByOwner Array of CryptoLegacy addresses set under owner role.
   * @return listByGuardian Array of CryptoLegacy addresses set under guardian role.
   * @return listByRecovery Array of CryptoLegacy addresses set under recovery role.
   */
  function getAllCryptoLegacyListByRoles(bytes32 _hash) external view returns(
    address[] memory listByBeneficiary,
    address[] memory listByOwner,
    address[] memory listByGuardian,
    address[] memory listByRecovery
  ) {
    listByBeneficiary = cryptoLegacyByBeneficiary[_hash].values();
    listByOwner = cryptoLegacyByOwner[_hash].values();
    listByGuardian = cryptoLegacyByGuardian[_hash].values();
    listByRecovery = cryptoLegacyByRecovery[_hash].values();
  }
}
