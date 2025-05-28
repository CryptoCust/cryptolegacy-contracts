/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../libraries/LibDiamond.sol";
import "../libraries/LibCryptoLegacyPlugins.sol";
import "../interfaces/ICryptoLegacy.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";
import "../libraries/LibSafeMinimalBeneficiaryMultisig.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title BeneficiaryPluginAddRights
 * @notice Empowers beneficiaries to add additional plugin functionality to tailor the distribution process. This plugin enhances control over asset distribution rights and ensures beneficiaries can manage their claims under predefined conditions.
*/
contract BeneficiaryPluginAddRights is ICryptoLegacyPlugin, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant PLUGIN_MULTISIG_POSITION = keccak256("beneficiary_plugin_add_rights.multisig.plugin.storage");

    /**
     * @notice Returns the function selectors provided by this plugin for managing beneficiary distribution rights.
     * @dev These selectors represent the externally accessible methods implemented in this plugin.
     * @return sigs An array of function selectors.
     */
    function getSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](9);
        sigs[0] = this.barGetInitializationStatus.selector;
        sigs[1] = this.barSetMultisigConfig.selector;
        sigs[2] = this.barPropose.selector;
        sigs[3] = this.barCancel.selector;
        sigs[4] = this.barConfirm.selector;
        sigs[5] = this.barAddPluginList.selector;
        sigs[6] = this.barGetVotersAndConfirmations.selector;
        sigs[7] = this.barGetProposalWithStatus.selector;
        sigs[8] = this.barGetProposalListWithStatuses.selector;
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
     * @notice Returns the multisig method selectors that are allowed to be executed via proposals.
     * @dev These allowed methods include adding plugin lists and setting multisig configuration.
     * @return sigs An array of function selectors for multisig proposals.
     */
    function getMultisigAllowedMethods() public pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](2);
        sigs[0] = this.barAddPluginList.selector;
        sigs[1] = this.barSetMultisigConfig.selector;
    }

    /**
     * @notice Returns the unique name for this plugin.
     * @dev The name is used for identification purposes across the CryptoLegacy ecosystem.
     * @return A string representing the plugin name.
     */
    function getPluginName() public pure returns (string memory) {
        return "beneficiary_plugin_add_rights";
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
     * @notice Modifier that ensures token distribution has started.
     * @dev Calls LibCryptoLegacy._checkDistributionReady() to validate that distribution is ready.
     */
    modifier onlyDistributionReady() {
        LibCryptoLegacy._checkDistributionReady(LibCryptoLegacy.getCryptoLegacyStorage());
        _;
    }

    /**
     * @notice Retrieves the multisig storage structure for this plugin.
     * @dev Uses a fixed storage slot (PLUGIN_MULTISIG_POSITION) to avoid collisions.
     * @return storageStruct A reference to the ISafeMinimalMultisig.Storage struct.
     */
    function getPluginMultisigStorage() internal pure returns (ISafeMinimalMultisig.Storage storage storageStruct) {
        bytes32 position = PLUGIN_MULTISIG_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }

    /**
     * @notice Sets the multisig configuration for beneficiary actions.
     * @dev Allows the owner (or the contract itself when distribution is ready) to update multisig confirmation requirements.
     *      Calls LibSafeMinimalBeneficiaryMultisig._setConfirmations() using the current beneficiaries.
     * @param _requiredConfirmations The number of confirmations required for multisig proposals.
     */
    function barSetMultisigConfig(uint128 _requiredConfirmations) external {
        if (msg.sender == address(this)) {
            LibCryptoLegacy._checkDistributionReady(LibCryptoLegacy.getCryptoLegacyStorage());
        } else {
            LibCryptoLegacy._checkOwner();
        }
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        LibSafeMinimalBeneficiaryMultisig._setConfirmations(getPluginMultisigStorage(), cls.beneficiaries.values(), _requiredConfirmations);
    }

    /**
     * @notice Submits a new multisig proposal.
     * @dev Validates if the proposer is an allowed voter and the method is permitted before adding the proposal.
     *      Automatically executes the proposal if only one confirmation is required.
     * @param _selector The function selector targeted by the proposal.
     * @param _params The ABI-encoded parameters to be passed when executing the proposal.
     */
    function barPropose(bytes4 _selector, bytes memory _params) nonReentrant external onlyDistributionReady returns(uint256 proposalId) {
        return LibSafeMinimalBeneficiaryMultisig._propose(getPluginMultisigStorage(), getMultisigAllowedMethods(), _selector, _params);
    }

    /**
     * @notice Confirms an existing multisig proposal.
     * @dev Records a confirmation from the caller and executes the proposal if the confirmations threshold is met.
     * @param _proposalId The identifier of the proposal to confirm.
     */
    function barConfirm(uint256 _proposalId) external nonReentrant onlyDistributionReady {
        LibSafeMinimalBeneficiaryMultisig._confirm(getPluginMultisigStorage(), _proposalId);
    }

    /**
     * @notice Cancels a previously confirmed proposal, removing the caller’s confirmation and possibly voiding it.
     * @dev Condition check: The proposal must not be executed or canceled; the caller must have confirmed it previously.
     * @param _proposalId The ID of the proposal to cancel confirmation for.
     */
    function barCancel(uint256 _proposalId) external nonReentrant onlyDistributionReady {
        LibSafeMinimalBeneficiaryMultisig._cancel(getPluginMultisigStorage(), _proposalId);
    }

    /**
     * @notice Adds a new list of plugins to the CryptoLegacy system.
     * @dev Ensures distribution is ready and that the caller is a multisig executor before proceeding.
     *      Calls LibCryptoLegacyPlugins._addPluginList with the provided plugin addresses.
     * @param _plugins An array of plugin contract addresses to be added.
     */
    function barAddPluginList(address[] memory _plugins) external onlyDistributionReady {
        LibSafeMinimalBeneficiaryMultisig._checkIsMultisigExecutor();

        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

        LibCryptoLegacy._checkDistributionReady(cls);
        LibCryptoLegacyPlugins._addPluginList(cls,_plugins);
    }

    /**
     * @notice Retrieves the initialization status of the multisig configuration.
     * @dev Returns whether the multisig storage for this plugin has been initialized.
     * @return status The current initialization status as defined in ISafeMinimalMultisig.InitializationStatus.
     */
    function barGetInitializationStatus() external view returns(ISafeMinimalMultisig.InitializationStatus status) {
        return LibSafeMinimalBeneficiaryMultisig._initializationStatus(getPluginMultisigStorage());
    }

    /**
     * @notice Retrieves the list of multisig voters and the number of required confirmations.
     * @dev Returns the current configuration for multisig execution in this plugin.
     * @return A tuple containing:
     *  - An array of voter identifiers (bytes32[]).
     *  - The required number of confirmations (uint128).
     */
    function barGetVotersAndConfirmations() external view returns(bytes32[] memory, uint128) {
        return LibSafeMinimalBeneficiaryMultisig._getVotersAndConfirmations(getPluginMultisigStorage());
    }

    /**
     * @notice Retrieves a specific proposal along with its confirmation status.
     * @dev Returns detailed information including the list of voters, required confirmations,
     * and the proposal status (including per-voter confirmation flags).
     * @param _proposalId The identifier of the proposal.
     * @return voters An array of voter identifiers.
     * @return requiredConfirmations The number of required confirmations.
     * @return proposalWithStatus A ProposalWithStatus struct containing the proposal details and confirmation information.
     */
    function barGetProposalWithStatus(uint256 _proposalId) external view returns(
        bytes32[] memory voters,
        uint128 requiredConfirmations,
        ISafeMinimalMultisig.ProposalWithStatus memory proposalWithStatus
    ) {
        return LibSafeMinimalBeneficiaryMultisig._getProposalWithStatus(
            LibCryptoLegacy.getCryptoLegacyStorage(),
            getPluginMultisigStorage(),
            _proposalId
        );
    }

    /**
     * @notice Retrieves the entire list of proposals along with their confirmation statuses.
     * @dev Returns the current multisig proposals managed by the plugin, paired with their status details.
     * @return voters An array of voter identifiers.
     * @return requiredConfirmations The confirmation threshold required for proposal execution.
     * @return proposalsWithStatuses An array of ProposalWithStatus structs for each proposal.
     */
    function barGetProposalListWithStatuses() external view returns(
        bytes32[] memory voters,
        uint128 requiredConfirmations,
        ISafeMinimalMultisig.ProposalWithStatus[] memory proposalsWithStatuses
    ) {
        return LibSafeMinimalBeneficiaryMultisig._getProposalListWithStatuses(
            LibCryptoLegacy.getCryptoLegacyStorage(),
            getPluginMultisigStorage()
        );
    }
}