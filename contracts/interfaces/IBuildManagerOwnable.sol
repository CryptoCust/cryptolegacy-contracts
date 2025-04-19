/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IBuildManagerOwnable {
    event AddBuildManager(address indexed buildManager);
    event RemoveBuildManager(address indexed buildManager);

    error NotTheOwnerOfCryptoLegacy();
    error CryptoLegacyNotRegistered();
    error BuildManagerNotAdded();
}