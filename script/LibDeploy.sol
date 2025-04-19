/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "../contracts/FeeRegistry.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/ProxyBuilder.sol";
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

    function _deployBuildManager(bytes32 _salt, address _owner, FeeRegistry _feeRegistry, PluginsRegistry _pluginRegistry, LifetimeNft _lifetimeNft) internal returns(CryptoLegacyBuildManager buildManager, BeneficiaryRegistry beneficiaryRegistry, CryptoLegacyFactory factory){
        (beneficiaryRegistry, factory) = _beforeDeployBuildManager(_salt, _owner);
        buildManager = new CryptoLegacyBuildManager{salt: _salt}(_owner, _feeRegistry, _pluginRegistry, beneficiaryRegistry, _lifetimeNft, factory);
        _afterDeployBuildManager( buildManager);
    }

    function _beforeDeployBuildManager(bytes32 _salt, address _owner) private returns(BeneficiaryRegistry beneficiaryRegistry, CryptoLegacyFactory factory){
        beneficiaryRegistry = new BeneficiaryRegistry{salt: _salt}(_owner);
        factory = _deployFactory(_salt, _owner);
    }

    function _afterDeployBuildManager(CryptoLegacyBuildManager buildManager) internal {
        buildManager.factory().setBuildOperator(address(buildManager), true);
        buildManager.lifetimeNft().setMinterOperator(address(buildManager), true);
        BuildManagerOwnable(address(buildManager.beneficiaryRegistry())).setBuildManager(address(buildManager), true);
    }

    function _updateBuildManagerRegistries(CryptoLegacyBuildManager buildManager, FeeRegistry _feeRegistry, PluginsRegistry _pluginRegistry, BeneficiaryRegistry _beneficiaryRegistry) internal {
        buildManager.setRegistries(_feeRegistry, _pluginRegistry, _beneficiaryRegistry);
    }

    function _deployExternalLens(bytes32 _salt, CryptoLegacyBuildManager buildManager) internal {
        CryptoLegacyExternalLens externalLens = new CryptoLegacyExternalLens{salt: _salt}();
        buildManager.setExternalLens(address(externalLens));
    }

    function _deployFactory(bytes32 _salt, address _owner) internal returns(CryptoLegacyFactory) {
        return new CryptoLegacyFactory{salt: _salt}(_owner);
    }

    function _deployLegacyMessenger(bytes32 _salt, address _owner, CryptoLegacyBuildManager buildManager) internal returns(LegacyMessenger legacyMessenger){
        legacyMessenger = new LegacyMessenger{salt: _salt}(_owner);
        _initLegacyMessenger(legacyMessenger, buildManager);
    }

    function _initLegacyMessenger(LegacyMessenger _legacyMessenger, CryptoLegacyBuildManager buildManager) internal{
        _legacyMessenger.setBuildManager(address(buildManager), true);
    }

    function _initFeeRegistry(FeeRegistry _feeRegistry, CryptoLegacyBuildManager _buildManager, uint128 _lifetimeFee, uint128 _buildFee, uint128 _updateFee, uint256 _refDiscountPct, uint256 _refSharePct) internal {
        uint8 REGISTRY_BUILD_CASE = 1;
        uint8 REGISTRY_UPDATE_CASE = 2;
        uint8 REGISTRY_LIFETIME_CASE = 3;
        _feeRegistry.setContractCaseFee(address(_buildManager), REGISTRY_LIFETIME_CASE, _lifetimeFee);
        _feeRegistry.setContractCaseFee(address(_buildManager), REGISTRY_BUILD_CASE, _buildFee);
        _feeRegistry.setContractCaseFee(address(_buildManager), REGISTRY_UPDATE_CASE, _updateFee);

        _feeRegistry.setDefaultPct(uint32(_refDiscountPct), uint32(_refSharePct));

        _feeRegistry.setLockOperator(address(_buildManager), true);

        if (_getRefMainnetId() == block.chainid) {
            _feeRegistry.setCodeOperator(address(_buildManager), true);
        }
    }

    function _transferOwnership(address _owner, CryptoLegacyBuildManager _buildManager, ProxyBuilder _proxyBuilder) internal {
        Ownable(address(_buildManager.feeRegistry())).transferOwnership(_owner);
        Ownable(address(_buildManager.pluginsRegistry())).transferOwnership(_owner);
        Ownable(address(_buildManager.beneficiaryRegistry())).transferOwnership(_owner);
        Ownable(address(_buildManager.lifetimeNft())).transferOwnership(_owner);
        Ownable(address(_buildManager.factory())).transferOwnership(_owner);
        _buildManager.transferOwnership(_owner);
        _proxyBuilder.transferOwnership(_owner);
        _proxyBuilder.proxyAdmin().transferOwnership(_owner);
    }

    function _transferOwnershipWithLm(address _owner, CryptoLegacyBuildManager _buildManager, ProxyBuilder _proxyBuilder, LegacyMessenger _lm) internal {
        _transferOwnership(_owner, _buildManager, _proxyBuilder);
        _lm.transferOwnership(_owner);
    }

    function _deployZeroCryptoLegacy(bytes32 _salt) internal returns(CryptoLegacy clToVerify) {
        address[] memory pls = new address[](0);
        clToVerify = new CryptoLegacy{salt: _salt}(address(0), address(0), pls);
    }

    function _deployProxyBuilder(bytes32 _salt, address _owner) internal returns (ProxyBuilder proxyBuilder) {
        ProxyAdmin proxyAdmin = new ProxyBuilderAdmin{salt: _salt}(_owner);
        proxyBuilder = new ProxyBuilder{salt: _salt}(_owner, address(proxyAdmin));
    }

    function _deployPluginsRegistry(bytes32 _salt, address _owner) internal returns(PluginsRegistry pluginsRegistry) {
        pluginsRegistry = new PluginsRegistry{salt: _salt}(_owner);
    }

    function _deployPluginsRegistryAndSet(bytes32 _salt, address _owner) internal returns(PluginsRegistry pluginsRegistry) {
        pluginsRegistry = _deployPluginsRegistry(_salt, _owner);

        (address basePlugin, address lensPlugin, address tgPlugin, address lrPlugin) = _deployPlugins(_salt);
        pluginsRegistry.addPlugin(basePlugin, "");
        pluginsRegistry.addPlugin(lensPlugin, "");
        pluginsRegistry.addPlugin(tgPlugin, "");
        pluginsRegistry.addPlugin(lrPlugin, "");
    }

    function _deployPlugins(bytes32 _salt) internal returns(address basePlugin, address lensPlugin, address tgPlugin, address lrPlugin) {
        basePlugin = address(new CryptoLegacyBasePlugin{salt: _salt}());
        lensPlugin = address(new LensPlugin{salt: _salt}());
        tgPlugin = address(new TrustedGuardiansPlugin{salt: _salt}());
        lrPlugin = address(new LegacyRecoveryPlugin{salt: _salt}());
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

    function _deploySignatureRoleTimelock(bytes32 _salt, CryptoLegacyBuildManager _buildManager, ProxyBuilder _proxyBuilder, LegacyMessenger _legacyMessenger, address _msig1, address _msig2, address _msig3) internal returns(SignatureRoleTimelock signatureRoleTimelock) {
        CryptoLegacyFactory factory = CryptoLegacyFactory(address(_buildManager.factory()));
        LifetimeNft lifetimeNft = LifetimeNft(address(_buildManager.lifetimeNft()));
        FeeRegistry feeRegistry = FeeRegistry(address(_buildManager.feeRegistry()));
        PluginsRegistry pluginsRegistry = PluginsRegistry(address(_buildManager.pluginsRegistry()));
        BeneficiaryRegistry beneficiaryRegistry = BeneficiaryRegistry(address(_buildManager.beneficiaryRegistry()));
        ProxyAdmin proxyAdmin = _proxyBuilder.proxyAdmin();

        ISignatureRoleTimelock.SignatureToAdd[] memory sigs = new ISignatureRoleTimelock.SignatureToAdd[](30);
        sigs[0] = _signatureMsig3(address(beneficiaryRegistry), beneficiaryRegistry.setBuildManager.selector);
        sigs[1] = _signatureMsig3(address(_legacyMessenger), _legacyMessenger.setBuildManager.selector);
        sigs[2] = _signatureMsig3(address(_buildManager), _buildManager.setRegistries.selector);
        sigs[3] = _signatureMsig3(address(_buildManager), _buildManager.setFactory.selector);
        sigs[4] = _signatureMsig2(address(_buildManager), _buildManager.setSupplyLimit.selector);
        sigs[5] = _signatureMsig2(address(_buildManager), _buildManager.setExternalLens.selector);
        sigs[6] = _signatureMsig2(address(_buildManager), _buildManager.withdrawFee.selector);
        sigs[7] = _signatureMsig3(address(factory), factory.setBuildOperator.selector);
        sigs[8] = _signatureMsig2(address(feeRegistry), feeRegistry.setCodeOperator.selector);
        sigs[9] = _signatureMsig2(address(feeRegistry), feeRegistry.setSupportedRefCodeInChains.selector);
        sigs[10] = _signatureMsig2(address(feeRegistry), feeRegistry.setFeeBeneficiaries.selector);
        sigs[11] = _signatureMsig2(address(feeRegistry), feeRegistry.setDefaultPct.selector);
        sigs[12] = _signatureZeroDaysMsig2(address(feeRegistry), feeRegistry.setRefererSpecificPct.selector);
        sigs[13] = _signatureMsig2(address(feeRegistry), feeRegistry.setContractCaseFee.selector);
        sigs[14] = _signatureZeroDaysMsig2(address(lifetimeNft), lifetimeNft.setBaseUri.selector);
        sigs[15] = _signatureMsig3(address(lifetimeNft), lifetimeNft.setMinterOperator.selector);
        sigs[16] = _signatureMsig3(address(feeRegistry), feeRegistry.setDebridgeGate.selector);
        sigs[17] = _signatureMsig2(address(feeRegistry), feeRegistry.setDebridgeNativeFee.selector);
        sigs[18] = _signatureMsig2(address(feeRegistry), feeRegistry.setDestinationChainContract.selector);
        sigs[19] = _signatureMsig2(address(feeRegistry), feeRegistry.setSourceChainContract.selector);
        sigs[20] = _signatureMsig2(address(feeRegistry), feeRegistry.setSourceAndDestinationChainContract.selector);
        sigs[21] = _signatureMsig2(address(feeRegistry), feeRegistry.setLockPeriod.selector);
        sigs[22] = _signatureZeroDaysMsig2(address(feeRegistry), feeRegistry.setReferralCode.selector);
        sigs[23] = _signatureMsig2(address(feeRegistry), feeRegistry.setCustomChainId.selector);
        sigs[24] = _signatureMsig3(address(pluginsRegistry), pluginsRegistry.addPlugin.selector);
        sigs[25] = _signatureMsig3(address(pluginsRegistry), pluginsRegistry.addPluginDescription.selector);
        sigs[26] = _signatureMsig3(address(pluginsRegistry), pluginsRegistry.removePlugin.selector);
        sigs[27] = _signatureMsig3(address(proxyAdmin), proxyAdmin.upgrade.selector);
        sigs[28] = _signatureMsig3(address(proxyAdmin), proxyAdmin.upgradeAndCall.selector);
        sigs[29] = _signatureMsig3(address(proxyAdmin), proxyAdmin.changeProxyAdmin.selector);

        signatureRoleTimelock = new SignatureRoleTimelock{salt: _salt}(5 days, getAddressRoles(_msig1, _msig2, _msig3), sigs, _msig1);
    }

    function _deployLifeTimeNft(bytes32 _salt, address _owner) internal returns(LifetimeNft lifetimeNft) {
        lifetimeNft = new LifetimeNft{salt: _salt}("LifeTime NFT", "LIFE", "", _owner);
    }

    function _deployFeeRegistry(bytes32 _salt, bytes32 _proxySalt, address _owner, ProxyBuilder proxyBuilder, uint32 _defaultDiscountPct, uint32 _defaultSharePct, ILifetimeNft _lifetimeNft, uint256 _lockPeriod) internal returns(FeeRegistry feeRegistry) {
        address implementation = address(new FeeRegistry{salt: _salt}());
        bytes memory initData = feeRegistryInitialize(_owner, _defaultDiscountPct, _defaultSharePct, _lifetimeNft, _lockPeriod);
        address create2Address = proxyBuilder.computeAddress(_proxySalt, keccak256(proxyBuilder.proxyBytecode(implementation, initData)));

        address proxy = proxyBuilder.build(create2Address, _proxySalt, implementation, initData);
        return FeeRegistry(proxy);
    }

    function _upgradeFeeRegistry(bytes32 _salt, FeeRegistry _feeRegistry, ProxyBuilder proxyBuilder) internal {
        address implementation = address(new FeeRegistry{salt: _salt}());
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(address(_feeRegistry)));
        proxyBuilder.proxyAdmin().upgrade(proxy, implementation);
    }

    function _setFeeRegistryCrossChains(FeeRegistry _feeRegistry) internal {
        uint256[] memory crossChainIds;
        address defaultDeBridge = 0x43dE2d77BF8027e25dBD179B491e8d64f38398aA;

        if (block.chainid == _getNftMainnetId() || block.chainid == _getNftMainnetId()) {
            _feeRegistry.setDebridgeGate(defaultDeBridge);

            crossChainIds = new uint256[](4);
            crossChainIds[0] = block.chainid == _getNftMainnetId() ? _getRefMainnetId() : _getNftMainnetId();
            crossChainIds[1] = 59144;
            crossChainIds[2] = 8453;
            crossChainIds[3] = 10;
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
        uint256 _lockPeriod
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            FeeRegistry.initialize.selector,
            _owner,
            _defaultDiscountPct,
            _defaultSharePct,
            address(_lifetimeNft),
            _lockPeriod
        );
    }

    function stringToHash(string memory _str) internal pure returns(bytes32) {
        return keccak256(abi.encode(_str));
    }
}