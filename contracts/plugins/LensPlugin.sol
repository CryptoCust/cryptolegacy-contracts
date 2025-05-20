/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../libraries/LibDiamond.sol";
import "../interfaces/ICryptoLegacy.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../interfaces/ICryptoLegacyLens.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title LensPlugin
 * @notice Offers a comprehensive, read-only view into the internal state of the CryptoLegacy contract. It exposes critical details such as fee parameters, update intervals, beneficiary configurations, and distribution data—ideal for dashboards and explorers.
*/
contract LensPlugin is ICryptoLegacyPlugin, ICryptoLegacyLens {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    function getSigs() public pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](20);
        sigs[0] = this.updateInterval.selector;
        sigs[1] = this.challengeTimeout.selector;
        sigs[2] = this.initialFeeToPay.selector;
        sigs[3] = this.updateFee.selector;
        sigs[4] = this.lastFeePaidAt.selector;
        sigs[5] = this.lastUpdateAt.selector;
        sigs[6] = this.distributionStartAt.selector;
        sigs[7] = this.invitedByRefCode.selector;
        sigs[8] = this.getTransferBlockNumbers.selector;
        sigs[9] = this.getBeneficiaries.selector;
        sigs[10] = this.getBeneficiaryConfig.selector;
        sigs[11] = this.getBeneficiaryClaimed.selector;
        sigs[12] = this.getOriginalBeneficiaryHash.selector;
        sigs[13] = this.getTokensDistribution.selector;
        sigs[14] = this.getMessagesBlockNumbersByRecipient.selector;
        sigs[15] = this.getVestedAndClaimedData.selector;
        sigs[16] = this.getPluginMetadata.selector;
        sigs[17] = this.getPluginInfoList.selector;
        sigs[18] = this.getCryptoLegacyBaseData.selector;
        sigs[19] = this.getCryptoLegacyListData.selector;
    }
    function getSetupSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](0);
    }
    function getPluginName() external pure returns (string memory) {
        return "lens";
    }
    function getPluginVer() external pure returns (uint16) {
        return uint16(1);
    }

    function updateInterval() external view returns(uint64) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.updateInterval;
    }

    function challengeTimeout() external view returns(uint64) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.challengeTimeout;
    }

    function distributionStartAt() external view returns(uint64) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.distributionStartAt;
    }

    function lastFeePaidAt() external view returns(uint64) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.lastFeePaidAt;
    }

    function lastUpdateAt() external view returns(uint64) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.lastUpdateAt;
    }

    function initialFeeToPay() external view returns(uint128) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.initialFeeToPay;
    }

    function updateFee() external view returns(uint128) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.updateFee;
    }

    function invitedByRefCode() external view returns(bytes8) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.invitedByRefCode;
    }

    /**
     * @notice Returns the total amount of tokens already claimed by a beneficiary for a specific token.
     * @param _beneficiary The beneficiary hash.
     * @param _token The address of the token.
     * @return The claimed amount.
     */
    function getBeneficiaryClaimed(bytes32 _beneficiary, address _token) external view returns(uint256) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.beneficiaryVesting[_beneficiary].tokenAmountClaimed[_token];
    }

    /**
     * @notice Retrieves the original beneficiary hash stored for a beneficiary.
     * @param _beneficiary The beneficiary hash.
     * @return The original beneficiary hash.
     */
    function getOriginalBeneficiaryHash(bytes32 _beneficiary) external view returns(bytes32) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.originalBeneficiaryHash[_beneficiary];
    }

    /**
    * @notice Retrieves the configuration for a given beneficiary.
     * @param _beneficiary The beneficiary hash.
     * @return The BeneficiaryConfig struct containing claim delay, vesting period, and share percentage.
     */
    function getBeneficiaryConfig(bytes32 _beneficiary) external view returns(ICryptoLegacy.BeneficiaryConfig memory) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.beneficiaryConfig[_beneficiary];
    }

    /**
     * @notice Retrieves the list of beneficiary identifiers and their configurations.
     * @return hashes An array of beneficiary hashes (keccak256 of beneficiary addresses).
     * @return originalHashes An array of original beneficiary hashes (keccak256 of beneficiary addresses).
     * @return configs An array of BeneficiaryConfig structs corresponding to each beneficiary.
     */
    function getBeneficiaries() external view returns(bytes32[] memory hashes, bytes32[] memory originalHashes, ICryptoLegacy.BeneficiaryConfig[] memory configs) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return _getBeneficiaries(cls);
    }

    function _getBeneficiaries(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(bytes32[] memory hashes, bytes32[] memory originalHashes, ICryptoLegacy.BeneficiaryConfig[] memory configs) {
        hashes = cls.beneficiaries.values();
        originalHashes = new bytes32[](hashes.length);
        configs = new ICryptoLegacy.BeneficiaryConfig[](hashes.length);
        for (uint256 i = 0; i < hashes.length; i++) {
            configs[i] = cls.beneficiaryConfig[hashes[i]];
            originalHashes[i] = cls.originalBeneficiaryHash[hashes[i]];
        }
    }

    /**
     * @notice Returns the block numbers when asset transfers occurred.
     * @return blockNumbers An array of block numbers.
     */
    function getTransferBlockNumbers() external view returns(uint64[] memory blockNumbers) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.transfersGotByBlockNumber;
    }

    /**
    * @notice Returns token distribution details for an array of tokens.
     * @param _tokens An array of ERC20 token addresses.
     * @return list An array of TokenDistribution structs that include the total amount to distribute and the total claimed amount.
     */
    function getTokensDistribution(address[] memory _tokens) external view returns(ICryptoLegacyLens.LensTokenDistribution[] memory list) {
        return _getTokensDistribution(_tokens);
    }

    /**
     * @notice Returns token distribution details for an array of tokens.
     * @param _tokens An array of ERC20 token addresses.
     * @return list An array of TokenDistribution structs that include the total amount to distribute and the total claimed amount.
     */
    function _getTokensDistribution(address[] memory _tokens) internal view returns(ICryptoLegacyLens.LensTokenDistribution[] memory list) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

        list = new LensTokenDistribution[](_tokens.length);
        for(uint256 i = 0; i < _tokens.length; i++) {
            ICryptoLegacy.TokenDistribution storage td = cls.tokenDistribution[_tokens[i]];
            list[i] = LensTokenDistribution(td.amountToDistribute, td.lastBalance, uint128(LibCryptoLegacy._getTotalClaimed(cls, _tokens[i])));
        }
    }

    /**
     * @notice Retrieves comprehensive data about the CryptoLegacy contract.
     * @return data A CryptoLegacyData struct containing fee details, update intervals, beneficiary list, and other settings.
     */
    function getCryptoLegacyBaseData() external view returns(CryptoLegacyBaseData memory data) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return CryptoLegacyBaseData(
            cls.initialFeeToPay,
            cls.updateFee,
            cls.updateInterval,
            cls.challengeTimeout,
            cls.lastFeePaidAt,
            cls.lastUpdateAt,
            cls.distributionStartAt,
            cls.invitedByRefCode,
            cls.defaultFuncDisabled,
            address(cls.buildManager)
        );
    }

    /**
     * @notice Retrieves comprehensive data about the CryptoLegacy contract.
     * @return data A CryptoLegacyListData struct containing beneficiary, transferBlockNumbers,  list, and other settings.
     */
    function getCryptoLegacyListData(address[] memory _tokens) external view returns(CryptoLegacyListData memory data) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        (bytes32[] memory beneficiaries, bytes32[] memory originalHashes, ICryptoLegacy.BeneficiaryConfig[] memory gotBeneficiaryConfigArr) = _getBeneficiaries(cls);
        return CryptoLegacyListData(
            beneficiaries,
            originalHashes,
            cls.transfersGotByBlockNumber,
            gotBeneficiaryConfigArr,
            _getPluginInfoList(cls),
            _getTokensDistribution(_tokens)
        );
    }

    /**
     * @notice Returns the block numbers when messages were received for a beneficiary.
     * @param _recipient The beneficiary hash.
     * @return blockNumbers An array of block numbers.
     */
    function getMessagesBlockNumbersByRecipient(bytes32 _recipient) external view returns(uint64[] memory blockNumbers) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        return cls.beneficiaryMessagesGotByBlockNumber[_recipient];
    }

    /**
     * @notice Calculates and returns the vested, claimed, and total distributable token amounts for a beneficiary.
     * @param _beneficiary The beneficiary hash.
     * @param _tokens An array of token addresses.
     * @return result An array of BeneficiaryTokenData structs.
     * @dev For each token, the vested amount is calculated as:
     *      vestedAmount = totalAmount * (min(currentTime - startDate, vestingPeriod) / vestingPeriod)
     *      where totalAmount = tokenDistribution.amountToDistribute * beneficiaryConfig.shareBps / 10000.
     */
    function getVestedAndClaimedData(bytes32 _beneficiary, address[] memory _tokens) external view returns(BeneficiaryTokenData[] memory result, uint64 startDate, uint64 endDate) {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

        result = new BeneficiaryTokenData[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            (ICryptoLegacy.BeneficiaryConfig storage bc, ICryptoLegacy.BeneficiaryVesting storage bv) = LibCryptoLegacy._getBeneficiaryConfigAndVesting(cls, _beneficiary);
            (startDate, endDate) = LibCryptoLegacy._getStartAndEndDate(cls, bc);
            ICryptoLegacy.TokenDistribution storage td = cls.tokenDistribution[_tokens[i]];
            (uint256 totalAmount, uint256 claimableAmount, ) = LibCryptoLegacy._getVestedAndClaimedAmount(td, bc, bv, _tokens[i], startDate, endDate);
            result[i] = BeneficiaryTokenData(claimableAmount, bv.tokenAmountClaimed[_tokens[i]], totalAmount);
        }
    }

    /**
     * @notice Retrieves metadata for all plugins currently attached to the CryptoLegacy contract.
     * @return An array of PluginInfo structs containing each plugin's address, name, and version.
     */
    function _getPluginInfoList(ICryptoLegacy.CryptoLegacyStorage storage cls) internal view returns(PluginInfo[] memory) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address[] memory addresses = ds.facetAddresses;
        PluginInfo[] memory plugins = new PluginInfo[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            (string memory name, uint16 version, uint64[] memory descriptionBlockNumbers) = _getPluginMetadata(cls, addresses[i]);
            plugins[i] = PluginInfo(addresses[i], name, version, descriptionBlockNumbers);
        }
        return plugins;
    }

    function _getPluginMetadata(ICryptoLegacy.CryptoLegacyStorage storage cls, address _plugin) internal view returns(string memory name, uint16 version, uint64[] memory descriptionBlockNumbers) {
        return (
            ICryptoLegacyPlugin(_plugin).getPluginName(),
            ICryptoLegacyPlugin(_plugin).getPluginVer(),
            cls.buildManager.pluginsRegistry().getPluginDescriptionBlockNumbers(_plugin)
        );
    }

    function getPluginInfoList() external view returns(PluginInfo[] memory) {
        return _getPluginInfoList(LibCryptoLegacy.getCryptoLegacyStorage());
    }

    function getPluginMetadata(address _plugin) external view returns(string memory name, uint16 version, uint64[] memory descriptionBlockNumbers) {
        return _getPluginMetadata(LibCryptoLegacy.getCryptoLegacyStorage(), _plugin);
    }
}