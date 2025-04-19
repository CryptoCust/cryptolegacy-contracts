/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ICryptoLegacyDiamondBase {
    event StaticCallCheck();

    error FunctionNotExists(bytes4 selector);
    error NotSelfCall();
}