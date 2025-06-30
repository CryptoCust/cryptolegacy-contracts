/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ICryptoLegacyBuildManager.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface ISafeMinimalMultisig {
    event CreateSafeMinimalMultisigProposal(uint256 proposalId, bytes32 voter, uint128 reqConfirmations);
    event CancelSafeMinimalMultisigProposal(uint256 proposalId, bytes32 voter, uint128 reqConfirmations, ProposalStatus status);
    event ConfirmSafeMinimalMultisigProposal(uint256 proposalId, bytes32 voter, uint128 reqConfirmations, uint256 confirms);
    event ExecuteSafeMinimalMultisigProposal(uint256 proposalId, bytes32 voter, bool executed, bytes returnData);
    event SetVotersAndConfirmations(bytes32[] voters, uint128 requiredConfirmations);
    event SetConfirmations(uint128 requiredConfirmations);
    event AddHeldEth(bytes32 voter, uint256 value);
    event WithdrawHeldEth(bytes32 voter, uint256 value);

    struct Storage {
        uint128 requiredConfirmations;
        bytes32[] voters;
        Proposal[] proposals;
        mapping(uint256 => mapping(bytes32 => bool)) confirmedBy;
        mapping(bytes32 => uint256) heldEth;
    }

    enum ProposalStatus {
        NOT_EXIST,
        PENDING,
        CANCELED,
        EXECUTED
    }

    struct Proposal {
        bytes params;
        uint128 confirms;
        bytes4 selector;
        ProposalStatus status;
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

    error MultisigProposalNotPending();
    error MultisigNotConfirmed();
    error MultisigExecutionFailed();
    error MultisigMethodNotAllowed();
    error MultisigVoterNotAllowed();
    error MultisigOnlyExecutor();
    error MultisigIncorrectRequiredConfirmations();
    error MultisigNothingToWithdraw();
    error TransferFeeFailed(bytes response);
}