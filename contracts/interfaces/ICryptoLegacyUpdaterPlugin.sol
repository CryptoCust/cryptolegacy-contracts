/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICryptoLegacyUpdaterPlugin {
    event AddUpdater(address indexed owner, address indexed updater);
    event RemoveUpdater(address indexed owner, address indexed updater);

    error NotTheUpdater();
}