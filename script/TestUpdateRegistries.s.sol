// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./LibDeploy.sol";
import "./LibMockDeploy.sol";
import "./UpdateRegistries.s.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/mocks/MockArbSys.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "forge-std/console.sol";

contract TestUpdateRegistries is Script {

    address payable internal _charlie = payable(0xF30EEeDf37c4b965754193CC8E89B4cBEe1C9D5F);
    address payable internal _dan = payable(0x2222222222222222222222222222222222222222);
    uint64 internal _updateInterval = 180 days;
    uint64 internal _challengeTimeout = 90 days;
    uint128 internal _buildFee = uint128(0.05 ether);

    CryptoLegacyBuildManager internal _buildManager = CryptoLegacyBuildManager(payable(0xF056a682A6b68833356D340a149A5bA1e6B1b194));
    PluginsRegistry _pluginRegistry = PluginsRegistry(0xdb0Cad1E2dd829F1F258A0d27244aFAe2334AF3f);
    BeneficiaryRegistry _beneficiaryRegistry = BeneficiaryRegistry(0x9d6E3A6539DdB1B8d108cD0aAE2B7E3040ED2336);
    LegacyMessenger _legacyMessenger = LegacyMessenger(0x925A9073408FC27a2A552E2cb23610D1f95F25b1);

    function run() public {
        MockArbSys mockArbSys = new MockArbSys();
        vm.etch(address(100), address(mockArbSys).code);

        address multiSig3 = vm.envAddress("MULTISIG_3");
        
        _charlie.transfer(1.5 ether);
        SignatureRoleTimelock srt = SignatureRoleTimelock(_buildManager.owner());
        address feeRegistry = address(_buildManager.feeRegistry());

        bytes memory setRegistriesBytes = abi.encodeWithSelector(_buildManager.setRegistries.selector, feeRegistry, address(_pluginRegistry), address(_beneficiaryRegistry));

        ISignatureRoleTimelock.CallToAdd[] memory calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(_buildManager), setRegistriesBytes);

        vm.prank(multiSig3);
        bytes32[] memory callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + LibDeploy._getDefaultTimelock() + 1);
        srt.executeCallList(callIds);

        assert(address(_buildManager.feeRegistry()) == feeRegistry);
        assert(address(_buildManager.pluginsRegistry()) == address(_pluginRegistry));
        assert(address(_buildManager.beneficiaryRegistry()) == address(_beneficiaryRegistry));

        bytes8 customRefCode = 0x0123456789abcdef;
        vm.startPrank(_charlie);
        _buildManager.createCustomRef(customRefCode, _charlie, _getEmptyUintList(), _getEmptyUintList());

        bytes32[] memory beneficiaryArr = new bytes32[](1);
        beneficiaryArr[0] = keccak256(abi.encode(_dan));
        ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
        beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);
        ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(bytes8(0), beneficiaryArr, beneficiaryConfigArr, _pluginRegistry.getPluginAddressList(), _updateInterval, _challengeTimeout);
        address payable cl = _buildManager.buildCryptoLegacy{value: _buildFee}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), 0));
        ICryptoLegacyLens cryptoLegacyLens = ICryptoLegacyLens(cl);

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        assert(address(clData.buildManager) == address(_buildManager));

        bytes[] memory messages = new bytes[](1);
        beneficiaryArr[0] = keccak256(abi.encode(_dan));
        _legacyMessenger.sendMessagesTo(cl, beneficiaryArr, beneficiaryArr, messages, messages, 1);
        vm.stopPrank();

        _beneficiaryRegistry.getCryptoLegacyListByOwner(keccak256(abi.encode(_charlie)));
        _beneficiaryRegistry.getCryptoLegacyBlockNumberChanges(cl);
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