// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./LibDeploy.sol";
import "./LibMockDeploy.sol";
import "./CryptoLegacyFactory.s.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "forge-std/console.sol";

contract TestCryptoLegacyFactoryDeploy is CryptoLegacyFactoryDeploy {

    address payable constant internal charlie = payable(0xF30EEeDf37c4b965754193CC8E89B4cBEe1C9D5F);
    address payable constant internal dan = payable(0x2222222222222222222222222222222222222222);
    uint64 internal updateInterval = 180 days;
    uint64 internal challengeTimeout = 90 days;

    function run() public override {
        super.run();

        charlie.transfer(1.5 ether);

        address sigTimelock = address(srt);
        _checkOwner(address(buildManager.feeRegistry()), sigTimelock);
        _checkOwner(address(buildManager.pluginsRegistry()), sigTimelock);
        _checkOwner(address(buildManager.beneficiaryRegistry()), sigTimelock);
        // _checkOwner(address(buildManager.lifetimeNft()), sigTimelock);
        _checkOwner(address(buildManager.factory()), sigTimelock);
        _checkOwner(address(buildManager), sigTimelock);
        _checkOwner(address(legacyMessenger), sigTimelock);
        _checkOwner(address(proxyBuilder), sigTimelock);
        _checkOwner(address(proxyBuilder.proxyAdmin()), sigTimelock);

        vm.expectRevert(ISignatureRoleTimelock.DisabledFunction.selector);
        srt.renounceRole(bytes32(0), address(0));

        CryptoLegacyExternalLens newExternalLens = new CryptoLegacyExternalLens();
        bytes memory setExternalBytes = abi.encodeWithSelector(buildManager.setExternalLens.selector, address(newExternalLens));

        ISignatureRoleTimelock.CallToAdd[] memory calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(buildManager), setExternalBytes);

        vm.prank(multiSig1);
        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, LibDeploy._getMsig2Role()));
        bytes32[] memory callIds = srt.scheduleCallList(calls);

        vm.prank(multiSig2);
        callIds = srt.scheduleCallList(calls);

        vm.expectRevert(ISignatureRoleTimelock.CallAlreadyScheduled.selector);
        vm.prank(multiSig2);
        srt.scheduleCallList(calls);

        vm.warp(block.timestamp + LibDeploy._getDefaultTimelock() / 2);

        vm.expectRevert(ISignatureRoleTimelock.TimelockActive.selector);
        srt.executeCallList(callIds);

        assert(address(buildManager.externalLens()) != address(newExternalLens));
        vm.warp(block.timestamp + LibDeploy._getDefaultTimelock() / 2 + 1);
        srt.executeCallList(callIds);
        assert(address(buildManager.externalLens()) == address(newExternalLens));

        ISignatureRoleTimelock.AddressRoleInput[] memory roles = new ISignatureRoleTimelock.AddressRoleInput[](1);
        roles[0] = ISignatureRoleTimelock.AddressRoleInput(LibDeploy._getMsig3Role(), charlie, address(0));

        bytes memory setRolesBytes = abi.encodeWithSelector(srt.setRoleAccounts.selector, roles);

        calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(srt), setRolesBytes);

        vm.prank(multiSig2);
        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, srt.ADMIN_ROLE()));
        callIds = srt.scheduleCallList(calls);

        vm.prank(multiSig1);
        callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + 5 days);

        assert(srt.hasRole(LibDeploy._getMsig3Role(), charlie) == false);
        srt.executeCallList(callIds);
        assert(srt.hasRole(LibDeploy._getMsig3Role(), charlie) == true);

        bytes8 customRefCode = 0x0123456789abcdef;
        vm.startPrank(charlie);
        vm.expectRevert(IFeeRegistry.NotOperator.selector);
        (bytes8 refCode, , ) = buildManager.createCustomRef(customRefCode, charlie, _getEmptyUintList(), _getEmptyUintList());

        bytes32[] memory beneficiaryArr = new bytes32[](1);
        beneficiaryArr[0] = keccak256(abi.encode(dan));
        ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
        beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);
        ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(bytes8(0), beneficiaryArr, beneficiaryConfigArr, pluginRegistry.getPluginAddressList(), updateInterval, challengeTimeout);
        address payable cl = buildManager.buildCryptoLegacy{value: 0}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), 0));
        CryptoLegacyBasePlugin cryptoLegacy = CryptoLegacyBasePlugin(cl);
        ICryptoLegacyLens cryptoLegacyLens = ICryptoLegacyLens(cl);

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        assert(clData.buildManager == address(buildManager));

        assert(feeRegistry.isNftLocked(charlie) == false);
        buildManager.payInitialFee{value: lifetimeFee}(customRefCode, charlie, _getEmptyUintList(), _getEmptyUintList());
        assert(feeRegistry.isNftLocked(charlie) == true);
        assert(lifetimeNft.totalSupply() == 1);
        vm.stopPrank();
        // assert(true == false);
    }


    function _getTwoAddressList(address _plugin, address _plugin2) internal virtual returns(address[] memory addr){
        addr = new address[](2);
        addr[0] = _plugin;
        addr[1] = _plugin2;
        return addr;
    }

    function _checkOwner(address _contract, address _owner) internal view {
        assert(Ownable(_contract).owner() == _owner);
    }

    function _getEmptyUintList() internal virtual returns(uint256[] memory list){
        list = new uint256[](0);
        return list;
    }

    function _getRefArgsStruct(address createRefRecipient) internal virtual returns(ICryptoLegacyBuildManager.RefArgs memory){
        return _getCustomRefArgsStructWithChains(createRefRecipient, bytes4(0), _getEmptyUintList(), _getEmptyUintList());
    }

    function _getCustomRefArgsStructWithChains(address createRefRecipient, bytes8 _customRefCode, uint256[] memory _chainIdsToLock, uint256[] memory _crossChainFees) internal virtual returns(ICryptoLegacyBuildManager.RefArgs memory){
        return ICryptoLegacyBuildManager.RefArgs(createRefRecipient, _customRefCode, _chainIdsToLock, _crossChainFees);
    }

    function _getCreate2ArgsStruct(address _create2Address, bytes32 _create2Salt) internal virtual returns(ICryptoLegacyFactory.Create2Args memory){
        return ICryptoLegacyFactory.Create2Args(_create2Address, _create2Salt);
    }
}