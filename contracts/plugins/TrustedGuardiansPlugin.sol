/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../libraries/LibDiamond.sol";
import "../interfaces/ICryptoLegacy.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";
import "../libraries/LibSafeMinimalMultisig.sol";
import "../interfaces/ITrustedGuardiansPlugin.sol";
import "../libraries/LibTrustedGuardiansPlugin.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TrustedGuardiansPlugin is ICryptoLegacyPlugin, ITrustedGuardiansPlugin, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @notice Returns the function selectors provided by this plugin.
     * @dev These selectors identify the externally callable functions of the TrustedGuardiansPlugin.
     * @return sigs An array of function selectors.
     */
    function getSigs() external view returns (bytes4[] memory sigs) {
        sigs = new bytes4[](8);
        sigs[0] = TrustedGuardiansPlugin(address(this)).initializeGuardians.selector;
        sigs[1] = TrustedGuardiansPlugin(address(this)).setGuardians.selector;
        sigs[2] = TrustedGuardiansPlugin(address(this)).setGuardiansConfig.selector;
        sigs[3] = TrustedGuardiansPlugin(address(this)).guardiansVoteForDistribution.selector;
        sigs[4] = TrustedGuardiansPlugin(address(this)).guardiansTransferTreasuryTokensToLegacy.selector;
        sigs[5] = TrustedGuardiansPlugin(address(this)).resetGuardianVoting.selector;
        sigs[6] = TrustedGuardiansPlugin(address(this)).getGuardiansData.selector;
        sigs[7] = TrustedGuardiansPlugin(address(this)).isGuardiansInitialized.selector;
    }

    /**
     * @notice Returns the setup function selectors for this plugin.
     * @dev These selectors are used during the plugin setup process.
     * @return sigs An array of function selectors.
     */
    function getSetupSigs() external view returns (bytes4[] memory sigs) {
        sigs = new bytes4[](1);
        sigs[0] = TrustedGuardiansPlugin(address(this)).isGuardiansInitialized.selector;
    }

    /**
     * @notice Returns the unique name for this plugin.
     * @dev The name is used for identification purposes across the CryptoLegacy ecosystem.
     * @return A string representing the plugin name.
     */
    function getPluginName() external pure returns (string memory) {
        return "trusted_guardians";
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
     * @notice Modifier that restricts function access to the owner.
     * @dev Invokes LibCryptoLegacy._checkOwner() to verify that msg.sender is the contract owner.
     */
    modifier onlyOwner() {
        LibCryptoLegacy._checkOwner();
        _;
    }

    /**
     * @notice Internal function that checks whether a given guardian (derived from msg.sender) has already voted.
     * @dev Iterates over the guardiansVoted array and removes any votes that are no longer valid because the vote corresponds to an address that is not a guardian.
     * @param cls The CryptoLegacy storage reference.
     * @param _pluginStorage The plugin-specific storage for trusted guardians.
     * @param _hash The hash identifier of the guardian (caller) to check.
     * @return isVoted True if the guardian has already voted, false otherwise.
     */
    function _isGuardianVoted(ICryptoLegacy.CryptoLegacyStorage storage cls, ITrustedGuardiansPlugin.PluginStorage storage _pluginStorage, bytes32 _hash) internal returns(bool isVoted) {
        bool isInitialized = _pluginStorage.guardians.length() != 0;
        uint256 i = 0;
        while(i < _pluginStorage.guardiansVoted.length) {
            bytes32 voted = _pluginStorage.guardiansVoted[i];
            if (!isInitialized && !cls.beneficiaries.contains(voted)) {
                uint256 lastIndex = _pluginStorage.guardiansVoted.length - 1;
                if (i != lastIndex) {
                    _pluginStorage.guardiansVoted[i] = _pluginStorage.guardiansVoted[lastIndex];
                }
                _pluginStorage.guardiansVoted.pop();
                continue;
            }
            if (voted == _hash) {
                isVoted = true;
            }
            i++;
        }
        return isVoted;
    }

    /**
     * @notice Checks that the caller is a guardian who has not yet voted.
     * @dev Calls _checkGuardian to ensure the caller is a guardian and then verifies that the caller's vote is not present.
     * @return cls Reference to the CryptoLegacy storage.
     * @return pluginStorage Reference to the plugin-specific storage.
     * @return hash The hash of msg.sender.
     */
    function _checkGuardian() internal view returns(ICryptoLegacy.CryptoLegacyStorage storage cls, ITrustedGuardiansPlugin.PluginStorage storage pluginStorage, bytes32 hash) {
        cls = LibCryptoLegacy.getCryptoLegacyStorage();
        pluginStorage = LibTrustedGuardiansPlugin.getPluginStorage();
        hash = LibCryptoLegacy._addressToHash(msg.sender);
        if (!_getGuardians(cls, pluginStorage).contains(hash)) {
            revert NotGuardian();
        }
    }

    /**
     * @notice Checks that the caller is a guardian who has not yet voted.
     * @dev Calls _checkGuardian to ensure the caller is a guardian and then verifies that the caller's vote is not present.
     * @return cls Reference to the CryptoLegacy storage.
     * @return pluginStorage Reference to the plugin-specific storage.
     * @return hash The hash of msg.sender.
     */
    function _checkGuardianNotVoted() internal returns(ICryptoLegacy.CryptoLegacyStorage storage cls, ITrustedGuardiansPlugin.PluginStorage storage pluginStorage, bytes32 hash) {
        (cls, pluginStorage, hash) = _checkGuardian();
        if (_isGuardianVoted(cls, pluginStorage, hash)) {
            revert GuardianAlreadyVoted();
        }
    }

    /**
     * @notice Returns the current set of guardians.
     * @dev If the plugin storage has no explicit guardians set, returns the beneficiaries from the core storage.
     * @param _cls The CryptoLegacy storage reference.
     * @param _pluginStorage The plugin-specific storage reference.
     * @return The EnumerableSet of guardian identifiers.
     */
    function _getGuardians(ICryptoLegacy.CryptoLegacyStorage storage _cls, ITrustedGuardiansPlugin.PluginStorage storage _pluginStorage) internal view returns(EnumerableSet.Bytes32Set storage) {
        if (_pluginStorage.guardians.length() == 0) {
            return _cls.beneficiaries;
        }
        return _pluginStorage.guardians;
    }

    /**
     * @notice Returns the current threshold required for guardians to vote for distribution.
     * @dev If no threshold is explicitly set in the plugin storage (i.e. equals zero), calculates a default threshold using LibSafeMinimalMultisig.
     * @param _cls The CryptoLegacy storage reference.
     * @param _pluginStorage The plugin-specific storage reference.
     * @return The threshold as a uint8.
     */
    function _getGuardiansThreshold(ICryptoLegacy.CryptoLegacyStorage storage _cls, ITrustedGuardiansPlugin.PluginStorage storage _pluginStorage) internal view returns(uint8) {
        EnumerableSet.Bytes32Set storage guardians = _getGuardians(_cls, _pluginStorage);
        if (_pluginStorage.guardiansThreshold == 0) {
            return uint8(LibSafeMinimalMultisig._calcDefaultConfirmations(guardians.length()));
        }
        return _pluginStorage.guardiansThreshold;
    }

    /**
     * @notice Returns the challenge timeout for guardians.
     * @dev If no explicit threshold is set, returns a default of 30 days.
     * @param _pluginStorage The plugin-specific storage reference.
     * @return The challenge timeout in seconds.
     */
    function _getGuardiansChallengeTimeout(ITrustedGuardiansPlugin.PluginStorage storage _pluginStorage) internal view returns(uint64) {
        if (_pluginStorage.guardiansThreshold == 0) {
            return 30 days;
        }
        return _pluginStorage.guardiansChallengeTimeout;
    }

    /**
     * @notice Initializes or reconfigures the list of guardians, their threshold, and challenge timeout.
     * @dev Only callable by the owner. Clears any prior votes. If no guardians are set, it defaults to beneficiaries as guardians.
     * @param _guardians Array of GuardianToChange specifying which addresses to add or remove.
     * @param _guardiansThreshold Required number of guardian votes.
     * @param _guardiansChallengeTimeout Timeout in seconds that is set for distribution if guardiansThreshold is met.
     */
    function initializeGuardians(GuardianToChange[] memory _guardians, uint8 _guardiansThreshold, uint64 _guardiansChallengeTimeout) external onlyOwner nonReentrant {
        ITrustedGuardiansPlugin.PluginStorage storage pluginStorage = LibTrustedGuardiansPlugin.getPluginStorage();
        _setGuardians(pluginStorage, _guardians);
        _setGuardiansConfig(pluginStorage, _guardiansThreshold, _guardiansChallengeTimeout);
    }

    /**
     * @notice Updates the guardian set.
     * @dev Can only be called by the owner. Processes an array of GuardianToChange structs to add or remove guardians.
     * @param _guardians Array of GuardianToChange structs.
     */
    function setGuardians(GuardianToChange[] memory _guardians) external onlyOwner nonReentrant {
        _setGuardians(LibTrustedGuardiansPlugin.getPluginStorage(), _guardians);
    }

    /**
     * @notice Internal function to update the guardians set.
     * @dev Iterates through the provided GuardianToChange array and adds or removes each guardian.
     *      Also updates the beneficiary registry accordingly.
     * @param _pluginStorage The plugin-specific storage reference.
     * @param _guardians Array of GuardianToChange structs.
     */
    function _setGuardians(ITrustedGuardiansPlugin.PluginStorage storage _pluginStorage, GuardianToChange[] memory _guardians) internal {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        for (uint i = 0; i < _guardians.length; i++) {
            GuardianToChange memory g = _guardians[i];
            if (g.isAdd) {
                _pluginStorage.guardians.add(g.hash);
                LibCryptoLegacy._setCryptoLegacyToBeneficiaryRegistry(cls, g.hash, IBeneficiaryRegistry.EntityType.GUARDIAN, true);
            } else {
                _pluginStorage.guardians.remove(g.hash);
                LibCryptoLegacy._setCryptoLegacyToBeneficiaryRegistry(cls, g.hash, IBeneficiaryRegistry.EntityType.GUARDIAN, false);
            }
            emit SetGuardian(g.hash, g.isAdd);
        }
    }

    /**
     * @notice Updates the guardians configuration.
     * @dev Can only be called by the owner. Resets any previous guardian votes.
     * Reverts if the provided challenge timeout exceeds 30 days.
     * Emits a SetGuardiansConfig event with the new parameters.
     * @param _guardiansThreshold The number of votes required.
     * @param _guardiansChallengeTimeout The timeout (in seconds) after which distribution can be triggered.
     */
    function setGuardiansConfig(uint8 _guardiansThreshold, uint64 _guardiansChallengeTimeout) external onlyOwner nonReentrant {
        _setGuardiansConfig(LibTrustedGuardiansPlugin.getPluginStorage(), _guardiansThreshold, _guardiansChallengeTimeout);
    }

    /**
     * @notice Internal function to update the guardians configuration.
     * @dev Validates that the challenge timeout does not exceed 30 days before updating.
     * Clears all recorded guardian votes.
     * Emits a SetGuardiansConfig event.
     * @param _pluginStorage The plugin-specific storage reference.
     * @param _guardiansThreshold The required number of votes.
     * @param _guardiansChallengeTimeout The challenge timeout in seconds.
     */
    function _setGuardiansConfig(ITrustedGuardiansPlugin.PluginStorage storage _pluginStorage, uint8 _guardiansThreshold, uint64 _guardiansChallengeTimeout) internal {
        if (_guardiansChallengeTimeout > 30 days) {
            revert MaxGuardiansTimeout(30 days);
        }
        _pluginStorage.guardiansThreshold = _guardiansThreshold;
        _pluginStorage.guardiansChallengeTimeout = _guardiansChallengeTimeout;
        _pluginStorage.guardiansVoted = new bytes32[](0);
        emit SetGuardiansConfig(_guardiansThreshold, _guardiansChallengeTimeout);
    }

    /**
     * @notice Allows a guardian to vote for distribution.
     * @dev Checks that the guardian has not already voted before recording the vote.
     *      If the number of votes reaches the required threshold, sets the distribution start time to the current block timestamp plus the guardians challenge timeout.
     * @dev Emits GuardiansDistributionStartSet if the distribution start time is updated, and emits GuardiansVoteForDistribution regardless.
     */
    function guardiansVoteForDistribution() external nonReentrant {
        (ICryptoLegacy.CryptoLegacyStorage storage cls, ITrustedGuardiansPlugin.PluginStorage storage pluginStorage, bytes32 hash) = _checkGuardianNotVoted();

        pluginStorage.guardiansVoted.push(hash);
        uint8 guardiansThreshold = _getGuardiansThreshold(cls, pluginStorage);
        uint64 guardiansChallengeTimeout = _getGuardiansChallengeTimeout(pluginStorage);
        if (pluginStorage.guardiansVoted.length >= guardiansThreshold) {
            uint64 maxDistributionStartAt = uint64(block.timestamp) + guardiansChallengeTimeout;
            if (cls.distributionStartAt == 0 || cls.distributionStartAt > maxDistributionStartAt) {
                cls.distributionStartAt = maxDistributionStartAt;
                emit GuardiansDistributionStartSet(hash, maxDistributionStartAt);
            }
            pluginStorage.guardiansVoted = new bytes32[](0);
        }
        emit GuardiansVoteForDistribution(hash, pluginStorage.guardiansVoted.length);
    }

    /**
     * @notice Allows a guardian to transfer treasury tokens from specified holders to the legacy contract.
     * @dev Checks that the caller is a guardian and that the distribution phase is ready before transferring tokens.
     * @param _holders Array of addresses from which tokens will be transferred.
     * @param _tokens Array of token addresses to be transferred.
     */
    function guardiansTransferTreasuryTokensToLegacy(address[] memory _holders, address[] memory _tokens) external nonReentrant {
        (ICryptoLegacy.CryptoLegacyStorage storage cls, , ) = _checkGuardian();
        LibCryptoLegacy._checkDistributionReady(cls);
        LibCryptoLegacy._transferTreasuryTokensToLegacy(cls, _holders, _tokens);
    }

    /**
     * @notice Resets the guardian voting state, clearing the guardiansVoted array and resetting distributionStartAt.
     * @dev Can only be called by the owner.
     */
    function resetGuardianVoting() external onlyOwner nonReentrant {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        LibTrustedGuardiansPlugin._resetGuardianVoting(cls);
    }

    /**
     * @notice Internal view function to check guardian initialization.
     * @param _pluginStorage The plugin-specific storage.
     * @return True if the guardians set is non-empty, false otherwise.
     */
    function _isGuardiansInitialized(ITrustedGuardiansPlugin.PluginStorage storage _pluginStorage) internal view returns(bool) {
        return _pluginStorage.guardians.length() != 0;
    }

    /**
     * @notice Checks whether guardians have been explicitly initialized.
     * @dev Returns true if the guardians set in plugin storage is non-empty.
     * @return True if guardians are initialized, false otherwise.
     */
    function isGuardiansInitialized() external view returns(bool) {
        return _isGuardiansInitialized(LibTrustedGuardiansPlugin.getPluginStorage());
    }

    /**
     * @notice Retrieves current guardian data.
     * @dev Returns the list of guardian identifiers, the list of votes already cast, the required vote threshold, and the challenge timeout.
     * @return guardians An array of guardian identifiers.
     * @return guardiansVoted An array of guardian identifiers that have already voted.
     * @return guardiansThreshold The number of votes required to trigger distribution.
     * @return guardiansChallengeTimeout The timeout (in seconds) applied when the vote threshold is met.
     */
    function getGuardiansData() external view returns(
        bytes32[] memory guardians,
        bytes32[] memory guardiansVoted,
        uint8 guardiansThreshold,
        uint64 guardiansChallengeTimeout
    ) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        ITrustedGuardiansPlugin.PluginStorage storage pluginStorage = LibTrustedGuardiansPlugin.getPluginStorage();
        return (
            _getGuardians(cls, pluginStorage).values(),
            pluginStorage.guardiansVoted,
            _getGuardiansThreshold(cls, pluginStorage),
            _getGuardiansChallengeTimeout(pluginStorage)
        );
    }
}