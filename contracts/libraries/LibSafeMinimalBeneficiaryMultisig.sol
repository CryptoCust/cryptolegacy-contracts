/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../interfaces/ISafeMinimalMultisig.sol";
import "./LibCryptoLegacy.sol";
import "./LibSafeMinimalMultisig.sol";

library LibSafeMinimalBeneficiaryMultisig {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @notice Ensures that the caller is the designated multisig executor.
     * @dev Only the contract itself is allowed to execute multisig operations.
     * Reverts with ISafeMinimalMultisig.MultisigOnlyExecutor if msg.sender is not this contract.
     */
    function _checkIsMultisigExecutor() internal view {
        LibSafeMinimalMultisig._checkIsMultisigExecutor();
    }

    /**
     * @notice Determines the initialization status of the multisig storage.
     * @dev Returns INITIALIZED if requiredConfirmations is non‑zero, otherwise returns NOT_INITIALIZED_NO_NEED.
     * @param s The multisig storage structure.
     * @return status The initialization status as defined by ISafeMinimalMultisig.InitializationStatus.
     */
    function _initializationStatus(ISafeMinimalMultisig.Storage storage s) internal view returns(ISafeMinimalMultisig.InitializationStatus status) {
        if (s.requiredConfirmations != 0) {
            return ISafeMinimalMultisig.InitializationStatus.INITIALIZED;
        } else {
            return ISafeMinimalMultisig.InitializationStatus.NOT_INITIALIZED_NO_NEED;
        }
    }

    /**
     * @notice Retrieves the list of voters and the number of required confirmations for multisig operations.
     * @dev Voters are fetched from the CryptoLegacy storage beneficiaries, and required confirmations are computed.
     * @param s The multisig storage structure.
     * @return A tuple containing:
     *  - An array of voter identifiers (bytes32[]).
     *  - The number of required confirmations (uint256).
     */
    function _getVotersAndConfirmations(ISafeMinimalMultisig.Storage storage s) internal view returns(bytes32[] memory, uint256) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return (_getVoters(cls), _getRequiredConfirmations(s, cls));
    }

    /**
     * @notice Retrieves the entire list of proposals submitted to the multisig.
     * @dev Returns an array of proposals stored in the multisig storage.
     * @param s The multisig storage structure.
     * @return An array of ISafeMinimalMultisig.Proposal.
     */
    function _getProposalList(ISafeMinimalMultisig.Storage storage s) internal view returns(ISafeMinimalMultisig.Proposal[] memory) {
        return s.proposals;
    }

    /**
     * @notice Retrieves a specific proposal by its proposal ID.
     * @dev Accesses the proposals array at the given index.
     * @param s The multisig storage structure.
     * @param _proposalId The index of the proposal.
     * @return The ISafeMinimalMultisig.Proposal corresponding to _proposalId.
     */
    function _getProposal(ISafeMinimalMultisig.Storage storage s, uint256 _proposalId) internal view returns(ISafeMinimalMultisig.Proposal memory) {
        return s.proposals[_proposalId];
    }

    /**
     * @notice Retrieves the multisig proposals along with their voting statuses, the list of voters, and required confirmations.
     * @dev Iterates over all proposals and computes their statuses via LibSafeMinimalMultisig._getProposalWithStatus.
     * @param cls The CryptoLegacy storage structure.
     * @param s The multisig storage structure.
     * @return voters The array of voter identifiers.
     * @return requiredConfirmations The number of confirmations required for a proposal to be approved.
     * @return proposalsWithStatuses An array of proposals with their computed statuses.
     */
    function _getProposalListWithStatuses(
        ICryptoLegacy.CryptoLegacyStorage storage cls,
        ISafeMinimalMultisig.Storage storage s
    ) internal view returns(
        bytes32[] memory voters,
        uint256 requiredConfirmations,
        ISafeMinimalMultisig.ProposalWithStatus[] memory proposalsWithStatuses
    ) {
        voters = _getVoters(cls);
        uint256 length = s.proposals.length;
        requiredConfirmations = _getRequiredConfirmations(s, cls);
        proposalsWithStatuses = new ISafeMinimalMultisig.ProposalWithStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            proposalsWithStatuses[i] = LibSafeMinimalMultisig._getProposalWithStatus(s, voters, i);
        }
    }

    /**
     * @notice Retrieves a specific proposal along with its voting status.
     * @dev Returns the voter list, required confirmations, and the proposal with its computed status.
     * @param cls The CryptoLegacy storage structure.
     * @param s The multisig storage structure.
     * @param _proposalId The index of the proposal to retrieve.
     * @return voters The array of voter identifiers.
     * @return requiredConfirmations The number of required confirmations.
     * @return proposalWithStatus The proposal with its status details.
     */
    function _getProposalWithStatus(
        ICryptoLegacy.CryptoLegacyStorage storage cls,
        ISafeMinimalMultisig.Storage storage s,
        uint256 _proposalId
    ) internal view returns(
        bytes32[] memory voters,
        uint256 requiredConfirmations,
        ISafeMinimalMultisig.ProposalWithStatus memory proposalWithStatus
    ) {
        voters = _getVoters(cls);
        proposalWithStatus = LibSafeMinimalMultisig._getProposalWithStatus(s, voters, _proposalId);
        requiredConfirmations = _getRequiredConfirmations(s, cls);
    }

    /**
     * @notice Computes the number of required confirmations for multisig proposals.
     * @dev If the multisig storage is not initialized, returns the default required confirmations calculated from the beneficiaries count.
     * Otherwise, returns the stored requiredConfirmations.
     * @param s The multisig storage structure.
     * @param cls The CryptoLegacy storage structure.
     * @return The number of required confirmations.
     */
    function _getRequiredConfirmations(ISafeMinimalMultisig.Storage storage s, ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(uint256) {
        if (LibSafeMinimalMultisig._initializationStatus(s) != ISafeMinimalMultisig.InitializationStatus.INITIALIZED) {
            return _getDefaultRequiredConfirmations(cls);
        }
        return s.requiredConfirmations;
    }

    /**
     * @notice Retrieves the list of voter identifiers from the CryptoLegacy beneficiaries.
     * @dev Voters are derived from the values stored in the beneficiaries enumerable set.
     * @param cls The CryptoLegacy storage structure.
     * @return An array of bytes32 voter identifiers.
     */
    function _getVoters(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(bytes32[] memory) {
        return cls.beneficiaries.values();
    }

    /**
     * @notice Calculates the default number of required confirmations based on the number of beneficiaries.
     * @dev Invokes LibSafeMinimalMultisig._calcDefaultConfirmations() using the beneficiary count from LibCryptoLegacy._getBeneficiariesCount().
     * @param cls The CryptoLegacy storage structure.
     * @return The default required confirmations.
     */
    function _getDefaultRequiredConfirmations(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(uint256) {
        return LibSafeMinimalMultisig._calcDefaultConfirmations(LibCryptoLegacy._getBeneficiariesCount(cls));
    }

    /**
     * @notice Sets the number of required confirmations for multisig operations.
     * @dev Ensures that _requiredConfirmations is non‑zero and does not exceed the length of the _voters array.
     * Reverts with ISafeMinimalMultisig.MultisigIncorrectRequiredConfirmations if the condition fails.
     * @param s The multisig storage structure.
     * @param _voters An array of voter identifiers.
     * @param _requiredConfirmations The new number of required confirmations.
     */
    function _setConfirmations(ISafeMinimalMultisig.Storage storage s, bytes32[] memory _voters, uint256 _requiredConfirmations) internal {
        if (_requiredConfirmations > _voters.length || _requiredConfirmations == 0) {
            revert ISafeMinimalMultisig.MultisigIncorrectRequiredConfirmations();
        }
        s.requiredConfirmations = _requiredConfirmations;
        emit ISafeMinimalMultisig.SetConfirmations(_requiredConfirmations);
    }

    /**
     * @notice Initializes the multisig storage with default required confirmations if not already initialized.
     * @dev Retrieves the voters from CryptoLegacy storage and sets the default confirmations based on the beneficiaries count.
     * @param s The multisig storage structure.
     * @param _voters An array of voter identifiers.
     */
    function _initializeIfNot(ISafeMinimalMultisig.Storage storage s, bytes32[] memory _voters) internal {
        if (LibSafeMinimalMultisig._initializationStatus(s) != ISafeMinimalMultisig.InitializationStatus.INITIALIZED) {
            ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
            _setConfirmations(s, _voters,_getDefaultRequiredConfirmations(cls));
        }
    }

    /**
     * @notice Submits a new multisig proposal.
     * @dev Retrieves the CryptoLegacy storage to obtain the voter list, initializes multisig if needed, and then forwards
     * the proposal details (allowed methods, function selector, and parameters) to LibSafeMinimalMultisig._propose.
     * @param s The multisig storage structure.
     * @param _allowedMethods An array of method selectors (bytes4) permitted for the proposal.
     * @param _selector The function selector representing the action proposed.
     * @param _params The ABI-encoded parameters for the proposal.
     */
    function _propose(ISafeMinimalMultisig.Storage storage s, bytes4[] memory _allowedMethods, bytes4 _selector, bytes memory _params) internal {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        bytes32[] memory voters = _getVoters(cls);
        _initializeIfNot(s, voters);
        LibSafeMinimalMultisig._propose(s, voters, _allowedMethods, _selector, _params);
    }

    /**
     * @notice Confirms an existing multisig proposal.
     * @dev Retrieves the voter list from CryptoLegacy storage, ensures multisig initialization,
     * and then confirms the proposal with the given proposal ID via LibSafeMinimalMultisig._confirm.
     * @param s The multisig storage structure.
     * @param _proposalId The ID (index) of the proposal to be confirmed.
     */
    function _confirm(ISafeMinimalMultisig.Storage storage s, uint256 _proposalId) internal {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        bytes32[] memory voters = _getVoters(cls);
        _initializeIfNot(s, voters);
        LibSafeMinimalMultisig._confirm(s, voters, _proposalId);
    }
}