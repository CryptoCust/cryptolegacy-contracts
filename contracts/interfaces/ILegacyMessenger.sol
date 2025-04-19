/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ILegacyMessenger {
    event LegacyMessage(bytes32 indexed toRecipient, bytes32 messageHash, bytes message, uint256 indexed messageType);
    event LegacyMessageCheck(bytes32 indexed toBeneficiary, bytes32 messageHash, bytes message, uint256 indexed messageType);
}