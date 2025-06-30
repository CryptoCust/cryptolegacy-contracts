/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./IBeneficiaryRegistry.sol";
import "./ICryptoLegacy.sol";
import "./IPluginsRegistry.sol";

interface ICryptoLegacyBuildManager {
    event CreateRef(address indexed sender, bytes8 indexed refCode, address indexed recipient, uint256[] chainIds);
    event CreateCustomRef(address indexed sender, bytes8 indexed refCode, address indexed recipient, uint256[] chainIds);
    event SetCrossChainsRef(address indexed sender, uint256[] chainIds);
    event WithdrawFee(address indexed recipient, uint256 indexed amount);
    event SetRegistries(address indexed feeRegistry, address indexed pluginsRegistry, address indexed beneficiaryRegistry);
    event SetFactory(address indexed factory);
    event SetSupplyLimit(uint256 supplyLimit);
    event SetExternalLens(address indexed externalLens);
    event PaidForMint(address indexed sender, uint256 indexed tokenId, address indexed toHolder);
    event PaidForMultipleNft(address indexed sender, bytes8 indexed code, uint256 value, uint256 totalAmount);
    event Build(address indexed sender, address indexed cryptoLegacy, address[] plugins, bytes32[] beneficiaryHashes, ICryptoLegacy.BeneficiaryConfig[] beneficiaryConfig, bool isPaid, uint64 updateInterval, uint64 challengeTimeout);

    struct BuildArgs {
        bytes8 invitedByRefCode;
        bytes32[] beneficiaryHashes;
        ICryptoLegacy.BeneficiaryConfig[] beneficiaryConfig;
        address[] plugins;
        uint64 updateInterval;
        uint64 challengeTimeout;
    }

    struct RefArgs {
        address createRefRecipient;
        bytes8 createRefCustomCode;
        uint256[] createRefChains;
        uint256[] crossChainFees;
    }

    struct LifetimeNftMint {
        address toHolder;
        uint256 amount;
    }

    function payInitialFee(bytes8 _code, address _toHolder, uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable returns(uint256 returnValue);

    function payFee(bytes8 _code, address _toHolder, uint256 _mul, uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable returns(uint256 returnValue);

    function getUpdateFee(bytes8 _refCode) external returns(uint256);

    function isLifetimeNftLocked(address _owner) external view returns(bool);

    function isLifetimeNftLockedAndUpdate(address _owner) external returns(bool);

    function isPluginRegistered(address _plugin) external view returns(bool);

    function isCryptoLegacyBuilt(address _cryptoLegacy) external view returns(bool);

    function pluginsRegistry() external view returns(IPluginsRegistry);

    function getFactoryAddress() external view returns(address);

    function beneficiaryRegistry() external view returns(IBeneficiaryRegistry);

    function externalLens() external view returns(address);

    error AlreadyLifetime();
    error WithdrawFeeFailed(bytes reason);
    error NotValidTimeout();
    error IncorrectFee(uint256 feeToTake);
    error BelowMinimumSupply(uint256 supplyLimit);
    error NotRegisteredCryptoLegacy();
    error NotOwnerOfCryptoLegacy();
    error TransferFeeFailed(bytes response);
}
