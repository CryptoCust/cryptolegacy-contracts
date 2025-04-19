/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./LibCryptoLegacy.sol";
import "../interfaces/ISafeMinimalMultisig.sol";

library LibSafeMinimalMultisig {
    /**
     * @notice Ensures that the caller is the designated multisig executor.
     * @dev Only the contract itself is allowed to execute multisig operations.
     * Reverts with ISafeMinimalMultisig.MultisigOnlyExecutor if msg.sender is not this contract.
     */
    function _checkIsMultisigExecutor() internal view {
        if (msg.sender != address(this)) {
            revert ISafeMinimalMultisig.MultisigOnlyExecutor();
        }
    }

    /**
     * @notice Verifies that a given voter is allowed by comparing against an array of allowed voters.
     * @dev Iterates through _allVoters to ensure that _voter exists.
     * Reverts with ISafeMinimalMultisig.MultisigVoterNotAllowed if _voter is not contained in _allVoters.
     * @param _allVoters The array of allowed voter identifiers.
     * @param _voter The voter identifier (hash of the voter's address) to check.
     */
    function _checkIsVoterAllowed(bytes32[] memory _allVoters, bytes32 _voter) internal pure {
        if (!_isVoterAllowed(_allVoters, _voter)) {
            revert ISafeMinimalMultisig.MultisigVoterNotAllowed();
        }
    }

    /**
    * @notice Sets the list of voters and the required number of confirmations for multisig operations.
     * @dev Validates that _requiredConfirmations is non‑zero and does not exceed the length of _voters.
     * Reverts with ISafeMinimalMultisig.MultisigIncorrectRequiredConfirmations if validation fails.
     * @param s The multisig storage structure.
     * @param _voters An array of voter identifiers.
     * @param _requiredConfirmations The number of confirmations required to execute a proposal.
     */
    function _setVotersAndConfirmations(ISafeMinimalMultisig.Storage storage s, bytes32[] memory _voters, uint256 _requiredConfirmations) internal {
        if (_requiredConfirmations > _voters.length || _requiredConfirmations == 0) {
            revert ISafeMinimalMultisig.MultisigIncorrectRequiredConfirmations();
        }
        s.voters = _voters;
        s.requiredConfirmations = _requiredConfirmations;
        emit ISafeMinimalMultisig.SetVotersAndConfirmations(_voters, _requiredConfirmations);
    }

    /**
     * @notice Returns the initialization status of the multisig storage.
     * @dev Checks if the required confirmations has been set.
     * @param s The multisig storage structure.
     * @return status The initialization status. Returns INITIALIZED if requiredConfirmations is non‑zero,
     * otherwise returns NOT_INITIALIZED_BUT_NEED.
     */
    function _initializationStatus(ISafeMinimalMultisig.Storage storage s) internal view returns(ISafeMinimalMultisig.InitializationStatus status) {
        if (s.requiredConfirmations != 0) {
            return ISafeMinimalMultisig.InitializationStatus.INITIALIZED;
        } else {
            return ISafeMinimalMultisig.InitializationStatus.NOT_INITIALIZED_BUT_NEED;
        }
    }

    /**
     * @notice Calculates the default number of confirmations required based on the total number of voters.
     * @dev Uses the formula: (voterCount / 2) + 1.
     * @param _voterCount The total count of voters.
     * @return The default number of required confirmations.
     */
    function _calcDefaultConfirmations(uint256 _voterCount) internal pure returns(uint256) {
        return (_voterCount / 2) + 1;
    }

    /**
     * @notice Checks if a given method (identified by its selector) is allowed.
     * @dev Iterates over _allowedMethods and returns true if _selector is found.
     * @param _allowedMethods An array of permitted function selectors.
     * @param _selector The function selector to check.
     * @return True if _selector is allowed, false otherwise.
     */
    function _isMethodAllowed(bytes4[] memory _allowedMethods, bytes4 _selector) internal pure returns(bool) {
        for(uint256 i = 0; i < _allowedMethods.length; i++) {
            if (_allowedMethods[i] == _selector) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Checks if a voter is allowed by verifying their presence in the allowed voters list.
     * @dev Iterates through _allVoters and returns true if _voter is found.
     * @param _allVoters An array of allowed voter identifiers.
     * @param _voter The voter identifier to check.
     * @return True if _voter is allowed, false otherwise.
     */
    function _isVoterAllowed(bytes32[] memory _allVoters, bytes32 _voter) internal pure returns(bool) {
        for (uint256 i = 0; i < _allVoters.length; i++) {
            if (_allVoters[i] == _voter) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Counts how many voters have confirmed a specific proposal.
     * @dev Iterates over all voters in _allVoters and counts true confirmations from the storage.
     * @param s The multisig storage structure.
     * @param _allVoters The array of voter identifiers.
     * @param _proposalId The proposal identifier.
     * @return confirmed The total number of confirmations for the proposal.
     */
    function _getConfirmedCount(ISafeMinimalMultisig.Storage storage s, bytes32[] memory _allVoters, uint256 _proposalId) internal view returns(uint256 confirmed) {
        for (uint256 i = 0; i < _allVoters.length; i++) {
            if (s.confirmedBy[_proposalId][_allVoters[i]]) {
                confirmed++;
            }
        }
        return confirmed;
    }

    /**
     * @notice Retrieves the stored voters and required confirmations from multisig storage.
     * @dev Returns the voter list and the required confirmation threshold.
     * @param s The multisig storage structure.
     * @return voters The array of voter identifiers.
     * @return requiredConfirmations The number of required confirmations.
     */
    function _getStorageVotersAndConfirmations(ISafeMinimalMultisig.Storage storage s) internal view returns(bytes32[] memory, uint256) {
        return (s.voters, s.requiredConfirmations);
    }

    /**
     * @notice Retrieves a specific proposal from storage.
     * @dev Accesses the proposals array at the provided index.
     * @param s The multisig storage structure.
     * @param _proposalId The identifier of the proposal.
     * @return The Proposal corresponding to _proposalId.
     */
    function _getProposal(ISafeMinimalMultisig.Storage storage s, uint256 _proposalId) internal view returns(ISafeMinimalMultisig.Proposal memory) {
        return s.proposals[_proposalId];
    }

    /**
     * @notice Retrieves the complete list of proposals.
     * @dev Returns an array containing all proposals stored in the multisig.
     * @param s The multisig storage structure.
     * @return An array of Proposal structs.
     */
    function _getProposalList(ISafeMinimalMultisig.Storage storage s) internal view returns(ISafeMinimalMultisig.Proposal[] memory) {
        return s.proposals;
    }

    /**
     * @notice Retrieves all proposals with their confirmation statuses and the stored voter list.
     * @dev Constructs an array of ProposalWithStatus structs by computing each proposal's confirmation details.
     * @param s The multisig storage structure.
     * @return voters The array of voter identifiers.
     * @return requiredConfirmations The number of required confirmations.
     * @return proposalsWithStatuses An array of proposals paired with their confirmation statuses.
     */
    function _getProposalListWithStatusesAndStorageVoters(ISafeMinimalMultisig.Storage storage s) internal view returns(
        bytes32[] memory voters,
        uint256 requiredConfirmations,
        ISafeMinimalMultisig.ProposalWithStatus[] memory proposalsWithStatuses
    ) {
        voters = s.voters;
        uint256 length = s.proposals.length;
        requiredConfirmations = s.requiredConfirmations;
        proposalsWithStatuses = new ISafeMinimalMultisig.ProposalWithStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            proposalsWithStatuses[i] =  LibSafeMinimalMultisig._getProposalWithStatus(s, voters, i);
        }
    }

    /**
     * @notice Retrieves a proposal along with its per-voter confirmation status.
     * @dev Iterates over the provided voters list to create a boolean array indicating which voters confirmed the proposal.
     * The total confirmation count is updated if the proposal is not yet executed.
     * @param s The multisig storage structure.
     * @param voters The array of allowed voter identifiers.
     * @param _proposalId The proposal identifier.
     * @return proposalWithStatus A struct that pairs the proposal details with an array of boolean confirmation flags.
     */
    function _getProposalWithStatus(ISafeMinimalMultisig.Storage storage s, bytes32[] memory voters, uint256 _proposalId) internal view returns(ISafeMinimalMultisig.ProposalWithStatus memory proposalWithStatus) {
        bool[] memory confirmedBy = new bool[](voters.length);
        ISafeMinimalMultisig.Proposal memory proposal = s.proposals[_proposalId];
        uint256 confirms = 0;
        for (uint256 j = 0; j < voters.length; j++) {
            confirmedBy[j] = s.confirmedBy[_proposalId][voters[j]];
            if (confirmedBy[j]) {
                confirms++;
            }
        }
        if (!proposal.executed) {
            proposal.confirms = confirms;
        }
        return ISafeMinimalMultisig.ProposalWithStatus(proposal, confirmedBy);
    }

    /**
     * @notice Submits a new multisig proposal.
     * @dev Verifies that the method (identified by _selector) is allowed and that the sender is an authorized voter.
     * Records the proposal in storage and automatically confirms the proposal by the sender.
     * Emits the CreateSafeMinimalMultisigProposal event.
     * If the required confirmations equal 1, the proposal is executed immediately.
     * @param s The multisig storage structure.
     * @param _allVoters The array of allowed voter identifiers.
     * @param _allowedMethods An array of permitted function selectors.
     * @param _selector The function selector representing the action of the proposal.
     * @param _params The ABI-encoded parameters for the proposed action.
     */
    function _propose(ISafeMinimalMultisig.Storage storage s, bytes32[] memory _allVoters, bytes4[] memory _allowedMethods, bytes4 _selector, bytes memory _params) internal {
        bytes32 voter = LibCryptoLegacy._addressToHash(msg.sender);
        if (!_isMethodAllowed(_allowedMethods, _selector)) {
            revert ISafeMinimalMultisig.MultisigMethodNotAllowed();
        }
        _checkIsVoterAllowed(_allVoters, voter);

        s.proposals.push(ISafeMinimalMultisig.Proposal(_selector, _params, 1, false));
        uint256 proposalId = s.proposals.length - 1;
        s.confirmedBy[proposalId][voter] = true;

        emit ISafeMinimalMultisig.CreateSafeMinimalMultisigProposal(proposalId, voter, s.requiredConfirmations);

        if (s.requiredConfirmations == 1) {
            _execute(s, voter, proposalId);
        }
    }

    /**
     * @notice Records a confirmation for an existing multisig proposal.
     * @dev Checks that the proposal is not already executed and that the sender has not already confirmed.
     * Records the confirmation, updates the confirmation count, and emits the ConfirmSafeMinimalMultisigProposal event.
     * If the total confirmations reach the required threshold, the proposal is executed.
     * @param s The multisig storage structure.
     * @param _allVoters The array of allowed voter identifiers.
     * @param _proposalId The proposal identifier.
     */
    function _confirm(ISafeMinimalMultisig.Storage storage s, bytes32[] memory _allVoters, uint256 _proposalId) internal {
        bytes32 voter = LibCryptoLegacy._addressToHash(msg.sender);
        ISafeMinimalMultisig.Proposal storage p = s.proposals[_proposalId];
        if (p.executed) {
            revert ISafeMinimalMultisig.MultisigAlreadyExecuted();
        }
        if (s.confirmedBy[_proposalId][voter]) {
            revert ISafeMinimalMultisig.MultisigAlreadyConfirmed();
        }
        _checkIsVoterAllowed(_allVoters, voter);

        s.confirmedBy[_proposalId][voter] = true;
        p.confirms = _getConfirmedCount(s, _allVoters, _proposalId);

        emit ISafeMinimalMultisig.ConfirmSafeMinimalMultisigProposal(_proposalId, voter, s.requiredConfirmations, p.confirms);

        if (p.confirms >= s.requiredConfirmations) {
            _execute(s, voter, _proposalId);
        }
    }

    /**
     * @notice Executes a multisig proposal that has met the required confirmation threshold.
     * @dev Sets the proposal as executed and then attempts to perform the proposed action via a low-level call.
     * Reverts with ISafeMinimalMultisig.MultisigExecutionFailed if the execution call fails.
     * Emits the ExecuteSafeMinimalMultisigProposal event.
     * @param s The multisig storage structure.
     * @param _voter The voter identifier triggering the execution.
     * @param _proposalId The proposal identifier.
     */
    function _execute(ISafeMinimalMultisig.Storage storage s, bytes32 _voter, uint256 _proposalId) private {
        ISafeMinimalMultisig.Proposal storage p = s.proposals[_proposalId];
        p.executed = true;

        (bool success, bytes memory data) = address(this).call(abi.encodePacked(p.selector, p.params));
        if (!success) {
            revert ISafeMinimalMultisig.MultisigExecutionFailed();
        }

        emit ISafeMinimalMultisig.ExecuteSafeMinimalMultisigProposal(_proposalId, _voter, success, data);
    }
}