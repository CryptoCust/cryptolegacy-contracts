/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ICryptoLegacyOwnable {
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OwnableUnauthorizedAccount(address account);
}