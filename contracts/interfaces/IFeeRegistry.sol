/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./IDeBridgeGate.sol";
import "./ILifetimeNft.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IFeeRegistry {
    event AddCodeOperator(address indexed codeOperator);
    event RemoveCodeOperator(address indexed codeOperator);
    event SetDefaultPct(uint32 defaultDiscountPct, uint32 defaultSharePct);
    event SetRefererSpecificPct(address indexed referrer, bytes8 indexed code, uint32 discountPct, uint32 sharePct);
    event SetContractCaseFee(address indexed sourceContract, uint8 indexed contractCase, uint256 fee);
    event TakeFee(address indexed sourceContract, uint8 indexed contractCase, bytes8 indexed code, uint256 discount, uint256 share, uint256 fee, uint256 value);
    event SentFee(address indexed referrer, bytes8 indexed code, address indexed recipient, uint256 value);
    event AccumulateFee(address indexed referrer, bytes8 indexed code, address indexed recipient, uint256 value);
    event CreateCode(address indexed codeOperator, address indexed referrer, bytes8 indexed code, address recipient, uint256 fromChain);
    event UpdateCode(address indexed codeOperator, address indexed referrer, bytes8 indexed code, address recipient, uint256 fromChain);
    event ChangeCode(address indexed oldReferrer, address indexed newReferrer, bytes8 indexed code);
    event ChangeRecipient(address indexed referrer, address indexed newRecipient, bytes8 indexed code);
    event SetCrossChainsRef(bytes8 indexed shortCode, bool indexed isCreate, uint256[] toChainIDs, uint256[] crossChainFees);
    event SetFeeBeneficiaries(FeeBeneficiary[] beneficiaries);
    event AddSupportedRefCodeInChain(uint256 indexed chainId);
    event RemoveSupportedRefCodeInChain(uint256 indexed chainId);
    event WithdrawFee(address indexed beneficiary, uint256 value);
    event WithdrawRefFee(address indexed recipient, uint256 value);

    struct FRStorage {
        uint32 defaultDiscountPct;
        uint32 defaultSharePct;
        uint128 accumulatedFee;

        EnumerableSet.UintSet supportedRefInChains;
        mapping(bytes8 => Referrer) refererByCode;
        mapping(address => bytes8) codeByReferrer;
        EnumerableSet.AddressSet codeOperators;

        mapping(address => mapping(uint8 => uint128)) feeByContractCase;
        FeeBeneficiary[] feeBeneficiaries;
    }

    struct Referrer {
        address owner;
        address recipient;
        uint32 discountPct;
        uint32 sharePct;
        uint128 accumulatedFee;
    }
    struct FeeBeneficiary {
        address recipient;
        uint32 sharePct;
    }

    function getContractCaseFee(address _contract, uint8 _case) external view returns(uint256);
    function getContractCaseFeeForCode(address _contract, uint8 _case, bytes8 _code) external view returns(uint256 fee);
    function takeFee(address _contract, uint8 _case, bytes8 _code, uint256 _mul) external payable;

    function createCustomCode(address _referrer, address _recipient, bytes8 _shortCode, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable returns(bytes8 code, uint256 totalFee);
    function createCode(address _referrer, address _recipient, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable returns(bytes8 code, uint256 totalFee);
    function updateCrossChainsRef(address _referrer, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable returns(uint256 totalFee);

    function accumulatedFee() external view returns(uint128);

    function getSupportedRefInChainsList() external view returns(uint256[] memory);

    error PctSumDoesntMatchBase();
    error TooBigPct();
    error RefAlreadyCreated();
    error ZeroCode();
    error NotOperator();
    error NotReferrer();
    error AlreadyReferrer();
    error CodeNotCreated();
}

interface ILockChainGate {
    event AddLockOperator(address indexed lockOperator);
    event RemoveLockOperator(address indexed lockOperator);
    event SetDestinationChainContract(uint256 indexed chainId, address indexed chainContract);
    event SetSourceChainContract(uint256 indexed chainId, address indexed chainContract);
    event SetDeBridgeGate(address indexed deBridgeGate);
    event SetDeBridgeNativeFee(uint256 indexed chainId, uint256 nativeFee);
    event SetLockPeriod(uint256 lockPeriod);
    event SendToChain(uint256 indexed toChainId, bytes32 indexed submissionId, uint256 value, bytes dstTransactionCall);
    event LockNft(uint256 lockedAt, uint256 indexed tokenId, address indexed holder);
    event UnlockNft(uint256 lockedAt, uint256 indexed tokenId, address indexed holder, address indexed recipient);
    event ApproveNft(uint256 indexed tokenId, address indexed holder, address indexed approveTo);
    event TransferNft(uint256 indexed tokenId, address indexed holder, address indexed transferTo, uint256 fromChainID);
    event LockToChain(address indexed sender, uint256 indexed tokenId, uint256 indexed toChainID, bytes32 submissionId);
    event UpdateLockToChain(address indexed sender, uint256 indexed tokenId, uint256 indexed toChainID, bytes32 submissionId);
    event Update(address indexed sender, uint256 indexed tokenId, uint256 indexed toChainID, bytes32 submissionId);
    event UnlockFromChain(address indexed sender, uint256 indexed tokenId, uint256 indexed toChainID, bytes32 submissionId);
    event CrossLockNft(uint256 lockedAt, uint256 indexed tokenId, address indexed holder, uint256 indexed fromChainID);
    event CrossUnlockNft(uint256 lockedAt, uint256 indexed tokenId, address indexed holder, uint256 indexed fromChainID);
    event CrossUpdateNftOwner(uint256 indexed fromChainID, uint256 indexed tokenId, address indexed transferTo);
    event SetReferralCode(uint32 indexed referralCode);
    event SetCustomChainId(uint256 indexed customChainId);

    struct LCGStorage {
        IDeBridgeGate deBridgeGate;

        mapping(uint256 => uint256) deBridgeNativeFee;
        mapping(uint256 => address) destinationChainContracts;
        mapping(uint256 => address) sourceChainsContracts;

        EnumerableSet.AddressSet lockOperators;

        ILifetimeNft lifetimeNft;
        uint256 lockPeriod;
        mapping(address => LockedNft) lockedNft;
        mapping(uint256 => address) ownerOfTokenId;
        mapping(uint256 => EnumerableSet.UintSet) lockedToChainsIds;
        mapping(uint256 => uint256) lockedNftFromChainId;
        mapping(uint256 => address) lockedNftApprovedTo;
        uint32 referralCode;
        uint256 customChainId;
    }


    struct LockedNft {
        uint256 lockedAt;
        uint256 tokenId;
    }

    function lockLifetimeNft(uint256 _tokenId, address _owner, uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable;

    function isNftLocked(address _owner) external view returns(bool);

    function isNftLockedAndUpdate(address _owner) external returns(bool);

    function calculateCrossChainCreateRefNativeFee(uint256[] memory _chainIds, uint256[] memory _crossChainFees) external view returns(uint256);

    error AlreadyLocked();
    error LockedToChains();
    error CrossChainLock();
    error TooEarly();
    error DestinationChainNotSpecified();
    error TokenNotLocked();
    error TokenIdMismatch(uint256 checkTokenId);
    error AlreadyLockedToChain();
    error SourceNotSpecified();
    error NotLockedByChain();
    error DestinationNotSpecified();
    error NotAvailable();
    error IncorrectFee(uint256 requiredFee);
    error SameAddress();
    error RecipientLocked();
    error NotCallProxy();
    error ChainIdMismatch();
    error NotValidSender();
    error NotAllowed();
}
