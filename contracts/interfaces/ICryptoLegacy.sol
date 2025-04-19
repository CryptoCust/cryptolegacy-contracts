/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ICryptoLegacyBuildManager.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface ICryptoLegacy {
    event PauseSet(bool indexed isPaused);
    event Update(uint256 updateFee, bytes32 indexed byPlugin);
    event FeePaidByLifetime(bytes8 indexed refCode, bool indexed initial, address factory, uint64 lastFeePaidAt);
    event FeePaidByDefault(bytes8 indexed refCode, bool indexed initial, uint256 value, address factory, uint64 lastFeePaidAt);
    event FeePaidByTransfer(bytes8 indexed refCode, bool indexed initial, uint256 value, address factory, uint64 lastFeePaidAt);
    event FeeSentToRefByTransfer(bytes8 indexed refCode, uint256 value, address referral);
    event BeneficiaryClaim(address indexed token, uint256 amount, bytes32 indexed beneficiary);
    event TransferTreasuryTokensToLegacy(address[] holders, address[] tokens);
    event TransferTokensFromLegacy(ICryptoLegacy.TokenTransferTo[] transfers);
    event AddFunctions(address _facetAddress, bytes4[] _functionSelectors, uint16 selectorPosition);
    event RemoveFunctions(address _facetAddress, bytes4[] _functionSelectors);

    struct BeneficiaryConfig {
        uint64 claimDelay;
        uint64 vestingPeriod;
        uint64 shareBps;
    }
    struct BeneficiaryVesting {
        mapping(address => uint256) tokenAmountClaimed; // token => claimedAmount
    }
    struct TokenDistribution {
        uint256 amountToDistribute;
        uint256 totalClaimedAmount;
    }
    struct CryptoLegacyStorage {
        bool isPaused;
        uint128 initialFeeToPay;
        uint128 updateFee;
        uint64 updateInterval;
        uint64 challengeTimeout;
        uint64 lastFeePaidAt;
        uint64 lastUpdateAt;
        uint64 distributionStartAt;
        bytes8 invitedByRefCode;
        uint8 defaultFuncDisabled; // 1 - beneficiaryClaim
        ICryptoLegacyBuildManager buildManager;
        EnumerableSet.Bytes32Set beneficiaries;
        mapping(bytes32 => BeneficiaryConfig) beneficiaryConfig;
        mapping(bytes32 => bytes32) originalBeneficiaryHash;
        mapping(bytes32 => BeneficiaryVesting) beneficiaryVesting; // originalHash => BeneficiaryVesting

        mapping(address => TokenDistribution) tokenDistribution;

        mapping(bytes32 => uint64[]) beneficiaryMessagesGotByBlockNumber;
        uint64[] transfersGotByBlockNumber;
    }

    struct TokenTransferTo {
        address token;
        address recipient;
        uint256 amount;
    }

    function buildManager() external view returns(ICryptoLegacyBuildManager);

    function owner() external view returns(address);

    error DisabledFunc();
    error NotTheOwner();
    error NotTheBeneficiary();
    error BeneficiaryNotExist();
    error TooEarly();
    error NoValueAllowed();
    error TooLongArray(uint256 maxLength);
    error IncorrectFee(uint256 requiredFee);
    error ZeroAddress();
    error ZeroTokens();
    error InitialFeeNotPaid();
    error InitialFeeAlreadyPaid();
    error NotBuildManager();
    error AlreadyInit();
    error LengthMismatch();
    error ShareSumDoesntMatchBase();
    error DistributionStarted();
    error DistributionStartAlreadySet();
    error DistributionDelay();
    error AlreadySet();
    error BeneficiaryNotSet();
    error Pause();
    error IncorrectFacetCutAction();
    error NotContractOwner();
    error FacetNotFound();
    error FacetHasNoCode();
    error NoSelectorsInFacetToCut();
    error FacetCantBeZero();
    error CantRemoveImmutableFunctions();
    error CantAddFunctionThatAlreadyExists();
    error CantReplaceFunctionWithSameFunction();
    error InitFunctionReverted();
    error InitAddressZeroButCalldataIsNot();
    error InitCalldataZeroButAddressIsNot();
    error PluginNotRegistered();
}