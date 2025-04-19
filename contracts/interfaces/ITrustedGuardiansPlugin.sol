/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface ITrustedGuardiansPlugin {
    event SetGuardian(bytes32 indexed guardian, bool indexed _isAdd);
    event GuardiansVoteForDistribution(bytes32 indexed guardian, uint256 votedCount);
    event GuardiansDistributionStartSet(bytes32 indexed guardian, uint256 distributionStartAt);
    event SetGuardiansConfig(uint8 guardiansThreshold, uint64 guardiansChallengeTimeout);
    event ResetGuardiansVoting();

    struct PluginStorage {
        EnumerableSet.Bytes32Set guardians;
        bytes32[] guardiansVoted;
        uint8 guardiansThreshold;
        uint64 guardiansChallengeTimeout;
    }
    struct GuardianToChange {
        bytes32 hash;
        bool isAdd;
    }

    function isGuardiansInitialized() external view returns(bool);

    error NotGuardian();
    error ThresholdDontMet();
    error GuardianAlreadyVoted();
    error MaxGuardiansTimeout(uint64 guardiansThreshold);
}