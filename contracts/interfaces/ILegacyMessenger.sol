/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ILegacyMessenger {
    event LegacyMessage(address indexed legacy, bytes32 indexed toRecipient, bytes32 messageHash, bytes message, uint256 indexed messageType);
    event LegacyMessageCheck(address indexed legacy, bytes32 indexed toBeneficiary, bytes32 messageHash, bytes message, uint256 indexed messageType);
}