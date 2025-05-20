/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./LockChainGate.sol";
import "./interfaces/IFeeRegistry.sol";
import "./interfaces/ILifetimeNft.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title FeeRegistry
 * @notice Manages fee settings, referral codes and fee collection for CryptoLegacy contracts.
 */
contract FeeRegistry is LockChainGate, IFeeRegistry {
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;

  uint32 constant public PCT_BASE = 10000; // Denominator for percentage calculations.
  bytes32 constant internal FR_STORAGE_POSITION = keccak256("crypto_legacy.fee_registry.storage");

  /**
   * @notice Constructor (proxy-initialized) that disables direct initialization logic. 
   * @dev The actual initialization is in `initialize()`.
   */
  constructor() {}

  /**
   * @notice Retrieves the FeeRegistry storage pointer.
   * @dev Uses inline assembly to load the storage pointer from the predefined FR_STORAGE_POSITION slot.
   * @return fs A storage reference to the FRStorage struct.
   */
  function lockFeeRegistryStorage() internal pure returns (FRStorage storage fs) {
    bytes32 position = FR_STORAGE_POSITION;
    assembly {
      fs.slot := position
    }
  }

  /**
   * @notice Initializes the FeeRegistry by setting default discount/share percentages and hooking up the LifetimeNft + LockChainGate config.
   * @param _owner The contract owner address.
   * @param _defaultDiscountPct The default discount for fees, base is 10,000.
   * @param _defaultSharePct The default share for referrals, base is 10,000.
   * @param _lifetimeNft The LifetimeNft contract address.
   * @param _lockPeriod The lock period for lifetime NFTs.
   * @param _transferTimeout The time between lock and transfer for NFTs.
   */
  function initialize(address _owner, uint32 _defaultDiscountPct, uint32 _defaultSharePct, ILifetimeNft _lifetimeNft, uint64 _lockPeriod, uint64 _transferTimeout) external initializer {
    _setDefaultPct(lockFeeRegistryStorage(), _defaultDiscountPct, _defaultSharePct);
    _initializeLockChainGate(_lifetimeNft, _lockPeriod, _transferTimeout, _owner);
  }

  /**
   * @notice Sets or unsets an operator that may manage referral codes. Operators can create or update referral codes on behalf of the system.
   * @dev Only the owner can call this.
   * @param _operator The address of the operator.
   * @param _isAdd True to add, false to remove.
   */
  function setCodeOperator(address _operator, bool _isAdd) external onlyOwner {
    FRStorage storage fs = lockFeeRegistryStorage();
    if (_isAdd) {
      fs.codeOperators.add(_operator);
      emit AddCodeOperator(_operator);
    } else {
      fs.codeOperators.remove(_operator);
      emit RemoveCodeOperator(_operator);
    }
  }

  /**
   * @notice Adds or removes supported chain IDs for referral codes.
   * @param _chains Array of chain IDs.
   * @param _isAdd True to add; false to remove.
   */
  function setSupportedRefCodeInChains(uint256[] memory _chains, bool _isAdd) external onlyOwner {
    FRStorage storage fs = lockFeeRegistryStorage();
    for (uint256 i = 0; i < _chains.length; i++) {
      if (_isAdd) {
        fs.supportedRefInChains.add(_chains[i]);
        emit AddSupportedRefCodeInChain(_chains[i]);
      } else {
        fs.supportedRefInChains.remove(_chains[i]);
        emit RemoveSupportedRefCodeInChain(_chains[i]);
      }
    }
  }

  /**
   * @notice Sets the list of fee beneficiaries and their share percentages.
   * @dev The sum of all `sharePct` must be exactly 10,000.
   * @param _beneficiaries Array of FeeBeneficiary structs to define recipients and their share.
   */
  function setFeeBeneficiaries(FeeBeneficiary[] memory _beneficiaries) external onlyOwner {
    FRStorage storage fs = lockFeeRegistryStorage();
    delete fs.feeBeneficiaries;
    for (uint256 i = 0; i < _beneficiaries.length; i++) {
      fs.feeBeneficiaries.push(_beneficiaries[i]);
    }

    uint64 pctSum = 0;
    for (uint256 i = 0; i < _beneficiaries.length; i++) {
      pctSum += _beneficiaries[i].sharePct;
    }
    if (pctSum != PCT_BASE) {
      revert PctSumDoesntMatchBase();
    }

    emit SetFeeBeneficiaries(_beneficiaries);
  }

  /**
   * @notice Sets default discount and share percentages for referrals.
   * @dev This is a setter for default fee logic. Denominator is 10,000 for both discountPct and sharePct.
   * @param _defaultDiscountPct The new default discount percentage.
   * @param _defaultSharePct The new default share percentage.
   */
  function setDefaultPct(uint32 _defaultDiscountPct, uint32 _defaultSharePct) external onlyOwner {
    _setDefaultPct(lockFeeRegistryStorage(), _defaultDiscountPct, _defaultSharePct);
  }

  /**
   * @notice Internal function to update default percentages with PCT_BASE = 10000.
   * @param _defaultDiscountPct The new default discount percentage.
   * @param _defaultSharePct The new default share percentage.
   */
  function _setDefaultPct(FRStorage storage fs, uint32 _defaultDiscountPct, uint32 _defaultSharePct) internal {
    fs.defaultDiscountPct = _defaultDiscountPct;
    fs.defaultSharePct = _defaultSharePct;
    emit SetDefaultPct(_defaultDiscountPct, _defaultSharePct);
  }

  /**
   * @notice Sets a specific discount/share percentage for a referrer if they hold a custom code.
   * @dev Denominator is 10,000.
   * @param _referrer The address of the referrer.
   * @param _discountPct The discount percentage.
   * @param _sharePct The share percentage.
   */
  function setRefererSpecificPct(address _referrer, uint32 _discountPct, uint32 _sharePct) external onlyOwner {
    FRStorage storage fs = lockFeeRegistryStorage();
    if (_discountPct + _sharePct > PCT_BASE) {
      revert TooBigPct();
    }
    bytes8 code = fs.codeByReferrer[_referrer];
    fs.refererByCode[code].discountPct = _discountPct;
    fs.refererByCode[code].sharePct = _sharePct;
    emit SetRefererSpecificPct(_referrer, code, _discountPct, _sharePct);
  }

  /**
   * @notice Sets the fee for a particular contract-case combination.
   * @param _contract The source contract.
   * @param _case The case identifier.
   * @param _fee The fee amount.
   */
  function setContractCaseFee(address _contract, uint8 _case, uint128 _fee) external onlyOwner {
    FRStorage storage fs = lockFeeRegistryStorage();
    fs.feeByContractCase[_contract][_case] = _fee;
    emit SetContractCaseFee(_contract, _case, _fee);
  }

  /**
   * @notice Takes the fee from the caller and distributes referral shares.
   * @dev Calculates the fee for the given contract and case, applies any referral discount and share percentages,
   *      then transfers the share amount to the referral recipient and accumulates the remaining fee.
   * @param _contract The source contract address.
   * @param _case The fee case identifier.
   * @param _code The referral code.
   * @param _mul Multiplier for fee calculation.
   */
  function takeFee(address _contract, uint8 _case, bytes8 _code, uint256 _mul) external payable nonReentrant {
    FRStorage storage fs = lockFeeRegistryStorage();
    uint256 contractCaseFee = uint256(fs.feeByContractCase[_contract][_case]) * _mul;
    (uint256 discount, uint256 share, uint256 fee) = _calculateFee(fs, _code, contractCaseFee);
    _checkFee(fee);
    fs.accumulatedFee += uint128(fee - share);
    address shareRecipient = fs.refererByCode[_code].recipient;
    (bool isTransferSuccess, bytes memory response) = payable(shareRecipient).call{value: share, gas: 1e4}(new bytes(0));
    if (isTransferSuccess) {
      emit SentFee(fs.refererByCode[_code].owner, _code, shareRecipient, share);
    } else {
      fs.refererByCode[_code].accumulatedFee += uint128(share);
      emit AccumulateFee(fs.refererByCode[_code].owner, _code, shareRecipient, share, response);
    }
    emit TakeFee(_contract, _case, _code, discount, share, fee, msg.value);
  }

  /**
   * @notice Withdraws accumulated fees to the configured fee beneficiaries.
   * @dev Iterates over feeBeneficiaries and transfers fee shares calculated as:
   *      feeShare = (accumulatedFee * beneficiary.sharePct) / PCT_BASE.
   */
  function withdrawAccumulatedFee() external nonReentrant {
    FRStorage storage fs = lockFeeRegistryStorage();
    uint256 len = fs.feeBeneficiaries.length;
    uint256 accFee = fs.accumulatedFee;
    fs.accumulatedFee = 0;
    for (uint256 i = 0; i < len; i++) {
      uint256 feeShare = accFee * fs.feeBeneficiaries[i].sharePct / PCT_BASE;
      (bool success, bytes memory data) = payable(fs.feeBeneficiaries[i].recipient).call{value: feeShare}(new bytes(0));
      if (!success) {
        revert WithdrawAccumulatedFeeFailed(data);
      }
      emit WithdrawFee(fs.feeBeneficiaries[i].recipient, feeShare);
    }
  }

  /**
   * @notice Withdraws the accumulated fee for a specific referral code.
   * @dev Transfers the referral accumulated fee to the referral recipient and resets its accumulated value.
   * @param _code The referral code.
   */
  function withdrawReferralAccumulatedFee(bytes8 _code) external nonReentrant {
    Referrer storage ref = lockFeeRegistryStorage().refererByCode[_code];
    uint256 feeToSend = ref.accumulatedFee;
    ref.accumulatedFee = 0;
    (bool success, bytes memory data) = payable(ref.recipient).call{value: feeToSend}(new bytes(0));
    if (!success) {
      revert WithdrawAccumulatedFeeFailed(data);
    }
    emit WithdrawRefFee(ref.recipient, feeToSend);
  }

  /**
   * @notice Internal function to set a custom referral code.
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _shortCode The short referral code.
   * @return The custom referral code.
   */
  function _setCustomCode(FRStorage storage fs, address _referrer, address _recipient, bytes8 _shortCode, uint32 _discountPct, uint32 _sharePct) internal returns(bytes8) {
    _checkCodeNotZero(_shortCode);

    address prevOwner = fs.refererByCode[_shortCode].owner;
    if (prevOwner != _referrer) {
      _checkNewOwnerIsNotReferrer(fs, _referrer);
      if (fs.codeByReferrer[prevOwner] != bytes8(0)) {
        delete fs.codeByReferrer[prevOwner];
      }
      if (fs.codeByReferrer[_referrer] != _shortCode) {
        fs.codeByReferrer[_referrer] = _shortCode;
      }
    }
    fs.refererByCode[_shortCode].owner = _referrer;
    fs.refererByCode[_shortCode].recipient = _recipient;
    fs.refererByCode[_shortCode].discountPct = _discountPct;
    fs.refererByCode[_shortCode].sharePct = _sharePct;
    return _shortCode;
  }

  /**
   * @notice Internal function to create a custom referral code.
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _shortCode The desired short referral code.
   * @param _fromChain The originating chain ID (if applicable).
   * @return The custom referral code.
   */
  function _createCustomCode(FRStorage storage fs, address _referrer, address _recipient, bytes8 _shortCode, uint256 _fromChain, uint32 _discountPct, uint32 _sharePct) internal returns(bytes8) {
    if (fs.refererByCode[_shortCode].owner != address(0)) {
      revert RefAlreadyCreated();
    }
    emit CreateCode(msg.sender, _referrer, _shortCode, _recipient, _fromChain, _discountPct, _sharePct);
    return _setCustomCode(fs, _referrer, _recipient, _shortCode, _discountPct, _sharePct);
  }

  /**
   * @notice Validates that the provided referral code is non-zero.
   * @dev Reverts if _shortCode equals bytes8(0), ensuring a valid referral code is provided.
   * @param _shortCode The referral code to validate.
   */
  function _checkCodeNotZero(bytes8 _shortCode) internal pure {
    if (_shortCode == bytes8(0)) {
      revert ZeroCode();
    }
  }

  /**
   * @notice Ensures that the sender is an authorized code operator.
   * @dev Checks that msg.sender exists in the set of code operators stored in the registry.
   */
  function _checkSenderIsOperator(FRStorage storage fs) internal view {
    if (!fs.codeOperators.contains(msg.sender)) {
      revert NotOperator();
    }
  }

  /**
   * @notice Creates a custom referral code in current chain and multiple related chains (if _chainIds specified).
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _shortCode The desired referral code.
   * @param _chainIds Array of chain IDs.
   * @param _crossChainFees Array of fees corresponding to each chain.
   * @return shortCode The created referral code.
   * @return totalFee Total spent fee for crosschain operations
   */
  function createCustomCode(address _referrer, address _recipient, bytes8 _shortCode, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable nonReentrant returns(bytes8 shortCode, uint256 totalFee, uint256 returnValue) {
    FRStorage storage fs = lockFeeRegistryStorage();
    _checkSenderIsOperator(fs);
    _createCustomCode(fs, _referrer, _recipient, _shortCode, 0, uint32(0), uint32(0));
    totalFee = _setCrossChainsRef(fs, true, _shortCode, _chainIds, _crossChainFees);
    returnValue = _calcAndReturnFee(totalFee);
    return (_shortCode, totalFee, returnValue);
  }

  /**
   * @notice Creates a referral code in current chain and multiple related chains (if _chainIds specified).
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _chainIds Array of chain IDs.
   * @param _crossChainFees Array of corresponding fees.
   * @return shortCode The generated referral code.
   * @return totalFee Total spent fee for crosschain operations
   */
  function createCode(address _referrer, address _recipient, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable nonReentrant returns(bytes8 shortCode, uint256 totalFee, uint256 returnValue) {
    FRStorage storage fs = lockFeeRegistryStorage();
    _checkSenderIsOperator(fs);
    bytes32 fullCode = keccak256(abi.encodePacked(_referrer, block.timestamp, _referrer.balance));
    shortCode = bytes8(bytes20(fullCode));
    _createCustomCode(fs, _referrer, _recipient, shortCode, 0, uint32(0), uint32(0));
    totalFee = _setCrossChainsRef(fs, true, shortCode, _chainIds, _crossChainFees);
    returnValue = _calcAndReturnFee(totalFee);
  }

  /**
   * @notice Internal function to set cross-chain referral parameters.
   * @dev For each chain ID provided, calculates the sending fee using _getDeBridgeChainNativeFee,
   *      encodes the cross-chain command (create or update) and sends it via _send. Reverts if total fee is invalid.
   * @param fs The FeeRegistry storage pointer.
   * @param _isCreate True if creating a new referral code, false if updating an existing one.
   * @param _shortCode The referral code.
   * @param _toChainIDs Array of destination chain IDs.
   * @param _crossChainFees Array of fees corresponding to each chain.
   * @return totalFee Total fee spent for cross-chain operations.
   */
  function _setCrossChainsRef(FRStorage storage fs, bool _isCreate, bytes8 _shortCode, uint256[] memory _toChainIDs, uint256[] memory _crossChainFees) internal returns(uint256 totalFee) {
    if (_toChainIDs.length != _crossChainFees.length) {
      revert ArrayLengthMismatch();
    }
    LCGStorage storage ls = lockChainGateStorage();
    for (uint256 i = 0; i < _toChainIDs.length; i++) {
      _checkDestinationLockedChain(ls, _toChainIDs[i]);
      uint256 sendFee = _getDeBridgeChainNativeFee(ls, _toChainIDs[i], _crossChainFees[i]);
      bytes memory dstTxCall;
      Referrer storage ref = fs.refererByCode[_shortCode];
      if (_isCreate) {
        dstTxCall = _encodeCrossCreateCustomCodeCommand(ls, ref.owner, ref.recipient, _shortCode, ref.discountPct, ref.sharePct);
      } else {
        dstTxCall = _encodeCrossUpdateCustomCodeCommand(ls, ref.owner, ref.recipient, _shortCode, ref.discountPct, ref.sharePct);
      }
      _send(ls, dstTxCall, _toChainIDs[i], sendFee);
      totalFee += sendFee;
    }
    _checkFee(totalFee);
    emit SetCrossChainsRef(_shortCode, _isCreate, _toChainIDs, _crossChainFees);
  }

  /**
   * @notice Updates cross-chain referral parameters for the given referrer.
   * @param _referrer The referrer address.
   * @param _chainIds Array of new chain IDs.
   * @param _crossChainFees Array of new fees.
   */
  function updateCrossChainsRef(address _referrer, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable nonReentrant returns(uint256 totalFee, uint256 returnValue) {
    FRStorage storage fs = lockFeeRegistryStorage();
    _checkSenderIsOperator(fs);
    if (fs.codeByReferrer[_referrer] == bytes8(0)) {
      revert CodeNotCreated();
    }
    totalFee = _setCrossChainsRef(fs, false, fs.codeByReferrer[_referrer], _chainIds, _crossChainFees);
    returnValue = _calcAndReturnFee(totalFee);
  }

  /**
   * @notice Cross-chain creation of a custom referral code.
   * @param _fromChainId The source chain ID.
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _shortCode The referral code.
   */
  function crossCreateCustomCode(uint256 _fromChainId, address _referrer, address _recipient, bytes8 _shortCode, uint32 _discountPct, uint32 _sharePct) external nonReentrant {
    FRStorage storage fs = lockFeeRegistryStorage();
    LCGStorage storage ls = lockChainGateStorage();
    _checkSource(ls, _fromChainId);
    _onlyCrossChain(ls, _fromChainId);

    _createCustomCode(fs, _referrer, _recipient, _shortCode, _fromChainId, _discountPct, _sharePct);
  }

  /**
   * @notice Cross-chain update of a referral code.
   * @param _fromChainId The source chain ID.
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _shortCode The referral code.
   */
  function crossUpdateCustomCode(uint256 _fromChainId, address _referrer, address _recipient, bytes8 _shortCode, uint32 _discountPct, uint32 _sharePct) external nonReentrant {
    FRStorage storage fs = lockFeeRegistryStorage();
    LCGStorage storage ls = lockChainGateStorage();
    _checkSource(ls, _fromChainId);
    _onlyCrossChain(ls, _fromChainId);

    _setCustomCode(fs, _referrer, _recipient, _shortCode, _discountPct, _sharePct);

    emit UpdateCode(msg.sender, _referrer, _shortCode, _recipient, _fromChainId, _discountPct, _sharePct);
  }

  /**
   * @notice Encodes the cross-chain create custom code command.
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _shortCode The referral code.
   * @return The encoded call data.
   */
  function _encodeCrossCreateCustomCodeCommand(LCGStorage storage ls, address _referrer, address _recipient, bytes8 _shortCode, uint32 _discountPct, uint32 _sharePct) internal view returns (bytes memory) {
    return abi.encodeWithSelector(FeeRegistry.crossCreateCustomCode.selector, _getChainId(ls), _referrer, _recipient, _shortCode, _discountPct, _sharePct);
  }

  /**
   * @notice Encodes the cross-chain update custom code command.
   * @param _referrer The referrer address.
   * @param _recipient The recipient address.
   * @param _shortCode The referral code.
   * @return The encoded call data.
   */
  function _encodeCrossUpdateCustomCodeCommand(LCGStorage storage ls, address _referrer, address _recipient, bytes8 _shortCode, uint32 _discountPct, uint32 _sharePct) internal view returns (bytes memory) {
    return abi.encodeWithSelector(FeeRegistry.crossUpdateCustomCode.selector, _getChainId(ls), _referrer, _recipient, _shortCode, _discountPct, _sharePct);
  }

  /**
   * @notice Internal helper to ensure the sender is the referrer for the given code.
   * @param _code The referral code.
   */
  function _checkSenderIsReferrer(FRStorage storage fs, bytes8 _code) internal view {
    if (fs.codeByReferrer[msg.sender] != _code || _code == bytes8(0)) {
      revert NotReferrer();
    }
  }

  /**
   * @notice Validates that the new owner address is not already associated as a referrer.
   * @dev Reverts if the new owner already has an associated referral code.
   * @param fs The FeeRegistry storage pointer.
   * @param _newReferer The address proposed as the new referrer.
   */
  function _checkNewOwnerIsNotReferrer(FRStorage storage fs, address _newReferer) internal view {
    if (fs.codeByReferrer[_newReferer] != bytes8(0)) {
      revert AlreadyReferrer();
    }
  }

  /**
   * @notice Changes the referrer of a referral code.
   * @param _code The referral code.
   * @param _newReferer The new referrer address.
   */
  function changeCodeReferrer(bytes8 _code, address _newReferer, address _newRecipient, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable nonReentrant returns(uint256 totalFee, uint256 returnValue) {
    FRStorage storage fs = lockFeeRegistryStorage();
    _checkSenderIsReferrer(fs, _code);
    _checkNewOwnerIsNotReferrer(fs, _newReferer);
    delete fs.codeByReferrer[msg.sender];
    fs.refererByCode[_code].owner = _newReferer;
    fs.refererByCode[_code].recipient = _newRecipient;
    fs.codeByReferrer[_newReferer] = _code;
    totalFee = _setCrossChainsRef(fs, false, _code, _chainIds, _crossChainFees);
    returnValue = _calcAndReturnFee(totalFee);
    emit ChangeCode(msg.sender, _newReferer, _code);
  }

  /**
   * @notice Changes the recipient for referral benefits.
   * @param _code The referral code.
   * @param _newRecipient The new recipient address.
   */
  function changeRecipientReferrer(bytes8 _code, address _newRecipient, uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable nonReentrant returns(uint256 totalFee, uint256 returnValue) {
    FRStorage storage fs = lockFeeRegistryStorage();
    _checkSenderIsReferrer(fs, _code);
    fs.refererByCode[_code].recipient = _newRecipient;
    totalFee = _setCrossChainsRef(fs, false, _code, _chainIds, _crossChainFees);
    returnValue = _calcAndReturnFee(totalFee);
    emit ChangeRecipient(msg.sender, _newRecipient, _code);
  }

  /**
   * @notice Returns a list of all authorized referral code operator addresses.
   * @return An array of addresses currently designated as code operators.
   */
  function getCodeOperatorsList() external view returns(address[] memory) {
    return lockFeeRegistryStorage().codeOperators.values();
  }

  /**
   * @notice Checks if a given address is an authorized referral code operator.
   * @param _addr The address to check.
   * @return True if the address is an operator, false otherwise.
   */
  function isCodeOperator(address _addr) external view returns(bool) {
    return lockFeeRegistryStorage().codeOperators.contains(_addr);
  }

  /**
   * @notice Retrieves the list of supported chain IDs for referral codes.
   * @return An array of chain IDs where referral codes are supported.
   */
  function getSupportedRefInChainsList() external view returns(uint256[] memory) {
    return lockFeeRegistryStorage().supportedRefInChains.values();
  }

  /**
   * @notice Determines if a chain ID is supported for referral codes.
   * @param _chainId The chain ID to check.
   * @return True if the chain ID is supported, false otherwise.
   */
  function isSupportedRefInChain(uint256 _chainId) external view returns(bool) {
    return lockFeeRegistryStorage().supportedRefInChains.contains(_chainId);
  }

  /**
   * @notice Retrieves the fee beneficiaries configured in the registry.
   * @return An array of FeeBeneficiary structs.
   */
  function getFeeBeneficiaries() external view returns(FeeBeneficiary[] memory) {
    return lockFeeRegistryStorage().feeBeneficiaries;
  }

  /**
   * @notice Retrieves the effective discount and share percentages for a referral code.
   * @param _code The referral code.
   * @return discountPct The effective discount percentage.
   * @return sharePct The effective share percentage.
   */
  function getCodePct(bytes8 _code) external view returns(uint32 discountPct, uint32 sharePct) {
    return _getCodePct(lockFeeRegistryStorage(), _code);
  }
  /**
   * @notice Internal function to fetch effective percentages for a referral code.
   * @dev If the referral-specific percentage is 0, returns the default discount/share percentages.
   * @param fs The FeeRegistry storage pointer.
   * @param _code The referral code.
   * @return discountPct The effective discount percentage.
   * @return sharePct The effective share percentage.
   */
  function _getCodePct(FRStorage storage fs, bytes8 _code) internal view returns(uint32 discountPct, uint32 sharePct) {
    if (fs.refererByCode[_code].owner == address(0)) {
      return (0, 0);
    }
    discountPct = fs.refererByCode[_code].discountPct > 0 ? fs.refererByCode[_code].discountPct : fs.defaultDiscountPct;
    sharePct = fs.refererByCode[_code].sharePct > 0 ? fs.refererByCode[_code].sharePct : fs.defaultSharePct;
  }

  /**
   * @notice Calculates the fee after applying referral discounts.
   * @param _code The referral code.
   * @param _fee The original fee amount.
   * @return discount The discount amount.
   * @return share The referral share amount.
   * @return fee The final fee after discount.
   */
  function calculateFee(bytes8 _code, uint256 _fee) external view returns(uint256 discount, uint256 share, uint256 fee) {
    return _calculateFee(lockFeeRegistryStorage(), _code, _fee);
  }
  /**
   * @notice Internal function to calculate fee components based on a referral code.
   * @dev Uses effective percentages to compute discount and share.
   * @param fs The FeeRegistry storage pointer.
   * @param _code The referral code.
   * @param _fee The original fee amount.
   * @return discount The discount amount.
   * @return share The referral share amount.
   * @return fee The final fee after discount.
   */
  function _calculateFee(FRStorage storage fs, bytes8 _code, uint256 _fee) internal view returns(uint256 discount, uint256 share, uint256 fee) {
    (uint32 discountPct, uint32 sharePct) = _getCodePct(fs, _code);
    if (discountPct + sharePct > PCT_BASE) {
      revert TooBigPct();
    }
    discount = (_fee * uint256(discountPct)) / uint256(PCT_BASE);
    share = (_fee * uint256(sharePct)) / uint256(PCT_BASE);
    fee = _fee - discount;
  }

  /**
   * @notice Retrieves the fee for a specific contract case.
   * @param _contract The contract address.
   * @param _case The case identifier.
   * @return The fee amount.
   */
  function getContractCaseFee(address _contract, uint8 _case) external view returns(uint256) {
    return lockFeeRegistryStorage().feeByContractCase[_contract][_case];
  }

  /**
   * @notice Retrieves the fee for a contract case after applying referral discounts.
   * @param _contract The contract address.
   * @param _case The case identifier.
   * @param _code The referral code.
   * @return fee The fee amount.
   */
  function getContractCaseFeeForCode(address _contract, uint8 _case, bytes8 _code) external view returns(uint256 fee) {
    FRStorage storage fs = lockFeeRegistryStorage();
    (, , fee) = _calculateFee(fs, _code, fs.feeByContractCase[_contract][_case]);
  }

  /**
   * @notice Retrieves the referrer information for a given referrer address.
   * @param _referrer The referrer address.
   * @return ref The referrer struct.
   */
  function getReferrerByAddress(address _referrer) external view returns(Referrer memory ref) {
    return _getReferrerByAddress(lockFeeRegistryStorage(), _referrer);
  }

  /**
   * @notice Internal function to fetch referrer data using the referrer's address.
   * @dev Uses the mapping codeByReferrer to get the referral code and then returns the associated Referrer struct.
   * @param fs The FeeRegistry storage pointer.
   * @param _referrer The referrer address.
   * @return ref The Referrer struct.
   */
  function _getReferrerByAddress(FRStorage storage fs, address _referrer) internal view returns(Referrer memory ref) {
    return getReferrerByCode(fs.codeByReferrer[_referrer]);
  }

  /**
   * @notice Retrieves the referrer information for a given referral code.
   * @param _code The referral code.
   * @return ref The referrer struct.
   */
  function getReferrerByCode(bytes8 _code) public view returns(Referrer memory ref) {
    return _getReferrerByCode(lockFeeRegistryStorage(), _code);
  }
  /**
   * @notice Internal function to get the referrer information for a referral code.
   * @dev Updates the returned percentages using _getCodePct before returning.
   * @param fs The FeeRegistry storage pointer.
   * @param _code The referral code.
   * @return ref The Referrer struct with effective percentages.
   */
  function _getReferrerByCode(FRStorage storage fs, bytes8 _code) internal view returns(Referrer memory ref) {
    ref = fs.refererByCode[_code];
    (ref.discountPct, ref.sharePct) = _getCodePct(fs, _code);
    return ref;
  }

  /**
   * @notice Retrieves the default share percentage.
   * @return The default share percentage used when a referral code does not specify one.
   */
  function defaultSharePct() external view returns (uint32) {
    return lockFeeRegistryStorage().defaultSharePct;
  }
  /**
   * @notice Retrieves the default discount percentage.
   * @return The default discount percentage used when a referral code does not specify one.
   */
  function defaultDiscountPct() external view returns (uint32) {
    return lockFeeRegistryStorage().defaultDiscountPct;
  }

  /**
   * @notice Retrieves the referrer details for a given referral code.
   * @param _code The referral code.
   * @return The Referrer struct associated with the given referral code.
   */
  function refererByCode(bytes8 _code) external view returns (Referrer memory) {
    return lockFeeRegistryStorage().refererByCode[_code];
  }
  /**
   * @notice Retrieves the referral code associated with a given referrer's address.
   * @param _referrer The address of the referrer.
   * @return The referral code associated with the referrer.
   */
  function codeByReferrer(address _referrer) external view returns (bytes8) {
    return lockFeeRegistryStorage().codeByReferrer[_referrer];
  }
  /**
   * @notice Retrieves the total accumulated fee stored in the registry.
   * @return The total fee amount that has been accumulated.
   */
  function accumulatedFee() external view returns (uint128) {
    return lockFeeRegistryStorage().accumulatedFee;
  }
}
