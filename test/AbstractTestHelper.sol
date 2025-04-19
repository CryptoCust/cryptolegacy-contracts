// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/plugins/CryptoLegacyBasePlugin.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/FeeRegistry.sol";
import "../script/LibMockDeploy.sol";
import "../script/LibDeploy.sol";
import "forge-std/Test.sol";

abstract contract AbstractTestHelper is Test {
  address constant internal owner = address(0x8888888888888888888888888888888888888888);
  address constant internal deployer = address(0xD37b6C0259aD13c9897D99B861469fBEE5070B96);

  address payable constant internal alice = payable(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa);
  address payable constant internal aliceRecipient = payable(0x9999999999999999999999999999999999999999);
  address payable constant internal bob = payable(0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB);
  address payable constant internal bobBeneficiary1 = payable(0x7777777777777777777777777777777777777777);
  address payable constant internal bobBeneficiary2 = payable(0x6666666666666666666666666666666666666666);
  address payable constant internal bobBeneficiary3 = payable(0x5555555555555555555555555555555555555555);
  address payable constant internal bobBeneficiary4 = payable(0x477acDDe05713A93B6d42D3a9237371457649132);
  address payable constant internal dan = payable(0x2222222222222222222222222222222222222222);
  address payable constant internal danRecipient = payable(0x1111111111111111111111111111111111111111);
  address payable constant internal charlie = payable(0xF30EEeDf37c4b965754193CC8E89B4cBEe1C9D5F);
  address payable constant internal custFeeRecipient1 = payable(0x4444444444444444444444444444444444444444);
  address payable constant internal custFeeRecipient2 = payable(0x3333333333333333333333333333333333333333);
  address payable constant internal treasury = payable(0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC);

  FeeRegistry internal feeRegistry;
  ProxyBuilder internal proxyBuilder;
  CryptoLegacyFactory internal factory;
  MockLifetimeNft internal lifetimeNft;
  PluginsRegistry internal pluginsRegistry;
  CryptoLegacyBuildManager internal buildManager;
  BeneficiaryRegistry internal beneficiaryRegistry;
  address internal cryptoLegacyBasePlugin;
  address internal lensPlugin;

  MockERC20 internal mockToken1;
  uint256 internal refDiscountPct = 1000;
  uint256 internal refSharePct = 2000;

  uint128 internal lifetimeFee = 2 ether;
  uint128 internal buildFee = 0.2 ether;
  uint128 internal updateFee = 0.1 ether;

  uint64 internal updateInterval = 180 days;
  uint64 internal challengeTimeout = 90 days;

  bytes32 internal salt = bytes32(uint256(1));
  uint256 internal buildRollNumber = 1;

  function setUp() public virtual {
    vm.startPrank(deployer);

    pluginsRegistry = LibDeploy._deployPluginsRegistry(salt, deployer);
    lifetimeNft = LibMockDeploy._deployMockLifeTimeNft(salt, deployer);

    proxyBuilder = LibDeploy._deployProxyBuilder(salt, deployer);
    feeRegistry = LibDeploy._deployFeeRegistry(salt, salt, deployer, proxyBuilder, uint32(0), uint32(0), lifetimeNft, 60);

    (buildManager, beneficiaryRegistry, factory) = LibMockDeploy._deployMockBuildManager(salt, deployer, feeRegistry, pluginsRegistry, lifetimeNft);

    LibMockDeploy._initFeeRegistry(feeRegistry, buildManager, lifetimeFee, buildFee, updateFee, refDiscountPct, refSharePct);
    LibDeploy._transferOwnership(owner, buildManager, proxyBuilder);

    vm.stopPrank();

    alice.transfer(10 ether);
    bob.transfer(10 ether);
    dan.transfer(10 ether);
    charlie.transfer(10 ether);
    bobBeneficiary1.transfer(10 ether);
    bobBeneficiary2.transfer(10 ether);
    bobBeneficiary3.transfer(10 ether);

    (cryptoLegacyBasePlugin, lensPlugin, , ) = LibDeploy._deployPlugins(salt);
  }

  function _addBasePluginsToRegistry() internal {
    vm.startPrank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");
    pluginsRegistry.addPlugin(cryptoLegacyBasePlugin, "");
    vm.stopPrank();
  }

  function _getBasePlugins() internal virtual returns(address[] memory plugins){
    return _getOneInitPluginList(lensPlugin);
  }

  function _getEmptyUintList() internal virtual returns(uint256[] memory list){
    list = new uint256[](0);
    return list;
  }

  function _getEmptyAddressList() internal virtual returns(address[] memory list){
    list = new address[](0);
    return list;
  }

  function _getOneAddressList(address _plugin) internal virtual returns(address[] memory addr){
    addr = new address[](1);
    addr[0] = _plugin;
    return addr;
  }

  function _getTwoAddressList(address _plugin, address _plugin2) internal virtual returns(address[] memory addr){
    addr = new address[](2);
    addr[0] = _plugin;
    addr[1] = _plugin2;
    return addr;
  }

  function _getTwoBytes32List(bytes32 _hash1, bytes32 _hash2) internal virtual returns(bytes32[] memory hashes){
    hashes = new bytes32[](2);
    hashes[0] = _hash1;
    hashes[1] = _hash2;
    return hashes;
  }

  function _getOneInitPluginList(address _plugin) internal virtual returns(address[] memory plugins){
    return _getTwoAddressList(cryptoLegacyBasePlugin, _plugin);
  }

  function _getTwoInitPluginsList(address _plugin1, address _plugin2) internal virtual returns(address[] memory plugins){
    plugins = new address[](3);
    plugins[0] = cryptoLegacyBasePlugin;
    plugins[1] = _plugin1;
    plugins[2] = _plugin2;
    return plugins;
  }

  function _getThreeInitPluginsList(address _plugin1, address _plugin2, address _plugin3) internal virtual returns(address[] memory plugins){
    plugins = new address[](4);
    plugins[0] = cryptoLegacyBasePlugin;
    plugins[1] = _plugin1;
    plugins[2] = _plugin2;
    plugins[3] = _plugin3;
    return plugins;
  }

  function _getThreeUintList(uint256 _one, uint256 _two, uint256 _three) internal virtual returns(uint256[] memory list){
    list = new uint256[](3);
    list[0] = _one;
    list[1] = _two;
    list[2] = _three;
    return list;
  }

  function _getFourUintList(uint256 _one, uint256 _two, uint256 _three, uint256 _four) internal virtual returns(uint256[] memory list){
    list = new uint256[](4);
    list[0] = _one;
    list[1] = _two;
    list[2] = _three;
    list[3] = _four;
    return list;
  }

  function _getRefChains() internal virtual returns(uint256[] memory){
    uint256[] memory chains = new uint256[](0);
    return chains;
  }

  function _getRefArgsStruct(address createRefRecipient) internal virtual returns(ICryptoLegacyBuildManager.RefArgs memory){
    return _getRefArgsStructWithChains(createRefRecipient, _getRefChains(), _getRefChains());
  }

  function _getRefArgsStructWithChains(address createRefRecipient, uint256[] memory _chainIdsToLock, uint256[] memory _crossChainFees) internal virtual returns(ICryptoLegacyBuildManager.RefArgs memory){
    return ICryptoLegacyBuildManager.RefArgs(createRefRecipient, bytes4(0), _chainIdsToLock, _crossChainFees);
  }

  function _getCreate2ArgsStruct(address _create2Address, bytes32 _create2Salt) internal virtual returns(ICryptoLegacyFactory.Create2Args memory){
    return ICryptoLegacyFactory.Create2Args(_create2Address, _create2Salt);
  }

  function _buildCryptoLegacy(address _prank, uint256 _fee, bytes8 _refCode) internal virtual returns(CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, bytes32[] memory beneficiaryArr, ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr) {
    return _buildCryptoLegacyWithPlugins(_prank, _fee, _refCode, _getBasePlugins());
  }

  function _buildCryptoLegacyWithPlugins(address _prank, uint256 _fee, bytes8 _refCode, address[] memory _plugins) internal returns(CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, bytes32[] memory beneficiaryArr, ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr) {
    beneficiaryArr = new bytes32[](2);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    beneficiaryArr[1] = keccak256(abi.encode(bobBeneficiary2));
    beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](2);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(0, 0, 4000);
    beneficiaryConfigArr[1] = ICryptoLegacy.BeneficiaryConfig(0, 0, 6000);

//    vm.expectEmit(true, false, false, false);
//    emit CryptoLegacyBuildManager.Build(_prank, address(0), plugins, beneficiaryArr, beneficiaryConfigArr, _fee != 0);

    vm.prank(_prank);
    ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(_refCode, beneficiaryArr, beneficiaryConfigArr, _plugins, updateInterval, challengeTimeout);
    buildRoll();
    address payable cl = buildManager.buildCryptoLegacy{value: _fee}(buildArgs, _getRefArgsStruct(_prank), _getCreate2ArgsStruct(address(0), bytes32(uint(0))));
    cryptoLegacy = CryptoLegacyBasePlugin(cl);
    cryptoLegacyLens = ICryptoLegacyLens(cl);
  }

  function buildRoll() internal {
    vm.roll(buildRollNumber);
    buildRollNumber++;
  }

  function addressToHash(address _addr) internal pure returns(bytes32) {
    return keccak256(abi.encode(_addr));
  }
}
