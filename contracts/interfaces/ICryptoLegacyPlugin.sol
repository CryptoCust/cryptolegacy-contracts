/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICryptoLegacyPlugin {
    function getSigs() external view returns (bytes4[] memory);
    function getSetupSigs() external view returns (bytes4[] memory);
    function getPluginName() external view returns (string memory);
    function getPluginVer() external view returns (uint16);
}