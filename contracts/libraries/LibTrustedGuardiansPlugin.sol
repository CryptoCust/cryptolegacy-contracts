/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "../interfaces/ICryptoLegacy.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";
import "../interfaces/ITrustedGuardiansPlugin.sol";
import "./LibCryptoLegacy.sol";

library LibTrustedGuardiansPlugin {
    bytes32 internal constant PLUGIN_POSITION = keccak256("trusted_guardians.plugin.storage");

    /**
     * @notice Retrieves the storage structure used by the Trusted Guardians plugin.
     * @dev Uses a fixed storage slot defined by the PLUGIN_POSITION constant. This pattern
     * is used for upgradeable contracts to avoid storage collisions.
     * @return storageStruct A reference to the PluginStorage struct for the Trusted Guardians plugin.
     */
    function getPluginStorage() internal pure returns (ITrustedGuardiansPlugin.PluginStorage storage storageStruct) {
        bytes32 position = PLUGIN_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }

    /**
     * @notice Resets the guardian voting process.
     * @dev Clears the list of guardians who have voted by assigning a new empty bytes32 array to the
     * guardiansVoted field in the Trusted Guardians Plugin storage. Additionally, it resets the distribution
     * start timestamp in the CryptoLegacy storage to zero, effectively restarting the voting process.
     * Emits a ResetGuardiansVoting event to signal that the guardian voting has been reset.
     * @param cls The CryptoLegacy storage structure used to manage the distribution start time.
     */
    function _resetGuardianVoting(ICryptoLegacy.CryptoLegacyStorage storage cls) internal {
        ITrustedGuardiansPlugin.PluginStorage storage pluginStorage = LibTrustedGuardiansPlugin.getPluginStorage();
        pluginStorage.guardiansVoted = new bytes32[](0);

        cls.distributionStartAt = uint64(0);
        emit ITrustedGuardiansPlugin.ResetGuardiansVoting();
    }
}