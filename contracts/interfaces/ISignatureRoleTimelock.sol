/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ISignatureRoleTimelock {
    event SetMaxExecutionPeriod(uint128 indexed maxExecutionPeriod);
    event AddRoleAccount(bytes32 indexed role, address indexed account);
    event RemoveRoleAccount(bytes32 indexed role, address indexed account);
    event AddSignatureRole(address indexed target, bytes4 indexed signature, bytes32 indexed role, uint256 timelock);
    event RemoveSignatureRole(address indexed target, bytes4 indexed signature);
    event AddTarget(address indexed target);
    event RemoveTarget(address indexed target);
    event CallScheduled(bytes32 indexed callId, address indexed caller, address indexed target, bytes4 signature, uint256 executeAfter);
    event CallExecuted(bytes32 indexed callId, address indexed msgSender, bytes returnData);
    event CallCanceled(bytes32 indexed callId, address indexed msgSender);

    struct CallRequest {
        address caller;
        address target;
        bytes data;
        uint128 executeAfter;
        uint128 executeBefore;
        bool pending;
    }

    struct AddressRoleInput {
        bytes32 role;
        address newAccount;
        address prevAccount;
    }

    struct SignatureAttr {
        bytes32 role;
        uint128 timelock;
    }

    struct SignatureToAdd {
        address target;
        bytes4 signature;
        bytes32 role;
        uint128 timelock;
    }

    struct SignatureToRemove {
        address target;
        bytes4 signature;
    }

    struct CallToAdd {
        address target;
        bytes data;
    }

    struct TargetSigRes {
        bytes4 signature;
        bytes32 role;
        uint256 timelock;
    }

    error AlreadyHaveRole();
    error DoesntHaveRole();
    error RoleDontExist();
    error CallerNotCurrentAddress();
    error IncorrectSignatureIndex();
    error IncorrectRoleIndex();
    error CallFailed(bytes errorMessage);
    error CallNotScheduled();
    error NotPending();
    error TimelockActive();
    error TimelockExpired();
    error CallerHaveNoRequiredRole(bytes32 requiredRole);
    error CallAlreadyScheduled();
    error SignatureAlreadyExists();
    error SignatureTimeLockNotSet(bytes4 signature);
    error OutOfTimelockBounds(uint256 maxTimelock);
    error OutOfMaxExecutionPeriodBounds(uint256 minPeriod, uint256 maxPeriod);
}