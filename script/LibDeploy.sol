/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "../contracts/FeeRegistry.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/ProxyBuilder.sol";
import "../contracts/Create3Factory.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/ProxyBuilderAdmin.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/SignatureRoleTimelock.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/plugins/LegacyRecoveryPlugin.sol";
import "../contracts/plugins/CryptoLegacyBasePlugin.sol";
import "../contracts/plugins/TrustedGuardiansPlugin.sol";

library LibDeploy {
    event LifetimeNftStatus(bool deployed);
    event PluginAddResult(bool success);

    string internal constant CryptoLegacyBuildManagerName = "CryptoLegacyBuildManager";
    string internal constant BeneficiaryRegistryName = "BeneficiaryRegistry";
    string internal constant CryptoLegacyExternalLensName = "CryptoLegacyExternalLens";
    string internal constant CryptoLegacyFactoryName = "CryptoLegacyFactory";
    string internal constant LegacyMessengerName = "LegacyMessenger";
    string internal constant FeeRegistryName = "FeeRegistry";
    string internal constant FeeRegistryProxyName = "FeeRegistryProxy";
    string internal constant LifetimeNftName = "LifetimeNft";
    string internal constant SignatureRoleTimelockName = "SignatureRoleTimelock";
    string internal constant CryptoLegacyName = "CryptoLegacy";
    string internal constant ProxyBuilderAdminName = "ProxyBuilderAdmin";
    string internal constant ProxyBuilderName = "ProxyBuilder";
    string internal constant PluginsRegistryName = "PluginsRegistry";
    string internal constant CryptoLegacyBasePluginName = "CryptoLegacyBasePlugin";
    string internal constant LensPluginName = "LensPlugin";
    string internal constant TrustedGuardiansPluginName = "TrustedGuardiansPlugin";
    string internal constant LegacyRecoveryPluginName = "LegacyRecoveryPlugin";

    function _getNftMainnetId() internal pure returns(uint128) {
        return 1;
    }
    function _getRefMainnetId() internal pure returns(uint128) {
        return 42161;
    }
    function _getDefaultTimelock() internal pure returns(uint128) {
        return 5 days;
    }
    function _getMsig1Role() internal pure returns(bytes32) {
        return stringToHash("MultiSig1");
    }
    function _getMsig2Role() internal pure returns(bytes32) {
        return stringToHash("MultiSig2");
    }
    function _getMsig3Role() internal pure returns(bytes32) {
        return stringToHash("MultiSig3");
    }

    function _deployCreate3Factory(bytes32 _salt, address _owner) internal returns(Create3Factory factory){
        factory = new Create3Factory{salt: _salt}(_owner);
    }

    function _deployBuildManager(Create3Factory _factory, bytes32 _salt, address _owner, FeeRegistry _feeRegistry, PluginsRegistry _pluginRegistry, LifetimeNft _lifetimeNft) internal returns(CryptoLegacyBuildManager buildManager, BeneficiaryRegistry beneficiaryRegistry, CryptoLegacyFactory factory){
        (beneficiaryRegistry, factory) = _beforeDeployBuildManager(_factory, _salt, _owner);
        buildManager = CryptoLegacyBuildManager(payable(c3(
            _factory,
            _salt,
            CryptoLegacyBuildManagerName,
            cryptoLegacyBuildManagerBytecode(_owner, _feeRegistry, _pluginRegistry, beneficiaryRegistry, _lifetimeNft, factory)
        )));

        _afterDeployBuildManager( buildManager);
    }

    function _beforeDeployBuildManager(Create3Factory _factory, bytes32 _salt, address _owner) private returns(BeneficiaryRegistry beneficiaryRegistry, CryptoLegacyFactory factory){
        beneficiaryRegistry = _deployBeneficiaryRegistry(_factory, _salt, _owner);
        factory = _deployFactory(_factory, _salt, _owner);
    }

    function _afterDeployBuildManager(CryptoLegacyBuildManager buildManager) internal {
        buildManager.factory().setBuildOperator(address(buildManager), true);
        ILifetimeNft lifeNft = buildManager.lifetimeNft();
        (bool ok, ) = address(lifeNft).call(
            abi.encodeWithSelector(ILifetimeNft.setMinterOperator.selector, buildManager, true)
        );
        emit LifetimeNftStatus(ok);
        BuildManagerOwnable(address(buildManager.beneficiaryRegistry())).setBuildManager(address(buildManager), true);
    }

    function _deployBeneficiaryRegistry(Create3Factory _factory, bytes32 _salt, address _owner) internal returns(BeneficiaryRegistry beneficiaryRegistry) {
        beneficiaryRegistry = BeneficiaryRegistry(c3(
            _factory,
            _salt,
            BeneficiaryRegistryName,
            contractWithOwnerBytecode(type(BeneficiaryRegistry).creationCode, _owner)
        ));
    }

    function _updateBuildManagerRegistries(CryptoLegacyBuildManager buildManager, FeeRegistry _feeRegistry, PluginsRegistry _pluginRegistry, BeneficiaryRegistry _beneficiaryRegistry) internal {
        buildManager.setRegistries(_feeRegistry, _pluginRegistry, _beneficiaryRegistry);
    }

    function _deployExternalLens(Create3Factory _factory, bytes32 _salt, CryptoLegacyBuildManager buildManager) internal {
        CryptoLegacyExternalLens externalLens = CryptoLegacyExternalLens(c3(
            _factory,
            _salt,
            CryptoLegacyExternalLensName,
            type(CryptoLegacyExternalLens).creationCode
        ));
        buildManager.setExternalLens(address(externalLens));
    }

    function _deployFactory(Create3Factory _factory, bytes32 _salt, address _owner) internal returns(CryptoLegacyFactory) {
        return CryptoLegacyFactory(c3(
            _factory,
            _salt,
            CryptoLegacyFactoryName,
            contractWithOwnerBytecode(type(CryptoLegacyFactory).creationCode, _owner)
        ));
    }

    function _deployLegacyMessenger(Create3Factory _factory, bytes32 _salt, address _owner, CryptoLegacyBuildManager buildManager) internal returns(LegacyMessenger legacyMessenger){
        legacyMessenger = LegacyMessenger(c3(
            _factory,
            _salt,
            LegacyMessengerName,
            contractWithOwnerBytecode(type(LegacyMessenger).creationCode, _owner)
        ));
        _initLegacyMessenger(legacyMessenger, buildManager);
    }

    function _initLegacyMessenger(LegacyMessenger _legacyMessenger, CryptoLegacyBuildManager buildManager) internal{
        _legacyMessenger.setBuildManager(address(buildManager), true);
    }

    function _initFeeRegistry(FeeRegistry _feeRegistry, CryptoLegacyBuildManager _buildManager, uint128 _lifetimeFee, uint128 _buildFee, uint128 _updateFee) internal {
        uint8 REGISTRY_BUILD_CASE = 1;
        uint8 REGISTRY_UPDATE_CASE = 2;
        uint8 REGISTRY_LIFETIME_CASE = 3;
        _feeRegistry.setContractCaseFee(address(_buildManager), REGISTRY_LIFETIME_CASE, _lifetimeFee);
        _feeRegistry.setContractCaseFee(address(_buildManager), REGISTRY_BUILD_CASE, _buildFee);
        _feeRegistry.setContractCaseFee(address(_buildManager), REGISTRY_UPDATE_CASE, _updateFee);

        _feeRegistry.setLockOperator(address(_buildManager), true);

        if (_getRefMainnetId() == block.chainid) {
            _feeRegistry.setCodeOperator(address(_buildManager), true);
        }
    }

    function _transferOwnership(address _owner, CryptoLegacyBuildManager _buildManager, ProxyBuilder _proxyBuilder) internal {
        Ownable(address(_buildManager.feeRegistry())).transferOwnership(_owner);
        Ownable(address(_buildManager.pluginsRegistry())).transferOwnership(_owner);
        Ownable(address(_buildManager.beneficiaryRegistry())).transferOwnership(_owner);

        (bool ok, ) = address(_buildManager.lifetimeNft()).call(
            abi.encodeWithSelector(Ownable.transferOwnership.selector, _owner)
        );
        emit LifetimeNftStatus(ok);
        Ownable(address(_buildManager.factory())).transferOwnership(_owner);
        _buildManager.transferOwnership(_owner);
        _proxyBuilder.transferOwnership(_owner);
        _proxyBuilder.proxyAdmin().transferOwnership(_owner);
    }

    function _transferOwnershipWithLm(address _owner, CryptoLegacyBuildManager _buildManager, ProxyBuilder _proxyBuilder, LegacyMessenger _lm) internal {
        _transferOwnership(_owner, _buildManager, _proxyBuilder);
        _lm.transferOwnership(_owner);
    }

    function _deployZeroCryptoLegacy(Create3Factory _factory, bytes32 _salt) internal returns(CryptoLegacy clToVerify) {
        clToVerify = CryptoLegacy(payable(c3(
            _factory,
            _salt,
            CryptoLegacyName,
            cryptoLegacyBytecode(address(0), address(0), new address[](0))
        )));
    }

    function _deployProxyBuilder(Create3Factory _factory, bytes32 _salt, address _owner) internal returns (ProxyBuilder proxyBuilder) {
        ProxyBuilderAdmin proxyAdmin = ProxyBuilderAdmin(c3(
            _factory,
            _salt,
            ProxyBuilderAdminName,
            contractWithOwnerBytecode(type(ProxyBuilderAdmin).creationCode, _owner)
        ));
        proxyBuilder = ProxyBuilder(c3(
            _factory,
            _salt,
            ProxyBuilderName,
            proxyBuilderBytecode(_owner, address(proxyAdmin))
        ));
    }

    function _deployPluginsRegistry(Create3Factory _factory, bytes32 _salt, address _owner) internal returns(PluginsRegistry pluginsRegistry) {
        pluginsRegistry = PluginsRegistry(c3(
            _factory,
            _salt,
            PluginsRegistryName,
            contractWithOwnerBytecode(type(PluginsRegistry).creationCode, _owner)
        ));
    }

    function _deployPluginsRegistryAndSet(Create3Factory _factory, bytes32 _salt, address _owner) internal returns(PluginsRegistry pluginsRegistry) {
        pluginsRegistry = _deployPluginsRegistry(_factory, _salt, _owner);
        _deployAndSetPlugins(_factory, _salt, pluginsRegistry);
    }

    function _deployAndSetPlugins(Create3Factory _factory, bytes32 _salt, PluginsRegistry pluginsRegistry) internal {
        (address basePlugin, address lensPlugin, address tgPlugin, address lrPlugin) = _deployPlugins(_factory, _salt);
        pluginsRegistry.addPlugin(basePlugin, "");
        pluginsRegistry.addPlugin(lensPlugin, "");
        pluginsRegistry.addPlugin(tgPlugin, "");
        pluginsRegistry.addPlugin(lrPlugin, "");
    }

    function _deployPlugins(Create3Factory _factory, bytes32 _salt) internal returns(address basePlugin, address lensPlugin, address tgPlugin, address lrPlugin) {
        basePlugin = c3(_factory, _salt, CryptoLegacyBasePluginName, type(CryptoLegacyBasePlugin).creationCode);
        lensPlugin = c3(_factory, _salt, LensPluginName, type(LensPlugin).creationCode);
        tgPlugin = c3(_factory, _salt, TrustedGuardiansPluginName, type(TrustedGuardiansPlugin).creationCode);
        lrPlugin = c3(_factory, _salt, LegacyRecoveryPluginName, type(LegacyRecoveryPlugin).creationCode);
    }

    function _signatureMsig1(address _target, bytes4 _selector) internal pure returns(ISignatureRoleTimelock.SignatureToAdd memory) {
        return ISignatureRoleTimelock.SignatureToAdd(_target, _selector, _getMsig1Role(), _getDefaultTimelock());
    }

    function _signatureZeroDaysMsig1(address _target, bytes4 _selector) internal pure returns(ISignatureRoleTimelock.SignatureToAdd memory) {
        return ISignatureRoleTimelock.SignatureToAdd(_target, _selector, _getMsig1Role(), 1);
    }

    function _signatureMsig2(address _target, bytes4 _selector) internal pure returns(ISignatureRoleTimelock.SignatureToAdd memory) {
        return ISignatureRoleTimelock.SignatureToAdd(_target, _selector, _getMsig2Role(), _getDefaultTimelock());
    }

    function _signatureZeroDaysMsig2(address _target, bytes4 _selector) internal pure returns(ISignatureRoleTimelock.SignatureToAdd memory) {
        return ISignatureRoleTimelock.SignatureToAdd(_target, _selector, _getMsig2Role(), 1);
    }

    function _signatureMsig3(address _target, bytes4 _selector) internal pure returns(ISignatureRoleTimelock.SignatureToAdd memory) {
        return ISignatureRoleTimelock.SignatureToAdd(_target, _selector, _getMsig3Role(), _getDefaultTimelock());
    }

    function getAddressRoles(address _msig1, address _msig2, address _msig3) internal pure returns(ISignatureRoleTimelock.AddressRoleInput[] memory addressRoles) {
        addressRoles = new ISignatureRoleTimelock.AddressRoleInput[](3);
        addressRoles[0] = ISignatureRoleTimelock.AddressRoleInput(_getMsig1Role(), _msig1, address(0));
        addressRoles[1] = ISignatureRoleTimelock.AddressRoleInput(_getMsig2Role(), _msig2, address(0));
        addressRoles[2] = ISignatureRoleTimelock.AddressRoleInput(_getMsig3Role(), _msig3, address(0));
    }

    function getSignatureRoleTimeLockSigsLength(ILifetimeNft lifetimeNft) internal view returns(uint256) {
        (bool lifetimeNftExist, ) = address(lifetimeNft).staticcall(abi.encodeWithSelector(IERC721Enumerable.totalSupply.selector));
        return lifetimeNftExist ? 40 : 38;
    }

    function _deploySignatureRoleTimelock(Create3Factory _factory, bytes32 _salt, CryptoLegacyBuildManager _buildManager, ProxyBuilder _proxyBuilder, LegacyMessenger _legacyMessenger, address _msig1, address _msig2, address _msig3) internal returns(SignatureRoleTimelock signatureRoleTimelock) {
        FeeRegistry feeRegistry = FeeRegistry(address(_buildManager.feeRegistry()));

        //TODO: withdraw fee to msig2
        //TODO: transfer ownership to msig1
        BeneficiaryRegistry beneficiaryRegistry = BeneficiaryRegistry(address(_buildManager.beneficiaryRegistry()));

        uint256 arrLength = getSignatureRoleTimeLockSigsLength(_buildManager.lifetimeNft());
        ISignatureRoleTimelock.SignatureToAdd[] memory sigs = new ISignatureRoleTimelock.SignatureToAdd[](arrLength);
        sigs[0] = _signatureMsig3(address(beneficiaryRegistry), beneficiaryRegistry.setBuildManager.selector);
        sigs[1] = _signatureMsig1(address(beneficiaryRegistry), beneficiaryRegistry.transferOwnership.selector);
        sigs[2] = _signatureMsig3(address(_legacyMessenger), _legacyMessenger.setBuildManager.selector);
        sigs[3] = _signatureMsig1(address(_legacyMessenger), _legacyMessenger.transferOwnership.selector);
        sigs[4] = _signatureMsig3(address(_buildManager), _buildManager.setRegistries.selector);
        sigs[5] = _signatureMsig3(address(_buildManager), _buildManager.setFactory.selector);
        sigs[6] = _signatureMsig2(address(_buildManager), _buildManager.setSupplyLimit.selector);
        sigs[7] = _signatureMsig2(address(_buildManager), _buildManager.setExternalLens.selector);
        sigs[8] = _signatureMsig2(address(_buildManager), _buildManager.withdrawFee.selector);
        sigs[9] = _signatureMsig2(address(_buildManager), _buildManager.transferStuckNft.selector);
        sigs[10] = _signatureMsig1(address(_buildManager), _buildManager.transferOwnership.selector);
        sigs[11] = _signatureMsig3(address(_buildManager.factory()), _buildManager.factory().setBuildOperator.selector);
        sigs[12] = _signatureMsig1(address(_buildManager.factory()), _buildManager.transferOwnership.selector);
        sigs[13] = _signatureMsig2(address(feeRegistry), feeRegistry.setCodeOperator.selector);
        sigs[14] = _signatureMsig2(address(feeRegistry), feeRegistry.setSupportedRefCodeInChains.selector);
        sigs[15] = _signatureMsig2(address(feeRegistry), feeRegistry.setFeeBeneficiaries.selector);
        sigs[16] = _signatureMsig2(address(feeRegistry), feeRegistry.setDefaultPct.selector);
        sigs[17] = _signatureZeroDaysMsig2(address(feeRegistry), feeRegistry.setRefererSpecificPct.selector);
        sigs[18] = _signatureMsig2(address(feeRegistry), feeRegistry.setContractCaseFee.selector);
        sigs[19] = _signatureMsig3(address(feeRegistry), feeRegistry.setDebridgeGate.selector);
        sigs[20] = _signatureMsig2(address(feeRegistry), feeRegistry.setDebridgeNativeFee.selector);
        sigs[21] = _signatureMsig2(address(feeRegistry), feeRegistry.setDestinationChainContract.selector);
        sigs[22] = _signatureMsig2(address(feeRegistry), feeRegistry.setSourceChainContract.selector);
        sigs[23] = _signatureMsig2(address(feeRegistry), feeRegistry.setSourceAndDestinationChainContract.selector);
        sigs[24] = _signatureMsig2(address(feeRegistry), feeRegistry.setLockPeriod.selector);
        sigs[25] = _signatureMsig2(address(feeRegistry), feeRegistry.setLockOperator.selector);
        sigs[26] = _signatureZeroDaysMsig2(address(feeRegistry), feeRegistry.setReferralCode.selector);
        sigs[27] = _signatureMsig2(address(feeRegistry), feeRegistry.setCustomChainId.selector);
        sigs[28] = _signatureMsig1(address(feeRegistry), feeRegistry.transferOwnership.selector);
        sigs[29] = _signatureMsig3(address(_buildManager.pluginsRegistry()), _buildManager.pluginsRegistry().addPlugin.selector);
        sigs[30] = _signatureMsig3(address(_buildManager.pluginsRegistry()), _buildManager.pluginsRegistry().addPluginDescription.selector);
        sigs[31] = _signatureMsig3(address(_buildManager.pluginsRegistry()), _buildManager.pluginsRegistry().removePlugin.selector);
        sigs[32] = _signatureMsig1(address(_buildManager.pluginsRegistry()), _buildManager.transferOwnership.selector);
        sigs[33] = _signatureMsig3(address(_proxyBuilder.proxyAdmin()), _proxyBuilder.proxyAdmin().upgrade.selector);
        sigs[34] = _signatureMsig3(address(_proxyBuilder.proxyAdmin()), _proxyBuilder.proxyAdmin().upgradeAndCall.selector);
        sigs[35] = _signatureMsig3(address(_proxyBuilder.proxyAdmin()), _proxyBuilder.proxyAdmin().changeProxyAdmin.selector);
        sigs[36] = _signatureMsig1(address(_proxyBuilder.proxyAdmin()), _proxyBuilder.proxyAdmin().transferOwnership.selector);
        if (arrLength == 40) {
            sigs[37] = _signatureZeroDaysMsig2(address(_buildManager.lifetimeNft()), _buildManager.lifetimeNft().setBaseUri.selector);
            sigs[38] = _signatureMsig3(address(_buildManager.lifetimeNft()), _buildManager.lifetimeNft().setMinterOperator.selector);
            sigs[39] = _signatureMsig1(address(_buildManager.lifetimeNft()), _buildManager.transferOwnership.selector);
        }
        signatureRoleTimelock = SignatureRoleTimelock(c3(
            _factory,
            _salt,
            SignatureRoleTimelockName,
            signatureRoleTimelockBytecode(1, getAddressRoles(_msig1, _msig2, _msig3), sigs, _msig1)
        ));
    }

    function _initMultisigRights(FeeRegistry _feeRegistry, address _msig2) internal {
        IFeeRegistry.FeeBeneficiary[] memory feeBeneficiaries = new IFeeRegistry.FeeBeneficiary[](1);
        feeBeneficiaries[0] = IFeeRegistry.FeeBeneficiary(_msig2, 10000);
        _feeRegistry.setFeeBeneficiaries(feeBeneficiaries);
    }

    function _deployLifeTimeNft(Create3Factory _factory, bytes32 _salt, address _owner) internal returns(LifetimeNft lifetimeNft) {
        lifetimeNft = LifetimeNft(c3(
            _factory,
            _salt,
            LifetimeNftName,
            lifetimeNftBytecode("CryptoLegacy Life Pass", "LIFE", "", _owner)
        ));
    }

    function _lifetimeNftPredictedAddress(Create3Factory _factory, bytes32 _salt) internal view returns(address) {
        return _factory.computeAddress(contractSalt(LifetimeNftName, _salt));
    }

    function _deployFeeRegistry(Create3Factory _factory, bytes32 _salt, bytes32 _proxySalt, address _owner, ProxyBuilder proxyBuilder, uint32 _defaultDiscountPct, uint32 _defaultSharePct, ILifetimeNft _lifetimeNft, uint64 _lockPeriod, uint64 _transferTimeout) internal returns(FeeRegistry feeRegistry) {
        address implementation = c3(_factory, _salt, FeeRegistryName, type(FeeRegistry).creationCode);

        bytes32 feeRegistryProxySalt = contractSalt(FeeRegistryProxyName, _proxySalt);
        address create3Address = proxyBuilder.computeAddress(feeRegistryProxySalt);

        bytes memory initData = feeRegistryInitialize(_owner, _defaultDiscountPct, _defaultSharePct, _lifetimeNft, _lockPeriod, _transferTimeout);
        address proxy = proxyBuilder.build(create3Address, feeRegistryProxySalt, implementation, initData);

        return FeeRegistry(proxy);
    }

    function _upgradeFeeRegistry(Create3Factory _factory, bytes32 _salt, FeeRegistry _feeRegistry, ProxyBuilder proxyBuilder) internal {
        address implementation = c3(_factory, _salt, FeeRegistryName, type(FeeRegistry).creationCode);
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(address(_feeRegistry)));
        proxyBuilder.proxyAdmin().upgrade(proxy, implementation);
    }

    function _setFeeRegistryCrossChains(FeeRegistry _feeRegistry) internal {
        uint256[] memory crossChainIds;
        address defaultDeBridge = 0x43dE2d77BF8027e25dBD179B491e8d64f38398aA;

        if (block.chainid == _getNftMainnetId() || block.chainid == _getRefMainnetId()) {
            _feeRegistry.setDebridgeGate(defaultDeBridge);

            crossChainIds = new uint256[](4);
            crossChainIds[0] = block.chainid == _getNftMainnetId() ? _getRefMainnetId() : _getNftMainnetId();
            crossChainIds[1] = 59144; // Linea
            crossChainIds[2] = 8453; // Base
            crossChainIds[3] = 10; // Optimism
        } else {
            crossChainIds = new uint256[](2);
            crossChainIds[0] = _getNftMainnetId();
            crossChainIds[1] = _getRefMainnetId();
        }
        if (block.chainid == 59144) { // linea
            _feeRegistry.setDebridgeGate(defaultDeBridge);
        }
        if (block.chainid == 8453) { // base
            _feeRegistry.setDebridgeGate(0xc1656B63D9EEBa6d114f6bE19565177893e5bCBF);
        }
        if (block.chainid == 10) { // optimism
            _feeRegistry.setDebridgeGate(defaultDeBridge);
        }
        for (uint256 i = 0; i < crossChainIds.length; i++) {
            _feeRegistry.setSourceAndDestinationChainContract(crossChainIds[i], address(_feeRegistry));
        }
    }

    function feeRegistryInitialize(
        address _owner,
        uint32 _defaultDiscountPct,
        uint32 _defaultSharePct,
        ILifetimeNft _lifetimeNft,
        uint64 _lockPeriod,
        uint64 _transferTimeout
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            FeeRegistry.initialize.selector,
            _owner,
            _defaultDiscountPct,
            _defaultSharePct,
            address(_lifetimeNft),
            _lockPeriod,
            _transferTimeout
        );
    }

    function contractSalt(string memory _contractName, bytes32 _salt) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(_contractName, _salt));
    }

    function c3(Create3Factory _factory, bytes32 _salt, string memory _contractName, bytes memory _creationCode) internal returns(address){
        return _factory.build(contractSalt(_contractName, _salt), _creationCode);
    }

    function cryptoLegacyBuildManagerBytecode(
        address _owner,
        IFeeRegistry _feeRegistry,
        IPluginsRegistry _pluginsRegistry,
        IBeneficiaryRegistry _beneficiaryRegistry,
        ILifetimeNft _lifetimeNft,
        ICryptoLegacyFactory _factory
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(CryptoLegacyBuildManager).creationCode,
            abi.encode(_owner, _feeRegistry, _pluginsRegistry, _beneficiaryRegistry, _lifetimeNft, _factory)
        );
    }

    function cryptoLegacyBytecode(
        address _buildManager,
        address _owner,
        address[] memory _plugins
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(CryptoLegacy).creationCode,
            abi.encode(_buildManager, _owner, _plugins)
        );
    }

    function proxyBuilderBytecode(address _owner, address _proxyAdmin) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(ProxyBuilder).creationCode,
            abi.encode(_owner, _proxyAdmin)
        );
    }

    function signatureRoleTimelockBytecode(
        uint128 _adminTimelock,
        ISignatureRoleTimelock.AddressRoleInput[] memory _roles,
        ISignatureRoleTimelock.SignatureToAdd[] memory _sigs,
        address _adminAccount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(SignatureRoleTimelock).creationCode,
            abi.encode(_adminTimelock, _roles, _sigs, _adminAccount)
        );
    }

    function lifetimeNftBytecode(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address _owner
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(LifetimeNft).creationCode,
            abi.encode(name_, symbol_, baseURI_, _owner)
        );
    }

    function contractWithOwnerBytecode(bytes memory _creationCode, address _owner) internal pure returns (bytes memory) {
        return abi.encodePacked(_creationCode, abi.encode(_owner));
    }

    function stringToHash(string memory _str) internal pure returns(bytes32) {
        return keccak256(abi.encode(_str));
    }
}