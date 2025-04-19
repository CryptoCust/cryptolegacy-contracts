// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./plugins/LensPlugin.sol";
import "./interfaces/ICryptoLegacy.sol";
import "./interfaces/ICryptoLegacyLens.sol";
import "./interfaces/ITrustedGuardiansPlugin.sol";
import {CryptoLegacyBasePlugin} from "./plugins/CryptoLegacyBasePlugin.sol";

/**
 * @title CryptoLegacyLensForwarder
 * @notice A lens contract that forwards all getter calls to a specified CryptoLegacy diamond contract.
 * Each function takes the target contract address as the first argument and then calls the ready-made
 * getter on that contract. This way, we use all existing structures and logic without any duplication.
 */
contract CryptoLegacyExternalLens {
    function isLifetimeActive(address _cryptoLegacy) external view returns (bool) {
        return CryptoLegacyBasePlugin(_cryptoLegacy).isLifetimeActive();
    }
    function isPaused(address _cryptoLegacy) external view returns (bool) {
        return CryptoLegacyBasePlugin(_cryptoLegacy).isPaused();
    }
    function buildManager(address _cryptoLegacy) external view returns (address) {
        return address(ICryptoLegacy(_cryptoLegacy).buildManager());
    }
    function owner(address _cryptoLegacy) external view returns (address) {
        return address(ICryptoLegacy(_cryptoLegacy).owner());
    }

    function _baseData(address _cryptoLegacy) internal view returns(ICryptoLegacyLens.CryptoLegacyBaseData memory) {
        return ICryptoLegacyLens(_cryptoLegacy).getCryptoLegacyBaseData();
    }

    function _listTokensData(address _cryptoLegacy, address[] memory _tokens) internal view returns(ICryptoLegacyLens.CryptoLegacyListData memory) {
        return ICryptoLegacyLens(_cryptoLegacy).getCryptoLegacyListData(_tokens);
    }

    function updateInterval(address _cryptoLegacy) external view returns (uint64) {
        return LensPlugin(_cryptoLegacy).updateInterval();
    }

    function challengeTimeout(address _cryptoLegacy) external view returns (uint64) {
        return LensPlugin(_cryptoLegacy).challengeTimeout();
    }

    function distributionStartAt(address _cryptoLegacy) external view returns (uint64) {
        return LensPlugin(_cryptoLegacy).distributionStartAt();
    }

    function lastFeePaidAt(address _cryptoLegacy) external view returns (uint64) {
        return LensPlugin(_cryptoLegacy).lastFeePaidAt();
    }

    function lastUpdateAt(address _cryptoLegacy) external view returns (uint64) {
        return LensPlugin(_cryptoLegacy).lastUpdateAt();
    }

    function initialFeeToPay(address _cryptoLegacy) external view returns (uint128) {
        return LensPlugin(_cryptoLegacy).initialFeeToPay();
    }

    function updateFee(address _cryptoLegacy) external view returns (uint128) {
        return LensPlugin(_cryptoLegacy).updateFee();
    }

    function invitedByRefCode(address _cryptoLegacy) external view returns (bytes8) {
        return LensPlugin(_cryptoLegacy).invitedByRefCode();
    }

    function getBeneficiaries(address _cryptoLegacy)
    external
    view
    returns (bytes32[] memory hashes, bytes32[] memory originalHashes, ICryptoLegacy.BeneficiaryConfig[] memory configs)
    {
        return LensPlugin(_cryptoLegacy).getBeneficiaries();
    }

    function getTokensDistribution(address _cryptoLegacy, address[] calldata _tokens)
    external
    view
    returns (ICryptoLegacy.TokenDistribution[] memory list)
    {
        return LensPlugin(_cryptoLegacy).getTokensDistribution(_tokens);
    }

    function getCryptoLegacyBaseData(address _cryptoLegacy)
    external
    view
    returns (ICryptoLegacyLens.CryptoLegacyBaseData memory data)
    {
        return _baseData(_cryptoLegacy);
    }

    function getCryptoLegacyListData(address _cryptoLegacy, address[] memory _tokens)
    external
    view
    returns (ICryptoLegacyLens.CryptoLegacyListData memory data)
    {
        return _listTokensData(_cryptoLegacy, _tokens);
    }

    function getMessagesBlockNumbersByRecipient(address _cryptoLegacy, bytes32 _recipient)
    external
    view
    returns (uint64[] memory blockNumbers)
    {
        return ICryptoLegacyLens(_cryptoLegacy).getMessagesBlockNumbersByRecipient(_recipient);
    }

    function getTransferBlockNumbers(address _cryptoLegacy)
    external
    view
    returns (uint64[] memory blockNumbers)
    {
        return LensPlugin(_cryptoLegacy).getTransferBlockNumbers();
    }

    function getVestedAndClaimedData(
        address _cryptoLegacy,
        bytes32 _beneficiary,
        address[] calldata _tokens
    ) external view returns (ICryptoLegacyLens.BeneficiaryTokenData[] memory result, uint64 startDate, uint64 endDate) {
        return ICryptoLegacyLens(_cryptoLegacy).getVestedAndClaimedData(_beneficiary, _tokens);
    }

    function getPluginInfoList(address _cryptoLegacy)
    external
    view
    returns (ICryptoLegacyLens.PluginInfo[] memory)
    {
        return LensPlugin(_cryptoLegacy).getPluginInfoList();
    }

    function getCryptoLegacyListWithStatuses(IBeneficiaryRegistry _beneficiaryRegistry, bytes32 _hash)
    external
    view
    returns (
        address[] memory listByBeneficiary,
        bool[] memory beneficiaryDefaultGuardian,
        address[] memory listByOwner,
        address[] memory listByGuardian,
        address[] memory listByRecovery
    )
    {
        (listByBeneficiary, listByOwner, listByGuardian, listByRecovery) = _beneficiaryRegistry.getAllCryptoLegacyListByRoles(_hash);
        uint256 len = listByBeneficiary.length;
        beneficiaryDefaultGuardian = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            try ITrustedGuardiansPlugin(listByBeneficiary[i]).isGuardiansInitialized() returns(bool isInitialized) {
                beneficiaryDefaultGuardian[i] = !isInitialized;
            } catch {}
        }
    }
}