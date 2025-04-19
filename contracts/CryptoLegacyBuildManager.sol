/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./CryptoLegacy.sol";
import "./interfaces/IFeeRegistry.sol";
import "./interfaces/ILifetimeNft.sol";
import "./interfaces/IPluginsRegistry.sol";
import "./plugins/CryptoLegacyBasePlugin.sol";
import "./interfaces/ICryptoLegacyFactory.sol";
import "./interfaces/IBeneficiaryRegistry.sol";
import "./interfaces/ICryptoLegacyBuildManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CryptoLegacyBuildManager is ICryptoLegacyBuildManager, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @notice The fee registry contract used to determine and collect fees.
  IFeeRegistry public feeRegistry;
  /// @notice The plugins registry contract managing plugin registration.
  IPluginsRegistry public pluginsRegistry;
  /// @notice The beneficiary registry contract that records beneficiary-related data.
  IBeneficiaryRegistry public beneficiaryRegistry;
  /// @notice The Lifetime NFT contract used to award lifetime NFTs.
  ILifetimeNft public lifetimeNft;
  /// @notice The factory contract for deploying new CryptoLegacy contracts.
  ICryptoLegacyFactory public factory;
  /// @notice An external address for lens-type data (if applicable).
  address public externalLens;
  /// @notice The minimum supply value required for mass minting of lifetime NFTs.
  uint256 public minMassMintSupply = 1000;
  /// @notice Constant representing the build fee registry case.
  uint8 constant public REGISTRY_BUILD_CASE = 1;
  /// @notice Constant representing the update fee registry case.
  uint8 constant public REGISTRY_UPDATE_CASE = 2;
  /// @notice Constant representing the lifetime fee registry case.
  uint8 constant public REGISTRY_LIFETIME_CASE = 3;
  /// @notice Tracks whether a CryptoLegacy contract was built.
  mapping(address => bool) internal cryptoLegacyBuilt;

  receive() external payable {}

  /**
   * @notice Constructs a new CryptoLegacyBuildManager instance.
   * @dev Sets the registry contracts, factory, lifetime NFT contract, and transfers ownership to _owner.
   * @param _owner The address to be set as the owner.
   * @param _feeRegistry The fee registry contract.
   * @param _pluginsRegistry The plugins registry contract.
   * @param _beneficiaryRegistry The beneficiary registry contract.
   * @param _lifetimeNft The lifetime NFT contract.
   * @param _factory The factory contract for deploying new CryptoLegacy contracts.
   */
  constructor(
    address _owner,
    IFeeRegistry _feeRegistry,
    IPluginsRegistry _pluginsRegistry,
    IBeneficiaryRegistry _beneficiaryRegistry,
    ILifetimeNft _lifetimeNft,
    ICryptoLegacyFactory _factory
  ) Ownable() {
    _setRegistries(_feeRegistry, _pluginsRegistry, _beneficiaryRegistry);
    _setFactory(_factory);
    lifetimeNft = _lifetimeNft;
    _transferOwnership(_owner);
  }

  /**
   * @notice Sets the registry contracts.
   * @param _feeRegistry Fee registry contract.
   * @param _pluginsRegistry Plugins registry contract.
   * @param _beneficiaryRegistry Beneficiary registry contract.
   */
  function setRegistries(IFeeRegistry _feeRegistry, IPluginsRegistry _pluginsRegistry, IBeneficiaryRegistry _beneficiaryRegistry) external onlyOwner {
    _setRegistries(_feeRegistry, _pluginsRegistry, _beneficiaryRegistry);
  }
  /**
   * @notice Internal function to update the registry contracts.
   * @dev Updates state variables and emits a SetRegistries event.
   * @param _feeRegistry The fee registry contract.
   * @param _pluginsRegistry The plugins registry contract.
   * @param _beneficiaryRegistry The beneficiary registry contract.
   */
  function _setRegistries(IFeeRegistry _feeRegistry, IPluginsRegistry _pluginsRegistry, IBeneficiaryRegistry _beneficiaryRegistry) internal {
    feeRegistry = _feeRegistry;
    pluginsRegistry = _pluginsRegistry;
    beneficiaryRegistry = _beneficiaryRegistry;
    emit SetRegistries(address(_feeRegistry), address(_pluginsRegistry), address(_beneficiaryRegistry));
  }

  /**
   * @notice Sets the factory contract.
   * @param _factory The new factory contract.
   */
  function setFactory(ICryptoLegacyFactory _factory) external onlyOwner {
    _setFactory(_factory);
  }

  /**
   * @notice Internal function to update the factory contract.
   * @dev Updates the factory state variable and emits a SetFactory event.
   * @param _factory The new factory contract.
   */
  function _setFactory(ICryptoLegacyFactory _factory) internal {
    factory = _factory;
    emit SetFactory(address(_factory));
  }

  /**
   * @notice Sets the minimum supply limit for lifetime NFT mass minting.
   * @dev This is a setter for `minMassMintSupply` storage variable.
   *      This variable is used to block mass minting until the NFT supply is at least the configured amount.
   * @param _newVal The new minimum supply limit for mass minting.
   */
  function setSupplyLimit(uint256 _newVal) external onlyOwner {
    minMassMintSupply = _newVal;
    emit SetSupplyLimit(_newVal);
  }

  /**
   * @notice Sets an external lens address for off-chain data queries or explorer integration.
   * @dev This is a setter for `externalLens` used by front-ends to retrieve data from a separate lens contract.
   * @param _externalLens The address of the new external lens contract.
   */
  function setExternalLens(address _externalLens) external onlyOwner {
    externalLens = _externalLens;
    emit SetExternalLens(_externalLens);
  }

  /**
   * @notice Withdraws a portion of collected fees from this contract.
   * @dev Only the owner can call. This is a direct transfer of `_amount` to `_recipient`.
   * @param _recipient The address to receive the withdrawn fees.
   * @param _amount The amount of fees to transfer, in wei.
   */
  function withdrawFee(address payable _recipient, uint256 _amount) external onlyOwner {
    _recipient.transfer(_amount);
    emit WithdrawFee(_recipient, _amount);
  }

  /**
   * @notice Pays the fee or buy nft and lock it.
   * @dev The function calls `_payFee` with default case of REGISTRY_UPDATE_CASE.
   *      Condition checks ensure the correct fee is passed.
   * @param _code The referral code to use or register.
   * @param _toHolder The referral beneficiary address.
   * @param _mul A multiplier for repeated fee payments.
   * @param _lockToChainIds An array of chain IDs for optional cross-chain locking.
   * @param _crossChainFees An array of fees corresponding to each chain ID, using the same index.
   */
  function payFee(bytes8 _code, address _toHolder, uint256 _mul, uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable {
    _payFee(_code, _toHolder, REGISTRY_UPDATE_CASE, _mul, 0, _lockToChainIds, _crossChainFees);
  }

  /**
  * @notice Internal function to calculate and take fee based on provided parameters.
   * @dev Determines the fee by comparing update fee and lifetime fee. If lifetime fee is applicable and msg.value covers it,
   *      uses REGISTRY_LIFETIME_CASE. Verifies sufficient fee via _checkFee and then calls feeRegistry.takeFee.
   *      If the lifetime fee case applies, calls _mintAndLockLifetimeNft to mint and lock a lifetime NFT.
   * @param _code The referral code.
   * @param _toHolder The address to receive referral benefits (or the NFT in lifetime case).
   * @param _feeCase The fee case (REGISTRY_UPDATE_CASE or REGISTRY_LIFETIME_CASE).
   * @param _mul Multiplier for fee calculation.
   * @param _subValue A value to subtract from msg.value (if applicable).
   * @param _chainIds Array of chain IDs for locking tokens.
   * @param _crossChainFees Array of corresponding cross-chain fees.
   */
  function _payFee(bytes8 _code, address _toHolder, uint8 _feeCase, uint256 _mul, uint256 _subValue, uint256[] memory _chainIds, uint256[] memory _crossChainFees) internal {
    uint256 curValue = msg.value - _subValue;
    uint256 feeToTake = feeRegistry.getContractCaseFeeForCode(address(this), _feeCase, _code);
    uint256 lifetimeFee = feeRegistry.getContractCaseFeeForCode(address(this), REGISTRY_LIFETIME_CASE, _code);
    if (lifetimeFee > 0 && curValue >= lifetimeFee) {
      _feeCase = REGISTRY_LIFETIME_CASE;
      _mul = 1;
      feeToTake = lifetimeFee;
    }
    _checkFee(curValue, feeToTake);
    feeRegistry.takeFee{value: feeToTake}(address(this), _feeCase, _code, _mul);
    if (_feeCase == REGISTRY_LIFETIME_CASE) {
      _mintAndLockLifetimeNft(_toHolder, _chainIds, _crossChainFees, curValue - feeToTake);
    }
  }

  /**
   * @notice Verifies that the provided fee value is sufficient.
   * @dev Reverts with IncorrectFee if _value is less than _fee.
   * @param _value The fee value received.
   * @param _fee The expected fee amount.
   */
  function _checkFee(uint256 _value, uint256 _fee) internal pure {
    if (_value < _fee) {
      revert IncorrectFee(_fee);
    }
  }

  /**
   * @notice Internal function to mint a lifetime NFT and lock it.
   * @param _tokenOwner The owner of the NFT.
   * @param _chainIds Array of chain IDs.
   * @param _crossChainFees Array of fees corresponding to each chain.
   * @param _valueToSend The amount of value to send with the transaction.
   */
  function _mintAndLockLifetimeNft(address _tokenOwner, uint256[] memory _chainIds, uint256[] memory _crossChainFees, uint256 _valueToSend) internal {
    uint256 tokenId = lifetimeNft.mint(address(this));
    lifetimeNft.approve(address(feeRegistry), tokenId);
    ILockChainGate(address(feeRegistry)).lockLifetimeNft{value: _valueToSend}(tokenId, _tokenOwner, _chainIds, _crossChainFees);
  }

  /**
   * @notice Pays the initial fee for building a CryptoLegacy contract, also can be used to buy and lock NFT, if enough msg.value passed.
   * @param _code The referral code.
   * @param _toHolder The address that will receive locked NFT.
   * @param _lockToChainIds Array of chain IDs for cross-chain locking.
   * @param _crossChainFees Corresponding fees for each chain.
   */
  function payInitialFee(bytes8 _code, address _toHolder, uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) public payable {
    _payFee(_code, _toHolder, REGISTRY_BUILD_CASE, 1, 0, _lockToChainIds, _crossChainFees);
  }

  /**
   * @notice Pays for multiple lifetime NFTs at once (mass minting), used when total supply is above a given threshold.
   * @dev Reverts if current NFT totalSupply is below `minMassMintSupply`.
   *      Splits `msg.value` evenly by `lifetimeFee` to compute how many NFTs can be minted.
   * @param _code The referral code.
   * @param _lifetimeNftMints An array of `LifetimeNftMint` specifying how many NFTs each recipient should get.
   */
  function payForMultipleLifetimeNft(bytes8 _code, LifetimeNftMint[] memory _lifetimeNftMints) public payable {
    if (lifetimeNft.totalSupply() < minMassMintSupply) {
      revert BellowMinimumSupply(minMassMintSupply);
    }

    uint256 lifetimeFee = feeRegistry.getContractCaseFeeForCode(address(this), REGISTRY_LIFETIME_CASE, _code);
    _checkFee(msg.value, lifetimeFee);
    uint256 totalAmount = msg.value / lifetimeFee;
    feeRegistry.takeFee{value: msg.value}(address(this), REGISTRY_LIFETIME_CASE, _code, totalAmount);

    uint256 mintAmount = 0;
    for (uint256 i = 0; i < _lifetimeNftMints.length; i++) {
      LifetimeNftMint memory nftMint = _lifetimeNftMints[i];
      for (uint256 j = 0; j < nftMint.amount; j++) {
        uint256 tokenId = lifetimeNft.mint(nftMint.toHolder);
        emit PaidForMint(msg.sender, tokenId, nftMint.toHolder);
        mintAmount += 1;
      }
    }
    if (mintAmount != totalAmount) {
      revert IncorrectFee(mintAmount * lifetimeFee);
    }
    emit PaidForMultipleNft(msg.sender, _code, msg.value, totalAmount);
  }


  /**
   * @notice Creates a custom referral code in the current chain, optionally locking it cross-chain if `_chainIds` is non-empty.
   * @dev If `_chainIds` is non-empty, user must supply the required native fees in `_crossChainFees`.
   * @param _customRefCode The desired custom referral code (non-zero).
   * @param _recipient The address receiving the referral benefits.
   * @param _chainIds Destination chain IDs for cross-chain usage.
   * @param _crossChainFees Fees for each respective chain in `_chainIds`.
   * @return refCode The created or assigned code.
   * @return crossChainFee The total cross-chain fee used.
   */
  function createCustomRef(bytes8 _customRefCode, address _recipient, uint256[] memory _chainIds, uint256[] memory _crossChainFees) public payable returns(bytes8 refCode, uint256 crossChainFee) {
    uint256 valueToSend = calculateCrossChainCreateRefFee(_chainIds, _crossChainFees);
    _checkFee(msg.value, valueToSend);
    (refCode, crossChainFee) = feeRegistry.createCustomCode{value: valueToSend}(msg.sender, _recipient, _customRefCode, _chainIds, _crossChainFees);
    emit CreateCustomRef(msg.sender, refCode, _recipient, _chainIds);
  }

  /**
   * @notice Creates a referral code in the current chain, optionally locking it cross-chain if `_chainIds` is non-empty.
   * @dev If `_chainIds` is non-empty, user must supply the required native fees in `_crossChainFees`.
   * @param _recipient The address holding referral benefits.
   * @param _chainIds Destination chain IDs for cross-chain usage.
   * @param _crossChainFees Fees for each respective chain.
   * @return refCode The newly created short referral code.
   * @return crossChainFee The total cross-chain fee used.
   */
  function createRef(address _recipient, uint256[] memory _chainIds, uint256[] memory _crossChainFees) public payable returns(bytes8 refCode, uint256 crossChainFee) {
    uint256 valueToSend = calculateCrossChainCreateRefFee(_chainIds, _crossChainFees);
    _checkFee(msg.value, valueToSend);
    (refCode, crossChainFee) = feeRegistry.createCode{value: valueToSend}(msg.sender, _recipient, _chainIds, _crossChainFees);
    emit CreateRef(msg.sender, refCode, _recipient, _chainIds);
  }

  /**
   * @notice Updates cross-chain referral parameters for the caller's existing referral code.
   * @dev Similar cross-chain fee logic as createRef.
   * @param _chainIds Destination chain IDs to update.
   * @param _crossChainFees Corresponding fees for each chain ID.
   * @return crossChainFee The total cross-chain fee used.
   */
  function updateCrossChainsRef(uint256[] memory _chainIds, uint256[] memory _crossChainFees) external payable returns(uint256 crossChainFee) {
    uint256 valueToSend = calculateCrossChainCreateRefFee(_chainIds, _crossChainFees);
    _checkFee(msg.value, valueToSend);
    crossChainFee = feeRegistry.updateCrossChainsRef{value: valueToSend}(msg.sender, _chainIds, _crossChainFees);
    emit SetCrossChainsRef(msg.sender, _chainIds);
  }

  /**
   * @notice Internal helper to create a referral code and pay build fees.
   * @dev If a referral recipient is provided, creates a referral code (custom or generated) and deducts its fee.
   *      Then retrieves and pays the build fee via _getAndPayBuildFee.
   * @param _buildArgs The build arguments for CryptoLegacy creation.
   * @param _refArgs The referral arguments.
   * @return initialFeeToPay The fee for initial deployment.
   * @return updateFee The fee for subsequent updates.
   */
  function _createRefAndPayForBuild(BuildArgs memory _buildArgs, RefArgs memory _refArgs) internal returns(uint256 initialFeeToPay, uint256 updateFee) {
    uint256 subValue;
    if (_refArgs.createRefRecipient != address(0)) {
      if (_refArgs.createRefCustomCode == bytes8(0)) {
        (, subValue) = createRef(_refArgs.createRefRecipient, _refArgs.createRefChains, _refArgs.crossChainFees);
      } else {
        (, subValue) = createCustomRef(_refArgs.createRefCustomCode, _refArgs.createRefRecipient, _refArgs.createRefChains, _refArgs.crossChainFees);
      }
    }
    (initialFeeToPay, updateFee) = _getAndPayBuildFee(_buildArgs.invitedByRefCode, subValue, _refArgs.createRefChains, _refArgs.crossChainFees);
  }


  /**
   * @notice Creates a new CryptoLegacy contract instance.
   * @dev Calculates fees via referral logic, validates build parameters, deploys the new contract using the factory, initializes it with the provided parameters, records it in the beneficiary registry, and emits a Build event.
   * @param _buildArgs The build arguments that include referral code, plugin list, beneficiary hashes, beneficiary configurations, update interval, and challenge timeout.
   * @param _refArgs The referral arguments for code creation.
   * @param _create2Args The CREATE2 deployment arguments.
   * @return The payable address of the newly created CryptoLegacy contract.
   */
  function buildCryptoLegacy(
    BuildArgs memory _buildArgs,
    RefArgs memory _refArgs,
    ICryptoLegacyFactory.Create2Args memory _create2Args
  ) public payable returns(address payable) {
    (uint256 initialFeeToPay, uint256 updateFee) = _createRefAndPayForBuild(_buildArgs, _refArgs);
    _checkBuildArgs(_buildArgs);
    address payable cl = factory.createCryptoLegacy(msg.sender, _buildArgs.plugins, _create2Args);
    cryptoLegacyBuilt[cl] = true;
    CryptoLegacyBasePlugin(cl).initializeByBuildManager(
      updateFee,
      initialFeeToPay,
      _buildArgs.beneficiaryHashes,
      _buildArgs.beneficiaryConfig,
      _buildArgs.invitedByRefCode,
      _buildArgs.updateInterval,
      _buildArgs.challengeTimeout
    );
    emit Build(msg.sender, cl, _buildArgs.plugins, _buildArgs.beneficiaryHashes, _buildArgs.beneficiaryConfig, initialFeeToPay == 0, _buildArgs.updateInterval, _buildArgs.challengeTimeout);
    return payable(cl);
  }

  /**
   * @notice Checks if `_buildArgs.updateInterval` and `_buildArgs.challengeTimeout` meet the required constants.
   * @param _buildArgs The build arguments including interval config.
   */
  function _checkBuildArgs(BuildArgs memory _buildArgs) internal virtual {
    if (_buildArgs.updateInterval != 180 days || _buildArgs.challengeTimeout != 90 days) {
      revert NotValidTimeout();
    }
  }

  /**
   * @notice Retrieves and pays the build fee using the referral code.
   * @dev If msg.value minus any subtracted value is positive, calls _payFee.
   * Otherwise, retrieves the initial fee from feeRegistry.
   * If a lifetime NFT is locked for the caller, sets the initial fee to zero.
   * Also retrieves the update fee.
   * @param _invitedByRefCode The referral code.
   * @param _subValue The amount to subtract from msg.value.
   * @param _chainIds Array of chain IDs for fee locking.
   * @param _crossChainFees Array of corresponding cross-chain fees.
   * @return initialFeeToPay The fee for initial deployment.
   * @return updateFee The fee for future updates.
   */
  function _getAndPayBuildFee(bytes8 _invitedByRefCode, uint256 _subValue, uint256[] memory _chainIds, uint256[] memory _crossChainFees) internal returns(uint256 initialFeeToPay, uint256 updateFee) {
    if (msg.value - _subValue > 0) {
      _payFee(_invitedByRefCode, msg.sender, REGISTRY_BUILD_CASE, 1, _subValue, _chainIds, _crossChainFees);
    } else {
      initialFeeToPay = feeRegistry.getContractCaseFeeForCode(address(this), REGISTRY_BUILD_CASE, _invitedByRefCode);
    }
    // check for lock
    if (isLifetimeNftLockedAndUpdate(msg.sender)) {
      initialFeeToPay = 0;
    }
    updateFee = feeRegistry.getContractCaseFeeForCode(address(this), REGISTRY_UPDATE_CASE, _invitedByRefCode);
  }

  /**
   * @notice Returns the update fee for a given referral code.
   * @dev Simple wrapper around feeRegistry.getContractCaseFeeForCode.
   * @param _refCode The referral code used by the user.
   * @return The update fee for that code in wei.
   */
  function getUpdateFee(bytes8 _refCode) external view returns(uint256) {
    return feeRegistry.getContractCaseFeeForCode(address(this), REGISTRY_UPDATE_CASE, _refCode);
  }

  /**
   * @notice Calculate the initial build and update fee for provided ref code.
   * @param _invitedByRefCode The referral code, if any.
   * @return initialFeeToPay The initial build fee.
   * @return updateFee The fee for future updates.
   */
  function getAndPayBuildFee(bytes8 _invitedByRefCode) external payable returns(uint256 initialFeeToPay, uint256 updateFee) {
    uint256[] memory chainIds = new uint256[](0);
    return _getAndPayBuildFee(_invitedByRefCode, 0, chainIds, chainIds);
  }

  /**
   * @notice Calculates the total native fee required for cross-chain referral creation.
   * @dev Iterates through `_chainIds` and sums or fetches the fee from the lockChainGate.
   * @param _chainIds Destination chain IDs.
   * @param _crossChainFees Pre-supplied or zeroed fees array.
   * @return totalFee The total computed native fee.
   */
  function calculateCrossChainCreateRefFee(uint256[] memory _chainIds, uint256[] memory _crossChainFees) public view returns(uint256 totalFee) {
    bool toCallRegistry = _crossChainFees.length == 0;
    for (uint256 i = 0; i < _crossChainFees.length; i++) {
      if (_crossChainFees[i] == 0) {
        toCallRegistry = true;
        break;
      }
      totalFee += _crossChainFees[i];
    }
    if (toCallRegistry) {
      return ILockChainGate(address(feeRegistry)).calculateCrossChainCreateRefNativeFee(_chainIds, _crossChainFees);
    } else {
      return totalFee;
    }
  }

  /**
   * @notice Returns the address of the factory contract.
   * @return The factory contract address.
   */
  function getFactoryAddress() external override view returns(address) {
    return address(factory);
  }

  /**
   * @notice Checks whether a lifetime NFT is locked for the given owner.
   * @param _owner The address of the owner.
   * @return True if the lifetime NFT is locked, false otherwise.
   */
  function isLifetimeNftLocked(address _owner) public view returns(bool) {
    return ILockChainGate(address(feeRegistry)).isNftLocked(_owner);
  }

  /**
   * @notice Checks whether a lifetime NFT is locked for a given owner and updates the state if necessary.
   * @param _owner The address of the owner.
   * @return True if the lifetime NFT is locked, false otherwise.
   */
  function isLifetimeNftLockedAndUpdate(address _owner) public returns(bool) {
    return ILockChainGate(address(feeRegistry)).isNftLockedAndUpdate(_owner);
  }

  /**
   * @notice Checks whether a given plugin is registered.
   * @param _plugin The plugin address.
   * @return True if registered, false otherwise.
   */
  function isPluginRegistered(address _plugin) external view returns(bool) {
    return pluginsRegistry.isPluginRegistered(_plugin);
  }

  /**
   * @notice Verifies if a specific CryptoLegacy contract was built by this manager.
   * @dev Accessor for the `cryptoLegacyBuilt` mapping.
   * @param _cryptoLegacy The CryptoLegacy contract address.
   * @return True if the contract was built, false otherwise.
   */
  function isCryptoLegacyBuilt(address _cryptoLegacy) external view returns(bool) {
    return cryptoLegacyBuilt[_cryptoLegacy];
  }
}
