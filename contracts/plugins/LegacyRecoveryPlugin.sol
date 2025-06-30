/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../interfaces/ICryptoLegacy.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";
import "../libraries/LibSafeMinimalMultisig.sol";
import "../libraries/LibCryptoLegacyPlugins.sol";
import "../libraries/LibTrustedGuardiansPlugin.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract LegacyRecoveryPlugin is ICryptoLegacyPlugin, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant PLUGIN_MULTISIG_POSITION = keccak256("legacy_recovery.multisig.plugin.storage");

    /**
     * @notice Returns the function selectors provided by this plugin.
     * @dev These selectors identify the externally callable recovery functions.
     * @return sigs An array of function selectors.
     */
    function getSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](12);
        sigs[0] = this.lrSetMultisigConfig.selector;
        sigs[1] = this.lrPropose.selector;
        sigs[2] = this.lrConfirm.selector;
        sigs[3] = this.lrCancel.selector;
        sigs[4] = this.lrTransferTreasuryTokensToLegacy.selector;
        sigs[5] = this.lrWithdrawTokensFromLegacy.selector;
        sigs[6] = this.lrResetGuardianVoting.selector;
        sigs[7] = this.lrGetInitializationStatus.selector;
        sigs[8] = this.lrGetProposalWithStatus.selector;
        sigs[9] = this.lrGetProposalListWithStatuses.selector;
        sigs[10] = this.lrWithdrawHeldEth.selector;
        sigs[11] = this.lrGetHeldEth.selector;
    }

    /**
     * @notice Returns the setup function selectors for this plugin.
     * @dev This plugin does not require any setup functions.
     * @return sigs An empty array of function selectors.
     */
    function getSetupSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](0);
    }

    /**
     * @notice Returns the function selectors that are allowed to be executed via multisig proposals.
     * @dev These allowed methods include treasury token transfers and resetting guardian voting.
     * @return sigs An array containing the allowed function selectors.
     */
    function getMultisigAllowedMethods() public pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](3);
        sigs[0] = this.lrTransferTreasuryTokensToLegacy.selector;
        sigs[1] = this.lrWithdrawTokensFromLegacy.selector;
        sigs[2] = this.lrResetGuardianVoting.selector;
    }

    /**
     * @notice Returns the unique name for this plugin.
     * @dev The name is used for identification purposes across the CryptoLegacy ecosystem.
     * @return A string representing the plugin name.
     */
    function getPluginName() public pure returns (string memory) {
        return "legacy_recover";
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
     * @notice Retrieves the multisig storage structure dedicated to this plugin.
     * @dev Uses the fixed storage slot (PLUGIN_MULTISIG_POSITION) to avoid collisions with other storage.
     * @return storageStruct A reference to the ISafeMinimalMultisig.Storage struct.
     */
    function getPluginMultisigStorage() internal pure returns (ISafeMinimalMultisig.Storage storage storageStruct) {
        bytes32 position = PLUGIN_MULTISIG_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }

    /**
     * @notice Sets the multisig configuration for recovery operations.
     * @dev Only callable by the owner. Updates both the local multisig storage and the recovery list in the Beneficiary Registry.
     * @param _voters An array of voter identifiers (bytes32) to be used for multisig proposals.
     * @param _requiredConfirmations The number of confirmations required to execute a proposal.
     */
    function lrSetMultisigConfig(bytes32[] memory _voters, uint8 _requiredConfirmations) external onlyOwner {
        ISafeMinimalMultisig.Storage storage pluginStorage = getPluginMultisigStorage();
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        LibCryptoLegacy._setCryptoLegacyListToBeneficiaryRegistry(cls, pluginStorage.voters, _voters, IBeneficiaryRegistry.EntityType.RECOVERY);
        LibSafeMinimalMultisig._setVotersAndConfirmations(pluginStorage, _voters, _requiredConfirmations);
    }

    /**
     * @notice Submits a new multisig proposal.
     * @dev Validates if the proposer is an allowed voter and the method is permitted before adding the proposal.
     *      Automatically executes the proposal if only one confirmation is required.
     * @param _selector The function selector targeted by the proposal.
     * @param _params The ABI-encoded parameters to be passed when executing the proposal.
     * @param _salt Secret salt to improve address hash security. Optional, can be zero.
     */
    function lrPropose(bytes4 _selector, bytes memory _params, bytes32 _salt) external payable returns(uint256 proposalId) {
        ISafeMinimalMultisig.Storage storage pluginStorage = getPluginMultisigStorage();
        return LibSafeMinimalMultisig._propose(pluginStorage, _salt, pluginStorage.requiredConfirmations, pluginStorage.voters, getMultisigAllowedMethods(), _selector, _params);
    }

    /**
     * @notice Confirms an existing multisig proposal.
     * @dev Records a confirmation from the caller and executes the proposal if the confirmations threshold is met.
     * @param _proposalId The identifier of the proposal to confirm.
     * @param _salt Secret salt to improve address hash security. Optional, can be zero.
     */
    function lrConfirm(uint256 _proposalId, bytes32 _salt) external payable {
        ISafeMinimalMultisig.Storage storage pluginStorage = getPluginMultisigStorage();
        LibSafeMinimalMultisig._confirm(pluginStorage, _salt, pluginStorage.requiredConfirmations, pluginStorage.voters, _proposalId);
    }

    /**
     * @notice Cancels a previously confirmed proposal, removing the caller’s confirmation and possibly voiding it.
     * @dev Condition check: The proposal must not be executed or canceled; the caller must have confirmed it previously.
     * @param _proposalId The ID of the proposal to cancel confirmation for.
     * @param _salt Secret salt to improve address hash security. Optional, can be zero.
     */
    function lrCancel(uint256 _proposalId, bytes32 _salt) external {
        ISafeMinimalMultisig.Storage storage pluginStorage = getPluginMultisigStorage();
        LibSafeMinimalMultisig._cancel(pluginStorage, _salt, pluginStorage.requiredConfirmations, pluginStorage.voters, _proposalId);
    }

    /**
     * @notice Transfers treasury tokens from specified holders to the legacy contract.
     * @dev Only callable by a multisig executor. Invokes the transfer functionality in LibCryptoLegacy.
     * @param _holders An array of addresses holding tokens.
     * @param _tokens An array of ERC20 token addresses to be transferred.
     */
    function lrTransferTreasuryTokensToLegacy(address[] memory _holders, address[] memory _tokens) external nonReentrant {
        LibSafeMinimalMultisig._checkIsMultisigExecutor();
        LibCryptoLegacy._transferTreasuryTokensToLegacy(LibCryptoLegacy.getCryptoLegacyStorage(), _holders, _tokens);
    }

    /**
     * @notice Withdraws tokens from the legacy contract and transfers them to designated recipients.
     * @dev Only callable by a multisig executor. Uses LibCryptoLegacy to perform token transfers.
     * @param _transfers An array of TokenTransferTo structs containing token transfer information.
     */
    function lrWithdrawTokensFromLegacy(ICryptoLegacy.TokenTransferTo[] memory _transfers) external nonReentrant {
        LibSafeMinimalMultisig._checkIsMultisigExecutor();
        LibCryptoLegacy._transferTokensFromLegacy(LibCryptoLegacy.getCryptoLegacyStorage(), _transfers);
    }

    /**
     * @notice Resets the guardian voting process for recovery.
     * @dev Only callable by a multisig executor. Ensures that distribution has not yet started.
     *      Calls LibTrustedGuardiansPlugin._resetGuardianVoting to clear guardian votes and reset distribution start time.
     */
    function lrResetGuardianVoting() external payable nonReentrant {
        LibSafeMinimalMultisig._checkIsMultisigExecutor();
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        LibCryptoLegacy._checkDistributionStart(cls);
        LibTrustedGuardiansPlugin._resetGuardianVoting(cls);
    }

    /**
     * @notice Withdraws any accumulated ETH held for the caller and sends it to the specified recipient.
     * @param _salt   Secret salt used to derive the voter’s hash; use zero for plain address hashing.  
     * @param _recipient Address that will receive the withdrawn ETH.  
     */
    function lrWithdrawHeldEth(bytes32 _salt, address _recipient) external nonReentrant {
        ISafeMinimalMultisig.Storage storage pluginStorage = getPluginMultisigStorage();
        LibSafeMinimalMultisig._withdrawHeldEth(pluginStorage, _salt, pluginStorage.voters, _recipient);
    }
    
    /**
     * @notice Returns the amount of ETH currently held for a given voter identifier.
     * @param _hash Bytes32 identifier of the voter (e.g., from _addressToHash or _addressWithSaltToHash).  
     * @return heldEthBalance The ETH balance available for withdrawal by that voter.  
     */
    function lrGetHeldEth(bytes32 _hash) external view returns(uint256) {
        ISafeMinimalMultisig.Storage storage pluginStorage = getPluginMultisigStorage();
        return pluginStorage.heldEth[_hash];
    }

    /**
     * @notice Retrieves the initialization status of the recovery plugin multisig configuration.
     * @dev Uses LibSafeMinimalMultisig to determine if the multisig storage is initialized.
     * @return status The current initialization status as defined in ISafeMinimalMultisig.InitializationStatus.
     */
    function lrGetInitializationStatus() external view returns(ISafeMinimalMultisig.InitializationStatus status) {
        return LibSafeMinimalMultisig._initializationStatus(getPluginMultisigStorage());
    }

    /**
     * @notice Retrieves a specific multisig proposal along with its status.
     * @dev Returns detailed information including the voter list, required confirmations, and the proposal's confirmation status.
     * @param _proposalId The identifier of the proposal.
     * @return voters An array of voter identifiers.
     * @return requiredConfirmations The number of confirmations required to execute the proposal.
     * @return proposalWithStatus A ProposalWithStatus struct containing the proposal and its per-voter confirmation flags.
     */
    function lrGetProposalWithStatus(uint256 _proposalId) external view returns(
        bytes32[] memory voters,
        uint128 requiredConfirmations,
        ISafeMinimalMultisig.ProposalWithStatus memory proposalWithStatus
    ) {
        ISafeMinimalMultisig.Storage storage pluginStorage = getPluginMultisigStorage();
        return (
            pluginStorage.voters,
            pluginStorage.requiredConfirmations,
            LibSafeMinimalMultisig._getProposalWithStatus(getPluginMultisigStorage(), pluginStorage.voters, _proposalId)
        );
    }

    /**
     * @notice Retrieves the list of multisig proposals with their corresponding statuses.
     * @dev Returns the complete list of proposals stored in the plugin's multisig storage along with the required confirmations.
     * @return voters An array of voter identifiers.
     * @return requiredConfirmations The multisig confirmation threshold.
     * @return proposalsWithStatuses An array of ProposalWithStatus structs for each proposal.
     */
    function lrGetProposalListWithStatuses() external view returns(
        bytes32[] memory voters,
        uint128 requiredConfirmations,
        ISafeMinimalMultisig.ProposalWithStatus[] memory proposalsWithStatuses
    ) {
        return LibSafeMinimalMultisig._getProposalListWithStatusesAndStorageVoters(getPluginMultisigStorage());
    }
}