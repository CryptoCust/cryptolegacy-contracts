/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../interfaces/ICryptoLegacy.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";
import "../interfaces/ICryptoLegacyUpdaterPlugin.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../libraries/LibDiamond.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title UpdateRolePlugin
 * @notice Enables decentralized update management by allowing designated updaters (beyond the contract owner) to trigger state updates. It includes role assignment, verification, and secure update execution to maintain continuous system operation.
*/
contract UpdateRolePlugin is ICryptoLegacyPlugin, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant PLUGIN_POSITION = keccak256("update_role.plugin.storage");

    /**
     * @notice Returns the function selectors for update role management.
     * @dev These selectors correspond to the externally callable functions of the UpdateRolePlugin.
     * @return sigs An array of function selectors.
     */
    function getSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](4);
        sigs[0] = this.setUpdater.selector;
        sigs[1] = this.updateByUpdater.selector;
        sigs[2] = this.isUpdater.selector;
        sigs[3] = this.getUpdaterList.selector;
    }

    /**
     * @notice Returns the setup function selectors for this plugin.
     * @return sigs An array containing the setup function selector.
     */
    function getSetupSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](1);
        sigs[0] = this.isUpdater.selector;
    }

    /**
     * @notice Returns the unique name for this plugin.
     * @dev The name is used for identification purposes across the CryptoLegacy ecosystem.
     * @return A string representing the plugin name.
     */
    function getPluginName() public pure returns (string memory) {
        return "update_role";
    }

    /**
     * @notice Returns the version number for this plugin.
     * @dev The version returned is encoded as a uint16.
     * @return The plugin version.
     */
    function getPluginVer() external pure returns (uint16) {
        return uint16(1);
    }

    /**
     * @notice Defines the plugin storage for update role management.
     * @dev Uses an EnumerableSet to manage updater addresses.
     */
    struct PluginStorage {
        EnumerableSet.AddressSet updaters;
    }

    /**
     * @notice Retrieves the plugin storage using the fixed storage slot.
     * @dev Uses inline assembly to assign the storage slot defined by PLUGIN_POSITION.
     * @return storageStruct A reference to the PluginStorage struct.
     */
    function getPluginStorage() internal pure returns (PluginStorage storage storageStruct) {
        bytes32 position = PLUGIN_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }

    /**
     * @notice Returns the owner of the contract.
     * @dev Delegates to LibDiamond.contractOwner() for owner retrieval.
     * @return The address of the contract owner.
     */
    function owner() public view returns (address) {
        return LibDiamond.contractOwner();
    }

    /**
     * @notice Modifier that restricts function access to the owner.
     * @dev Invokes LibCryptoLegacy._checkOwner() to verify that msg.sender is the contract owner.
     */
    modifier onlyOwner() {
        LibCryptoLegacy._checkOwner();
        _;
    }

    /**
     * @notice Modifier to restrict access to approved updaters.
     * @dev Ensures that distribution is ready and that msg.sender is contained in the updater set.
     * Reverts with ICryptoLegacyUpdaterPlugin.NotTheUpdater if the caller is not an approved updater.
     */
    modifier onlyUpdater() {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        PluginStorage storage pluginStorage = getPluginStorage();
        LibCryptoLegacy._checkDistributionStart(cls);
        if (!pluginStorage.updaters.contains(msg.sender)) {
            revert ICryptoLegacyUpdaterPlugin.NotTheUpdater();
        }
        _;
    }

    /**
     * @notice Returns the list of updater addresses.
     * @return An array of addresses currently designated as updaters.
     */
    function getUpdaterList() public view returns(address[] memory) {
        PluginStorage storage pluginStorage = getPluginStorage();
        return pluginStorage.updaters.values();
    }

    /**
     * @notice Checks whether an address is an updater.
     * @param _acc The address to check.
     * @return True if _acc is in the updater set, false otherwise.
     */
    function isUpdater(address _acc) public view returns(bool) {
        PluginStorage storage pluginStorage = getPluginStorage();
        return pluginStorage.updaters.contains(_acc);
    }

    /**
     * @notice Adds or removes an updater address.
     * @dev Only the owner may call this function. Emits an AddUpdater event when adding and RemoveUpdater event when removing.
     * @param _updater The address to be added or removed.
     * @param _toAdd True to add the address; false to remove it.
     */
    function setUpdater(address _updater, bool _toAdd) external payable onlyOwner nonReentrant {
        PluginStorage storage pluginStorage = getPluginStorage();
        if (_toAdd) {
            pluginStorage.updaters.add(_updater);
            emit ICryptoLegacyUpdaterPlugin.AddUpdater(msg.sender, _updater);
        } else {
            pluginStorage.updaters.remove(_updater);
            emit ICryptoLegacyUpdaterPlugin.RemoveUpdater(msg.sender, _updater);
        }
    }

    /**
     * @notice Allows an updater to trigger a contract update.
     * @dev This function takes the required fee, sets the new lastUpdateAt timestamp, and resets distributionStartAt to zero. Requirements: - Caller must be an updater (as verified by isUpdater).
     * @param _lockToChainIds An array of chain IDs for which fee locking is applied.
     * @param _crossChainFees An array of fees corresponding to each chain in _lockToChainIds.
     */
    function updateByUpdater(uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable onlyUpdater nonReentrant {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        LibCryptoLegacy._takeFee(cls, owner(), address(0), 0, _lockToChainIds, _crossChainFees);

        cls.lastUpdateAt = uint64(block.timestamp);
        cls.distributionStartAt = uint64(0);
        emit ICryptoLegacy.Update(msg.value, keccak256(abi.encode(getPluginName())));
    }
}