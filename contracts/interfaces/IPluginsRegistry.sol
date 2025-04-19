/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IPluginsRegistry {
    event AddPlugin(address indexed plugin, string description);
    event AddPluginDescription(address indexed plugin, string description);
    event RemovePlugin(address indexed plugin);

    struct PluginInfo {
        address plugin;
        string name;
        uint16 version;
        uint64[] descriptionBlockNumbers;
    }

    function getPluginDescriptionBlockNumbers(address _plugin) external view returns(uint64[] memory);

    function isPluginRegistered(address _plugin) external view returns(bool);
}
