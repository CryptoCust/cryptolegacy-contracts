/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./interfaces/ICryptoLegacy.sol";
import "./interfaces/IBuildManagerOwnable.sol";
import "./interfaces/ICryptoLegacyBuildManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title BuildManagerOwnable
 * @notice Provides functionality for managing and verifying build managers for CryptoLegacy contracts.
 */
contract BuildManagerOwnable is IBuildManagerOwnable, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Storage set of valid build manager addresses.
    EnumerableSet.AddressSet internal buildManagerAdded;

    constructor() Ownable() {
    }

    /**
     * @notice Adds or removes a build manager.
     * @dev Only the owner may call this function. The function adds _buildManager to or removes it from the set.
     * @param _buildManager The address to be added or removed.
     * @param _isAdd True to add the build manager; false to remove.
     */
    function setBuildManager(address _buildManager, bool _isAdd) external onlyOwner {
        if (_isAdd) {
            buildManagerAdded.add(_buildManager);
            emit AddBuildManager(_buildManager);
        } else {
            buildManagerAdded.remove(_buildManager);
            emit RemoveBuildManager(_buildManager);
        }
    }

    /**
     * @notice Internal helper to check that the given CryptoLegacy contract was built by a valid manager.
     * @dev Reverts if the contract owner differs from `_clOwner` (when specified) or if the buildManager address is not in the set.
     * @param _cryptoLegacy The CryptoLegacy contract address to verify.
     * @param _clOwner If non-zero, the verified contract owner must match this address.
     */
    function _checkBuildManagerValid(address _cryptoLegacy, address _clOwner) internal view {
        ICryptoLegacyBuildManager buildManager = ICryptoLegacy(_cryptoLegacy).buildManager();

        if (_clOwner != address(0) && ICryptoLegacy(_cryptoLegacy).owner() != _clOwner) {
            revert NotTheOwnerOfCryptoLegacy();
        }
        if (!buildManager.isCryptoLegacyBuilt(_cryptoLegacy)) {
            revert CryptoLegacyNotRegistered();
        }
        if (!buildManagerAdded.contains(address(buildManager))) {
            revert BuildManagerNotAdded();
        }
    }

    /**
     * @notice Returns the list of build managers that have been added.
     * @return An array of build manager addresses.
     */
    function getBuildManagerAdded() external view returns(address[] memory) {
        return buildManagerAdded.values();
    }
}
