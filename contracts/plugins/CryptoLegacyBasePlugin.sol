/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../CryptoLegacyOwnable.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/ICryptoLegacy.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../libraries/LibCryptoLegacyPlugins.sol";
import "../interfaces/ICryptoLegacyBuildManager.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CryptoLegacyBasePlugin
 * @notice Provides the core functionalities for the CryptoLegacy system—including fee management, beneficiary configuration, periodic updates, challenge initiation, and token distribution. It ensures automated and secure management of crypto asset inheritance.
*/
contract CryptoLegacyBasePlugin is ICryptoLegacy, CryptoLegacyOwnable, ReentrancyGuard {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using SafeERC20 for IERC20;

  /**
   * @notice Returns the function selectors provided by this plugin.
   * @dev These selectors represent the externally callable base methods for the CryptoLegacy contract.
   * @return sigs An array of function selectors.
   */
  function getSigs() external view returns (bytes4[] memory sigs) {
    sigs = new bytes4[](17);
    sigs[0] = CryptoLegacyBasePlugin(address(this)).getCryptoLegacyVer.selector;
    sigs[1] = CryptoLegacyBasePlugin(address(this)).owner.selector;
    sigs[2] = CryptoLegacyBasePlugin(address(this)).buildManager.selector;
    sigs[3] = CryptoLegacyBasePlugin(address(this)).renounceOwnership.selector;
    sigs[4] = CryptoLegacyBasePlugin(address(this)).transferOwnership.selector;
    sigs[5] = CryptoLegacyBasePlugin(address(this)).isPaused.selector;
    sigs[6] = CryptoLegacyBasePlugin(address(this)).setPause.selector;
    sigs[7] = CryptoLegacyBasePlugin(address(this)).payInitialFee.selector;
    sigs[8] = CryptoLegacyBasePlugin(address(this)).initializeByBuildManager.selector;
    sigs[9] = CryptoLegacyBasePlugin(address(this)).setBeneficiaries.selector;
    sigs[10] = CryptoLegacyBasePlugin(address(this)).update.selector;
    sigs[11] = CryptoLegacyBasePlugin(address(this)).initiateChallenge.selector;
    sigs[12] = CryptoLegacyBasePlugin(address(this)).transferTreasuryTokensToLegacy.selector;
    sigs[13] = CryptoLegacyBasePlugin(address(this)).beneficiaryClaim.selector;
    sigs[14] = CryptoLegacyBasePlugin(address(this)).beneficiarySwitch.selector;
    sigs[15] = CryptoLegacyBasePlugin(address(this)).sendMessagesToBeneficiary.selector;
    sigs[16] = CryptoLegacyBasePlugin(address(this)).isLifetimeActive.selector;
  }

  /**
   * @notice Returns the setup function selectors for this plugin.
   * @dev These selectors are used during the plugin setup process.
   * @return sigs An array of function selectors.
   */
  function getSetupSigs() external view returns (bytes4[] memory sigs) {
    sigs = new bytes4[](5);
    sigs[0] = CryptoLegacyBasePlugin(address(this)).getCryptoLegacyVer.selector;
    sigs[1] = CryptoLegacyBasePlugin(address(this)).owner.selector;
    sigs[2] = CryptoLegacyBasePlugin(address(this)).buildManager.selector;
    sigs[3] = CryptoLegacyBasePlugin(address(this)).isPaused.selector;
    sigs[4] = CryptoLegacyBasePlugin(address(this)).isLifetimeActive.selector;
  }

  event SetBeneficiary(bytes32 indexed beneficiary, uint64 indexed vestingPeriod, uint64 shareBps, uint64 claimDelay);
  event SwitchBeneficiary(bytes32 indexed oldBeneficiary, bytes32 indexed newBeneficiary);
  event ChallengeInitiate(bytes32 indexed beneficiary);
  event BeneficiaryMessage(bytes32 indexed toBeneficiary, bytes32 messageHash, bytes message, uint256 indexed messageType);
  event BeneficiaryMessageCheck(bytes32 indexed toBeneficiary, bytes32 messageHash, bytes message, uint256 indexed messageType);

  /**
   * @notice Returns the unique name for this plugin.
   * @dev The name is used for identification purposes across the CryptoLegacy ecosystem.
   * @return A string representing the plugin name.
   */
  function getPluginName() public pure returns (string memory) {
    return "base";
  }

  /**
   * @notice Returns the version number for this plugin.
   * @dev The version returned is encoded as a uint16.
   * @return The plugin version.
   */
  function getPluginVer() external pure returns (uint16) {
    return uint16(1);
  }
  /**
   * @notice Returns the CryptoLegacy version provided by the plugin.
   * @dev Versioning of the underlying CryptoLegacy system.
   * @return The CryptoLegacy version as a uint16.
   */
  function getCryptoLegacyVer() external pure returns (uint16) {
    return uint16(1);
  }
  constructor() { }

  /**
   * @notice Initializes the contract by the Build Manager with required parameters.
   * @dev Must be called by the Build Manager; reverts if called by any other account or if already initialized.
   *      Sets beneficiary configurations, update fees, timing intervals, and reference code.
   * @param _updateFee The fee for periodic updates.
   * @param _initialFeeToPay The fee to be paid initially; if zero, the fee is marked as paid immediately.
   * @param _beneficiaryHashes Array of beneficiary identifiers (hashes).
   * @param _beneficiaryConfig Array of BeneficiaryConfig structs corresponding to each beneficiary.
   * @param _refCode The reference code used when inviting beneficiaries.
   * @param _updateInterval The interval (in seconds) for update fee recalculation.
   * @param _challengeTimeout The time (in seconds) to wait after challenge initiation before distribution.
   */
  function initializeByBuildManager(
    uint256 _updateFee,
    uint256 _initialFeeToPay,
    bytes32[] memory _beneficiaryHashes,
    BeneficiaryConfig[] memory _beneficiaryConfig,
    bytes8 _refCode,
    uint64 _updateInterval,
    uint64 _challengeTimeout
  ) external {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    if (msg.sender != address(cls.buildManager)) {
      revert ICryptoLegacy.NotBuildManager();
    }
    if (cls.beneficiaries.length() != 0) {
      revert ICryptoLegacy.AlreadyInit();
    }
    _setBeneficiaries(_beneficiaryHashes, _beneficiaryConfig);

    cls.updateFee = uint128(_updateFee);
    cls.updateInterval = _updateInterval;
    cls.challengeTimeout = _challengeTimeout;
    cls.invitedByRefCode = _refCode;

    if (_initialFeeToPay == 0) {
      cls.lastFeePaidAt = uint64(block.timestamp);
    } else {
      cls.initialFeeToPay = uint128(_initialFeeToPay);
      LibCryptoLegacy._setPause(cls, true);
    }

    LibCryptoLegacy._setCryptoLegacyToBeneficiaryRegistry(cls, LibCryptoLegacy._addressToHash(owner()), IBeneficiaryRegistry.EntityType.OWNER, true);
  }

  /**
   * @notice Returns the contract owner.
   * @dev Delegates to LibDiamond.contractOwner().
   * @return The address of the owner.
   */
  function owner() public view returns (address) {
    return LibDiamond.contractOwner();
  }

  /**
   * @notice Checks if the contract is currently paused.
   * @dev Delegates to LibCryptoLegacy._getPause().
   * @return True if paused, false otherwise.
   */
  function isPaused() external view returns (bool) {
    return LibCryptoLegacy._getPause(LibCryptoLegacy.getCryptoLegacyStorage());
  }

  /**
   * @notice Returns the Build Manager contract.
   * @dev Retrieves the buildManager from CryptoLegacy storage.
   * @return The ICryptoLegacyBuildManager instance.
   */
  function buildManager() external view returns(ICryptoLegacyBuildManager) {
    return LibCryptoLegacy.getCryptoLegacyStorage().buildManager;
  }

  /**
   * @notice Renounces ownership of the contract.
   * @dev Only the current owner may call this function.
   * Transfers ownership to the zero address.
   */
  function renounceOwnership() public virtual onlyOwner {
    _transferOwnership(address(0));
  }

  /**
   * @notice Transfers ownership of the contract to a new owner.
   * @dev Only the current owner may call this function.
   * Updates the Beneficiary Registry accordingly.
   * @param newOwner The address of the new owner.
   */
  function transferOwnership(address newOwner) public virtual onlyOwner {
    if (newOwner == address(0)) {
      revert ICryptoLegacy.ZeroAddress();
    }

    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    LibCryptoLegacy._updateOwnerInBeneficiaryRegistry(cls, newOwner);
    _transferOwnership(newOwner);
  }

  /**
   * @notice Pays the initial fee required by the CryptoLegacy system.
   * @dev Reverts if the initial fee has already been paid.
   *      Unpauses the contract, updates fee payment timestamps, and handles fee transfers:
   *        - If a lifetime NFT is active, sets initialFeeToPay to 0 and emits a fee-paid event.
   *        - Otherwise, attempts to pay the fee via the buildManager, falling back to a direct transfer.
   * @param _lockToChainIds Array of chain IDs for fee locking.
   * @param _crossChainFees Array of fees corresponding to each chain ID.
   */
  function payInitialFee(uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable nonReentrant {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    if (cls.lastFeePaidAt != 0) {
      revert ICryptoLegacy.InitialFeeAlreadyPaid();
    }

    LibCryptoLegacy._setPause(cls, false);
    cls.lastFeePaidAt = uint64(block.timestamp);
    cls.lastUpdateAt = uint64(block.timestamp);

    // Check if a lifetime NFT is active; if so, mark the fee as paid.
    if (LibCryptoLegacy._isLifetimeActiveAndUpdate(LibCryptoLegacy.getCryptoLegacyStorage(), owner())) {
      LibCryptoLegacy._checkNoFee();
      cls.initialFeeToPay = 0;
      emit FeePaidByLifetime(cls.invitedByRefCode, true, address(cls.buildManager), cls.lastFeePaidAt);
      return;
    }

    // Attempt to pay the initial fee via the buildManager.
    try cls.buildManager.payInitialFee{value: msg.value}(cls.invitedByRefCode, owner(), _lockToChainIds, _crossChainFees) {
      emit FeePaidByDefault(cls.invitedByRefCode, true, msg.value, address(cls.buildManager), cls.lastFeePaidAt);
    } catch {
      // Check that the fee meets the minimum requirements.
      LibCryptoLegacy._checkFee(uint256(cls.initialFeeToPay));
      payable(address(cls.buildManager)).transfer(msg.value);
      emit FeePaidByTransfer(cls.invitedByRefCode, true, msg.value, address(cls.buildManager), cls.lastFeePaidAt);
    }
    cls.initialFeeToPay = 0;
  }

  /**
   * @notice Sets or updates multiple beneficiaries with their configurations (claimDelay, vestingPeriod, shareBps).
   * @dev Can only be called by the owner. The sum of shareBps across all beneficiaries must be exactly 10,000.
   * @param _beneficiaryHashes Array of beneficiary identifiers.
   * @param _beneficiaryConfig Array of configurations matching `_beneficiaryHashes`.
   */
  function setBeneficiaries(bytes32[] memory _beneficiaryHashes, BeneficiaryConfig[] memory _beneficiaryConfig) external onlyOwner {
    _setBeneficiaries(_beneficiaryHashes, _beneficiaryConfig);
  }

  /**
   * @notice Internal function that updates beneficiary configurations.
   * @dev For each beneficiary, if the shareBps is zero then the beneficiary is removed,
   *      otherwise added to the storage set and its configuration is updated.
   *      The total of shareBps values must equal LibCryptoLegacy.SHARE_BASE (i.e. 10000) using the formula:
   *         sum(b.shareBps) == SHARE_BASE.
   * @param _beneficiaryHashes Array of beneficiary identifiers (hashes).
   * @param _beneficiaryConfig Array of BeneficiaryConfig structs.
   */
  function _setBeneficiaries(bytes32[] memory _beneficiaryHashes, BeneficiaryConfig[] memory _beneficiaryConfig) internal {
    if (_beneficiaryHashes.length != _beneficiaryConfig.length) {
      revert ICryptoLegacy.LengthMismatch();
    }
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    for (uint i = 0; i < _beneficiaryHashes.length; i++) {
      BeneficiaryConfig memory b = _beneficiaryConfig[i];

      // If shareBps is zero then remove beneficiary; otherwise add if missing.
      if (b.shareBps == 0) {
        cls.beneficiaries.remove(_beneficiaryHashes[i]);
        LibCryptoLegacy._setCryptoLegacyToBeneficiaryRegistry(cls, _beneficiaryHashes[i], IBeneficiaryRegistry.EntityType.BENEFICIARY, false);
      } else if (!cls.beneficiaries.contains(_beneficiaryHashes[i])) {
        cls.beneficiaries.add(_beneficiaryHashes[i]);
        LibCryptoLegacy._setCryptoLegacyToBeneficiaryRegistry(cls, _beneficiaryHashes[i], IBeneficiaryRegistry.EntityType.BENEFICIARY, true);
      }
      cls.beneficiaryConfig[_beneficiaryHashes[i]] = b;
      cls.originalBeneficiaryHash[_beneficiaryHashes[i]] = _beneficiaryHashes[i];

      emit SetBeneficiary(_beneficiaryHashes[i], b.vestingPeriod, b.shareBps, b.claimDelay);
    }
    // Sum all shareBps and ensure that the total equals SHARE_BASE (10000)
    uint64 shareSum = 0;
    bytes32[] memory allBeneficiaries = cls.beneficiaries.values();
    for (uint256 i = 0; i < allBeneficiaries.length; i++) {
      shareSum += cls.beneficiaryConfig[allBeneficiaries[i]].shareBps;
    }
    if (shareSum != LibCryptoLegacy.SHARE_BASE) {
      revert ICryptoLegacy.ShareSumDoesntMatchBase();
    }
  }


  /**
   * @notice Periodic update function to keep the contract active, pay any required update fee, and reset distributionStartAt to 0.
   * @dev Must be called by the owner with enough `msg.value` if an update fee is due.
   * @param _lockToChainIds Array of chain IDs for cross-chain fee locking, if any.
   * @param _crossChainFees Array of fees for each chain ID in `_lockToChainIds`.
   */
  function update(uint256[] memory _lockToChainIds, uint256[] memory _crossChainFees) external payable onlyOwner nonReentrant {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    LibCryptoLegacy._takeFee(cls, owner(), address(0), 0, _lockToChainIds, _crossChainFees);

    cls.lastUpdateAt = uint64(block.timestamp);
    cls.distributionStartAt = uint64(0);
    emit Update(msg.value, bytes32(0));
  }

  /**
   * @notice Initiates a challenge if the update interval has passed, starting distribution after `challengeTimeout`.
   * @dev Reverts if the contract is paused or if distributionStartAt is already set.
   *      Also checks that current time > lastUpdateAt + updateInterval.
   *      Sets distributionStartAt to block.timestamp + challengeTimeout.
   */
  function initiateChallenge() external {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    LibCryptoLegacy._checkPause(cls);
    if (cls.distributionStartAt != 0) {
      revert ICryptoLegacy.DistributionStartAlreadySet();
    }
    if (uint64(block.timestamp) < cls.lastUpdateAt + cls.updateInterval) {
      revert ICryptoLegacy.TooEarly();
    }
    bytes32 beneficiary = LibCryptoLegacy._checkAddressIsBeneficiary(cls, msg.sender);
    cls.distributionStartAt = uint64(block.timestamp) + cls.challengeTimeout;
    emit ChallengeInitiate(beneficiary);
  }

  /**
   * @notice Transfers treasury tokens from specified holders to the legacy contract for distribution.
   * @dev Requires that the distribution period is ready and sender is beneficiary.
   * @param _holders Array of addresses holding tokens.
   * @param _tokens Array of token addresses to transfer.
   */
  function transferTreasuryTokensToLegacy(address[] memory _holders, address[] memory _tokens) external nonReentrant {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    LibCryptoLegacy._checkPause(cls);
    LibCryptoLegacy._checkDistributionReadyForBeneficiary(cls);
    LibCryptoLegacy._transferTreasuryTokensToLegacy(cls, _holders, _tokens);
  }

  /**
   * @notice Claims a token for a beneficiary according to vesting schedule.
   * @dev Internal function that calculates vesting progress using:
   *      vestedAmount - claimedAmount, where vestedAmount is computed via LibCryptoLegacy._getVestedAndClaimedAmount.
   *      Transfers the claimable tokens to msg.sender and updates the claimed amounts.
   * @param cls Reference to CryptoLegacy storage.
   * @param td Reference to TokenDistribution for the token.
   * @param _beneficiary The beneficiary identifier.
   * @param _token The token address.
   * @param _startDate The timestamp when vesting starts.
   * @param _endDate The timestamp when vesting ends.
   * @return amountToClaim The token amount that is claimable.
   */
  function _claimTokenWithVesting(CryptoLegacyStorage storage cls, TokenDistribution storage td, bytes32 _beneficiary, address _token, uint64 _startDate, uint64 _endDate) internal returns(uint256 amountToClaim) {
    (BeneficiaryConfig storage bc, BeneficiaryVesting storage bv) = LibCryptoLegacy._getBeneficiaryConfigAndVesting(cls, _beneficiary);

    (uint256 vestedAmount, uint256 claimedAmount, ) = LibCryptoLegacy._getVestedAndClaimedAmount(td, bc, bv, _token, _startDate, _endDate);
    amountToClaim = vestedAmount - claimedAmount;
    bv.tokenAmountClaimed[_token] = vestedAmount;
    td.totalClaimedAmount += amountToClaim;
    IERC20(_token).safeTransfer(msg.sender, amountToClaim);

    emit BeneficiaryClaim(_token, amountToClaim, _beneficiary);
  }

  /**
   * @notice Allows a beneficiary to claim vested tokens for multiple tokens.
   * @dev Checks that beneficiary claims are enabled in this plugin by verifying disabled function flag.
   *      Calls LibCryptoLegacy._takeFee to process any fee payments.
   *      For each token in _tokens, calculates the claimable amount based on vesting dates and transfers tokens.
   * @param _tokens Array of token addresses to claim.
   * @param _ref Optional referral address; if provided, a fraction of msg.value is sent to the referral based on _refShare.
   * @param _refShare The referral share in basis points (denom: 10000) using the formula: (msg.value * _refShare) / 10000.
   */
  function beneficiaryClaim(address[] memory _tokens, address _ref, uint256 _refShare) external payable nonReentrant {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    LibCryptoLegacy._checkPause(cls);
    LibCryptoLegacy._checkDisabledFunc(cls, LibCryptoLegacy.CLAIM_FUNC_FLAG);
    uint256[] memory lockToChainIds = new uint256[](0);
    LibCryptoLegacy._takeFee(cls, owner(), _ref, _refShare, lockToChainIds, lockToChainIds);

    bytes32 beneficiary = LibCryptoLegacy._checkDistributionReadyForBeneficiary(cls);
    BeneficiaryConfig storage bc = cls.beneficiaryConfig[beneficiary];

    (uint64 startDate, uint64 endDate) = LibCryptoLegacy._getStartAndEndDate(cls, bc);

    if (uint64(block.timestamp) < startDate) {
      revert ICryptoLegacy.TooEarly();
    }

    for (uint i = 0; i < _tokens.length; i++) {
      TokenDistribution storage td = LibCryptoLegacy._tokenPrepareToDistribute(cls, _tokens[i]);
      _claimTokenWithVesting(cls, td, beneficiary, _tokens[i], startDate, endDate);
    }
  }

  /**
   * @notice Switches the beneficiary associated with the sender to a new beneficiary.
   * @dev Reverts if the new beneficiary is already registered.
   *      Removes the old beneficiary from storage and registry, then adds the new beneficiary with the same configuration.
   * @param _newBeneficiary The identifier (hash) of the new beneficiary.
   */
  function beneficiarySwitch(bytes32 _newBeneficiary) external {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    bytes32 oldBeneficiary = LibCryptoLegacy._checkAddressIsBeneficiary(cls, msg.sender);
    if (cls.beneficiaries.contains(_newBeneficiary)) {
      revert ICryptoLegacy.AlreadySet();
    }
    cls.beneficiaries.remove(oldBeneficiary);
    cls.beneficiaries.add(_newBeneficiary);

    LibCryptoLegacy._setCryptoLegacyToBeneficiaryRegistry(cls, oldBeneficiary, IBeneficiaryRegistry.EntityType.BENEFICIARY, false);
    LibCryptoLegacy._setCryptoLegacyToBeneficiaryRegistry(cls, _newBeneficiary, IBeneficiaryRegistry.EntityType.BENEFICIARY, true);

    cls.beneficiaryConfig[_newBeneficiary] = cls.beneficiaryConfig[oldBeneficiary];
    delete cls.beneficiaryConfig[oldBeneficiary];

    cls.originalBeneficiaryHash[_newBeneficiary] = cls.originalBeneficiaryHash[oldBeneficiary];
    delete cls.originalBeneficiaryHash[oldBeneficiary];

    emit SwitchBeneficiary(oldBeneficiary, _newBeneficiary);
  }

  /**
   * @notice Sends messages to a list of beneficiary hashes for off-chain communication or indexing and records the block number when the message was sent.
   * @dev For each beneficiary, emits BeneficiaryMessage and BeneficiaryMessageCheck events, must be called by the owner.
   * @param _beneficiaryList Array of beneficiary identifiers.
   * @param _messageHashList Array of hashed messages for reference.
   * @param _messageList Raw messages (in bytes).
   * @param _messageCheckList Extra checks or metadata (in bytes).
   * @param _messageType A numeric type to classify messages.
   */
  function sendMessagesToBeneficiary(
    bytes32[] memory _beneficiaryList,
    bytes32[] memory _messageHashList,
    bytes[] memory _messageList,
    bytes[] memory _messageCheckList,
    uint256 _messageType
  ) external onlyOwner {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

    for (uint256 i = 0; i < _beneficiaryList.length; i++) {
      emit BeneficiaryMessage(_beneficiaryList[i], _messageHashList[i], _messageList[i], _messageType);
      emit BeneficiaryMessageCheck(_beneficiaryList[i], _messageHashList[i], _messageCheckList[i], _messageType);
      cls.beneficiaryMessagesGotByBlockNumber[_beneficiaryList[i]].push(uint64(block.number));
    }
  }

  /**
   * @notice Checks if the lifetime NFT is active for the contract owner.
   * @dev Queries the Build Manager to determine if the lifetime NFT is locked.
   * @return isNftLocked True if the lifetime NFT is active (locked), false otherwise.
   */
  function isLifetimeActive() public view returns(bool isNftLocked) {
    CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    return cls.buildManager.isLifetimeNftLocked(owner());
  }
}
