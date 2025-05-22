/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ICryptoLegacy.sol";

interface ICryptoLegacyLens {
    function getMessagesBlockNumbersByRecipient(bytes32 _recipient) external view returns(uint64[] memory blockNumbers);

    struct BeneficiaryTokenData {
        uint256 claimableAmount;
        uint256 claimedAmount;
        uint256 totalAmount;
    }
    function getVestedAndClaimedData(bytes32 _beneficiary, address[] memory _tokens) external view returns(BeneficiaryTokenData[] memory result, uint64 startDate, uint64 endDate);

    struct PluginInfo {
        address plugin;
        string name;
        uint16 version;
        uint64[] descriptionBlockNumbers;
    }

    struct CryptoLegacyBaseData {
        uint128 initialFeeToPay;
        uint128 updateFee;
        uint64 updateInterval;
        uint64 challengeTimeout;
        uint64 lastFeePaidAt;
        uint64 lastUpdateAt;
        uint64 distributionStartAt;
        bytes8 invitedByRefCode;
        uint8 defaultFuncDisabled;
        address buildManager;
    }
    function getCryptoLegacyBaseData() external view returns(CryptoLegacyBaseData memory data);

    struct LensTokenDistribution {
        uint128 amountToDistribute;
        uint128 lastBalance;
        uint128 totalClaimed;
    }
    struct CryptoLegacyListData {
        bytes32[] beneficiaries;
        bytes32[] beneficiariesOriginalHashes;
        uint64[] transfersGotByBlockNumber;
        ICryptoLegacy.BeneficiaryConfig[] beneficiaryConfigArr;
        PluginInfo[] plugins;
        LensTokenDistribution[] tokenDistributions;
    }

    function getCryptoLegacyListData(address[] memory _tokens) external view returns(CryptoLegacyListData memory data);
}