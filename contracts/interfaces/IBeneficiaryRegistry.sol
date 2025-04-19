/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface IBeneficiaryRegistry {
    event AddCryptoLegacyForBeneficiary(bytes32 indexed beneficiary, address indexed cryptoLegacy);
    event RemoveCryptoLegacyForBeneficiary(bytes32 indexed beneficiary, address indexed cryptoLegacy);

    event AddCryptoLegacyForGuardian(bytes32 indexed guardian, address indexed cryptoLegacy);
    event RemoveCryptoLegacyForGuardian(bytes32 indexed guardian, address indexed cryptoLegacy);

    event AddCryptoLegacyForRecovery(bytes32 indexed recovery, address indexed cryptoLegacy);
    event RemoveCryptoLegacyForRecovery(bytes32 indexed recovery, address indexed cryptoLegacy);

    event AddCryptoLegacyForOwner(bytes32 indexed owner, address indexed cryptoLegacy);
    event RemoveCryptoLegacyForOwner(bytes32 indexed owner, address indexed cryptoLegacy);

    enum EntityType {
        NONE,
        OWNER,
        BENEFICIARY,
        GUARDIAN,
        RECOVERY
    }
    function setCryptoLegacyBeneficiary(bytes32 _beneficiary, bool _isAdd) external;

    function setCryptoLegacyOwner(bytes32 _owner, bool _isAdd) external;

    function setCryptoLegacyGuardian(bytes32 _guardian, bool _isAdd) external;

    function setCryptoLegacyRecoveryAddresses(bytes32[] memory _oldRecoveryAddresses, bytes32[] memory _newRecoveryAddresses) external;

    function getAllCryptoLegacyListByRoles(bytes32 _hash) external view returns(
        address[] memory listByBeneficiary,
        address[] memory listByOwner,
        address[] memory listByGuardian,
        address[] memory listByRecovery
    );
}
