/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./CryptoLegacyOwnable.sol";
import "./libraries/LibDiamond.sol";
import "./CryptoLegacyDiamondBase.sol";
import "./interfaces/ICryptoLegacy.sol";
import "./libraries/LibCryptoLegacy.sol";
import "./libraries/LibCryptoLegacyPlugins.sol";
import "./interfaces/ICryptoLegacyBuildManager.sol";

/**
 * @title CryptoLegacy: A Modular Inheritance Management System Leveraging the EIP-2535 Diamond Standard with an Extensible, Ready-to-Use Plugin Architecture for Secure and Flexible Crypto Asset Legacy Solutions
 * @notice This contract implements a decentralized crypto inheritance and asset recovery system using the Diamond Standard (EIP-2535) to allow dynamic upgrades and modular plugin integration.
 */
contract CryptoLegacy is CryptoLegacyDiamondBase, CryptoLegacyOwnable {

  constructor(address _buildManager, address _owner, address[] memory _plugins) {
    ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

    cls.buildManager = ICryptoLegacyBuildManager(_buildManager);
    cls.lastUpdateAt = uint64(block.timestamp);
    LibDiamond.setContractOwner(_owner);
    LibCryptoLegacyPlugins._addPluginList(cls, _plugins);
  }

  /**
   * @notice Replaces existing plugins with new ones.
   * @param _oldPlugins Array of plugin addresses to remove.
   * @param _newPlugins Array of plugin addresses to add.
   */
  function replacePlugin(address[] memory _oldPlugins, address[] memory _newPlugins) external onlyOwner {
    for (uint256 i = 0; i < _oldPlugins.length; i++) {
      LibCryptoLegacyPlugins._removePlugin(ICryptoLegacyPlugin(_oldPlugins[i]));
    }
    LibCryptoLegacyPlugins._addPluginList(LibCryptoLegacy.getCryptoLegacyStorage(),_newPlugins);
  }

  /**
   * @notice Adds additional plugins to the contract.
   * @param _plugins Array of plugin addresses.
   */
  function addPluginList(address[] memory _plugins) external onlyOwner {
    LibCryptoLegacyPlugins._addPluginList(LibCryptoLegacy.getCryptoLegacyStorage(),_plugins);
  }

  /**
   * @notice Removes plugins from the contract.
   * @param _plugins Array of plugin addresses.
   */
  function removePluginList(address[] memory _plugins) external onlyOwner {
    for (uint256 i = 0; i < _plugins.length; i++) {
      LibCryptoLegacyPlugins._removePlugin(ICryptoLegacyPlugin(_plugins[i]));
    }
  }

  /**
   * @notice Provides the external lens address for easier integration with explorers.
   * @return The external lens address.
   */
  function externalLens() external view returns(address) {
    ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    return cls.buildManager.externalLens();
  }
}
