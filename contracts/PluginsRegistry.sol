/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./interfaces/IPluginsRegistry.sol";
import "./interfaces/ICryptoLegacyPlugin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title PluginsRegistry
 * @notice Manages the registration and metadata storage of CryptoLegacy plugins.
 */
contract PluginsRegistry is IPluginsRegistry, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet private pluginsList;
  mapping(address => uint64[]) public pluginDescriptionBlockNumbers;

  /**
   * @notice Constructs the PluginsRegistry contract.
   * @dev Sets the contract owner.
   * @param _owner The address which will become the owner.
   */
  constructor(address _owner) Ownable() {
    _transferOwnership(_owner);
  }

  /**
   * @notice Adds a new plugin to the registry.
   * @dev Adds the plugin address to the internal plugins list and records the block number for the provided description.
   * @param _plugin The address of the plugin contract.
   * @param _description A string providing a description of the plugin.
   */
  function addPlugin(address _plugin, string memory _description) public onlyOwner {
    pluginsList.add(_plugin);
    pluginDescriptionBlockNumbers[_plugin].push(uint64(block.number));
    emit AddPlugin(_plugin, _description);
  }

  /**
   * @notice Adds an additional description to an already registered plugin.
   * @dev Records the current block number to track when the description was added.
   * @param _plugin The address of the plugin contract.
   * @param _description A string describing the plugin update.
   */
  function addPluginDescription(address _plugin, string memory _description) public onlyOwner {
    pluginDescriptionBlockNumbers[_plugin].push(uint64(block.number));
    emit AddPluginDescription(_plugin, _description);
  }

  /**
   * @notice Removes a plugin from the registry.
   * @dev Deletes the plugin address from the internal plugins list.
   * @param _plugin The address of the plugin to remove.
   */
  function removePlugin(address _plugin) public onlyOwner {
    pluginsList.remove(_plugin);
    emit RemovePlugin(_plugin);
  }

  /**
   * @notice Checks if `_plugin` is currently registered in the pluginsList.
   * @param _plugin Address of the plugin to check.
   * @return True if registered, false otherwise.
   */
  function isPluginRegistered(address _plugin) public view returns(bool) {
    return pluginsList.contains(_plugin);
  }

  /**
   * @notice Retrieves metadata for a given plugin.
   * @dev Obtains the plugin name and version from the plugin contract and returns the associated description block numbers.
   * @param _plugin The address of the plugin contract.
   * @return name The name of the plugin.
   * @return version The version of the plugin.
   * @return descriptionBlockNumbers An array of block numbers indicating when descriptions were added.
   */
  function getPluginMetadata(address _plugin) public view returns(
    string memory name,
    uint16 version,
    uint64[] memory descriptionBlockNumbers
  ) {
    return (
      ICryptoLegacyPlugin(_plugin).getPluginName(),
      ICryptoLegacyPlugin(_plugin).getPluginVer(),
      pluginDescriptionBlockNumbers[_plugin]
    );
  }

  /**
   * @notice Retrieves the array of block numbers for a plugin's description updates.
   * @param _plugin The address of the plugin contract.
   * @return An array of block numbers.
   */
  function getPluginDescriptionBlockNumbers(address _plugin) external view returns(uint64[] memory) {
    return pluginDescriptionBlockNumbers[_plugin];
  }

  /**
   * @notice Returns the list of registered plugin addresses.
   * @return An array of plugin contract addresses.
   */
  function getPluginAddressList() public view returns(address[] memory) {
    return pluginsList.values();
  }

  /**
   * @notice Retrieves detailed information for all registered plugins.
   * @dev Iterates over the plugins list and aggregates each plugin's metadata into an array of PluginInfo structs.
   * @return An array of PluginInfo structures containing address, name, version, and description timestamps.
   */
  function getPluginInfoList() public view returns(PluginInfo[] memory) {
    address[] memory addresses = getPluginAddressList();
    PluginInfo[] memory plugins = new PluginInfo[](addresses.length);

    for (uint256 i = 0; i < addresses.length; i++) {
      (string memory name, uint16 version, uint64[] memory descriptionBlockNumbers) = getPluginMetadata(addresses[i]);
      plugins[i] = PluginInfo(addresses[i], name, version, descriptionBlockNumbers);
    }
    return plugins;
  }
}
