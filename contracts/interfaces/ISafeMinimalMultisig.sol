/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ICryptoLegacyBuildManager.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface ISafeMinimalMultisig {
    event CreateSafeMinimalMultisigProposal(uint256 proposalId, bytes32 voter, uint256 reqConfirmations);
    event ConfirmSafeMinimalMultisigProposal(uint256 proposalId, bytes32 voter, uint256 reqConfirmations, uint256 confirms);
    event ExecuteSafeMinimalMultisigProposal(uint256 proposalId, bytes32 voter, bool executed, bytes returnData);
    event SetVotersAndConfirmations(bytes32[] voters, uint256 requiredConfirmations);
    event SetConfirmations(uint256 requiredConfirmations);

    struct Storage {
        uint256 requiredConfirmations;
        bytes32[] voters;
        Proposal[] proposals;
        mapping(uint256 => mapping(bytes32 => bool)) confirmedBy;
    }

    struct Proposal {
        bytes4 selector;
        bytes params;
        uint256 confirms;
        bool executed;
    }

    struct ProposalWithStatus {
        Proposal proposal;
        bool[] confirmedBy;
    }

    enum InitializationStatus {
        UNKNOWN,
        INITIALIZED,
        NOT_INITIALIZED_NO_NEED,
        NOT_INITIALIZED_BUT_NEED
    }

    error MultisigAlreadyExecuted();
    error MultisigAlreadyConfirmed();
    error MultisigExecutionFailed();
    error MultisigMethodNotAllowed();
    error MultisigVoterNotAllowed();
    error MultisigOnlyExecutor();
    error MultisigIncorrectRequiredConfirmations();
}