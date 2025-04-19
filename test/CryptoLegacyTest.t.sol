// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AbstractTestHelper.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockERC721.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/mocks/MockTestPlugin.sol";
import "../contracts/mocks/MockTest2Plugin.sol";
import "../contracts/mocks/MockClaimPlugin.sol";
import "../contracts/plugins/NftLegacyPlugin.sol";
import "../contracts/plugins/UpdateRolePlugin.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/interfaces/ICryptoLegacy.sol";
import "../contracts/mocks/MockMaliciousERC20.sol";
import "../contracts/mocks/MockMaliciousERC721.sol";
import "../contracts/libraries/LibCryptoLegacy.sol";
import "../contracts/plugins/LegacyRecoveryPlugin.sol";
import "../contracts/interfaces/ICryptoLegacyLens.sol";
import "../contracts/plugins/TrustedGuardiansPlugin.sol";
import "../contracts/interfaces/ITrustedGuardiansPlugin.sol";
import "../contracts/plugins/BeneficiaryPluginAddRights.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CryptoLegacyTest is AbstractTestHelper {

  function setUp() public override {
    super.setUp();
    vm.startPrank(owner);
    pluginsRegistry.addPlugin(cryptoLegacyBasePlugin, "");
    feeRegistry.setLockOperator(address(buildManager), true);
    vm.stopPrank();

    vm.startPrank(owner);
    mockToken1 = new MockERC20("Mock", "MOCK");
    mockToken1.mint(treasury, 1000 ether);
    mockToken1.mint(bob, 100000 ether);
    vm.stopPrank();
  }

  function testInitialDataAssignedCorrectly() public view {
    assertEq(feeRegistry.owner(), owner);
    assertEq(pluginsRegistry.owner(), owner);
    assertEq(buildManager.owner(), owner);

    PluginsRegistry.PluginInfo[] memory ps = pluginsRegistry.getPluginInfoList();
    assertEq(ps.length, 1);
    assertEq(ps[0].descriptionBlockNumbers.length, 1);
    assertEq(ps[0].descriptionBlockNumbers[0], block.number);
    assertEq(ps[0].name, "base");
    assertEq(ps[0].version, uint16(1));
    assertEq(ps[0].plugin, cryptoLegacyBasePlugin);

    address[] memory psAddresses = pluginsRegistry.getPluginAddressList();
    assertEq(psAddresses.length, 1);
    assertEq(psAddresses[0], cryptoLegacyBasePlugin);

    (
      string memory name,
      uint16 version,
      uint64[] memory descriptionBlockNumbers
    ) = pluginsRegistry.getPluginMetadata(cryptoLegacyBasePlugin);
    assertEq(descriptionBlockNumbers.length, 1);
    assertEq(descriptionBlockNumbers[0], block.number);
    assertEq(name, "base");
    assertEq(version, uint16(1));
  }

  function testProxyBuilder() public {
    address newProxyAdmin = address(new ProxyAdmin());
    vm.expectRevert("Ownable: caller is not the owner");
    proxyBuilder.setProxyAdmin(newProxyAdmin);

    vm.prank(owner);
    proxyBuilder.setProxyAdmin(newProxyAdmin);
    assertEq(address(proxyBuilder.proxyAdmin()), newProxyAdmin);
  }

  function testExternalLens() public {
    bytes8 customRefCode = 0x0123456789abcdef;
    vm.prank(alice);
    buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());

    CryptoLegacyExternalLens externalLens = new CryptoLegacyExternalLens();
    vm.startPrank(owner);
    vm.roll(10);
    pluginsRegistry.addPlugin(lensPlugin, "");
    buildManager.setExternalLens(address(externalLens));
    vm.stopPrank();

    (CryptoLegacyBasePlugin cryptoLegacy, , , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, customRefCode, _getOneInitPluginList(lensPlugin));
    address cl = address(cryptoLegacy);
    assertEq(CryptoLegacy(payable(cl)).externalLens(), address(externalLens));
    assertEq(externalLens.isLifetimeActive(cl), false);
    assertEq(externalLens.isPaused(cl), false);
    assertEq(externalLens.owner(cl), bob);
    assertEq(externalLens.buildManager(cl), address(buildManager));
    assertEq(externalLens.updateInterval(cl), updateInterval);
    assertEq(externalLens.challengeTimeout(cl), challengeTimeout);
    assertEq(externalLens.distributionStartAt(cl), 0);
    assertEq(externalLens.lastFeePaidAt(cl), block.timestamp);
    assertEq(externalLens.lastUpdateAt(cl), block.timestamp);
    assertEq(externalLens.initialFeeToPay(cl), 0);
    assertEq(externalLens.updateFee(cl), updateFee - updateFee * refDiscountPct / 10000);
    assertEq(externalLens.invitedByRefCode(cl), customRefCode);
    {
      (bytes32[] memory hashes, bytes32[] memory originalHashes, ICryptoLegacy.BeneficiaryConfig[] memory configs) = externalLens.getBeneficiaries(cl);

      assertEq(hashes[0], keccak256(abi.encode(bobBeneficiary1)));
      assertEq(hashes[1], keccak256(abi.encode(bobBeneficiary2)));
      assertEq(originalHashes[0], keccak256(abi.encode(bobBeneficiary1)));
      assertEq(originalHashes[1], keccak256(abi.encode(bobBeneficiary2)));
      assertEq(configs[0].shareBps, 4000);
      assertEq(configs[0].claimDelay, 0);
      assertEq(configs[0].vestingPeriod, 0);
      assertEq(configs[1].shareBps, 6000);
      assertEq(configs[1].claimDelay, 0);
      assertEq(configs[1].vestingPeriod, 0);
    }

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = externalLens.getCryptoLegacyBaseData(cl);
    assertEq(clData.buildManager, address(buildManager));
    assertEq(clData.updateInterval, updateInterval);
    assertEq(clData.challengeTimeout, challengeTimeout);

    {
      ICryptoLegacyLens.CryptoLegacyListData memory clListData = externalLens.getCryptoLegacyListData(cl, _getEmptyAddressList());
      assertEq(clListData.plugins.length, 2);
      assertEq(clListData.plugins[0].name, "base");
      assertEq(clListData.plugins[1].name, "lens");
    }

    ICryptoLegacyLens.PluginInfo[] memory ps = externalLens.getPluginInfoList(cl);
    assertEq(ps.length, 2);
    assertEq(ps[1].descriptionBlockNumbers.length, 1);
    assertEq(ps[1].descriptionBlockNumbers[0], 10);
    assertEq(ps[1].name, "lens");
    assertEq(ps[1].version, uint16(1));
    assertEq(ps[1].plugin, lensPlugin);

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();

    vm.warp(block.timestamp + clData.challengeTimeout + 1);
    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(mockToken1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);

    uint64[] memory blockNumbers = externalLens.getTransferBlockNumbers(cl);
    assertEq(blockNumbers[0], block.number);

    ICryptoLegacy.TokenDistribution[] memory list = externalLens.getTokensDistribution(cl, _getOneAddressList(address(mockToken1)));

    assertEq(list[0].amountToDistribute, 100 ether);
    assertEq(list[0].totalClaimedAmount, 0);

    vm.expectRevert(ICryptoLegacy.BeneficiaryNotExist.selector);
    (LensPlugin.BeneficiaryTokenData[] memory tokenData, , ) = externalLens.getVestedAndClaimedData(cl, addressToHash(dan), _getOneAddressList(address(mockToken1)));

    (tokenData, , ) = externalLens.getVestedAndClaimedData(cl, addressToHash(bobBeneficiary2), _getOneAddressList(address(mockToken1)));
    assertEq(tokenData[0].claimedAmount, 0);
    assertEq(tokenData[0].vestedAmount, 60 ether);
    assertEq(tokenData[0].totalAmount, 60 ether);
  }

  function testDiamondLoupeFacet() public {
    CryptoLegacyExternalLens externalLens = new CryptoLegacyExternalLens();
    vm.startPrank(owner);
    vm.roll(10);
    pluginsRegistry.addPlugin(lensPlugin, "");
    buildManager.setExternalLens(address(externalLens));
    vm.stopPrank();

    (CryptoLegacyBasePlugin cryptoLegacy, , , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getOneInitPluginList(lensPlugin));
    CryptoLegacy cl = CryptoLegacy(payable(address(cryptoLegacy)));
    DiamondLoupeFacet.Facet[] memory facets = cl.facets();
    assertEq(facets.length, 2);
    assertEq(facets[0].facetAddress, cryptoLegacyBasePlugin);
    assertEq(facets[0].functionSelectors.length, 17);
    assertEq(facets[1].facetAddress, lensPlugin);
    assertEq(facets[1].functionSelectors.length, 20);

    assertEq(cl.facetFunctionSelectors(cryptoLegacyBasePlugin).length, 17);
    assertEq(cl.facetAddresses().length, 2);
    assertEq(cl.facetAddresses()[0], cryptoLegacyBasePlugin);
    assertEq(cl.facetAddresses()[1], lensPlugin);
    assertEq(cl.facetAddress(LensPlugin.updateInterval.selector), lensPlugin);

    assertEq(cl.facetAddress(facets[0].functionSelectors[0]), facets[0].facetAddress);
    assertEq(cl.supportsInterface(facets[0].functionSelectors[0]), false);
  }

  function testCreateCryptoLegacyAndUpdate() public {
    bytes8 customRefCode = 0x0123456789abcdef;
    vm.prank(alice);
    vm.expectEmit(true, true, true, true);
    emit ICryptoLegacyBuildManager.CreateCustomRef(alice, customRefCode, aliceRecipient, _getRefChains());
    (bytes8 refCode, ) = buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());
    assertEq(customRefCode, refCode);
    IFeeRegistry.Referrer memory ref = feeRegistry.getReferrerByCode(refCode);
    assertEq(ref.owner, alice);
    assertEq(ref.recipient, aliceRecipient);
    assertEq(ref.sharePct, feeRegistry.defaultSharePct());
    assertEq(ref.discountPct, feeRegistry.defaultDiscountPct());

    (uint32 discountPct, uint32 sharePct) = feeRegistry.getCodePct(refCode);
    assertEq(sharePct, feeRegistry.defaultSharePct());
    assertEq(discountPct, feeRegistry.defaultDiscountPct());

    address newLensPlugin = address(new LensPlugin());
    vm.expectRevert("Ownable: caller is not the owner");
    pluginsRegistry.addPlugin(newLensPlugin, "");

    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;

    uint256 createdAt = block.timestamp;
    uint256 discount = buildFee * refDiscountPct / 10000;
    uint256 share = buildFee * refSharePct / 10000;

    vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, buildFee - discount));
    (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee - discount - 0.01 ether, customRefCode);

    vm.expectRevert(LibCreate2Deploy.Create2Failed.selector);
    (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee - discount, customRefCode);
    vm.stopPrank();

    vm.prank(owner);
    vm.expectEmit(true, true, false, false);
    emit IPluginsRegistry.AddPlugin(lensPlugin, "123");
    pluginsRegistry.addPlugin(lensPlugin, "123");
//    uint256 lensPluginBlockNumber = block.number;

    assertEq(pluginsRegistry.getPluginDescriptionBlockNumbers(lensPlugin)[0], block.number);
    assertEq(pluginsRegistry.getPluginDescriptionBlockNumbers(lensPlugin).length, 1);

    vm.roll(10);

    vm.prank(owner);
    vm.expectEmit(true, true, true, false);
    emit IPluginsRegistry.AddPluginDescription(lensPlugin, "123");
    pluginsRegistry.addPluginDescription(lensPlugin, "123");
    assertEq(pluginsRegistry.getPluginDescriptionBlockNumbers(lensPlugin)[1], block.number);
    assertEq(pluginsRegistry.getPluginDescriptionBlockNumbers(lensPlugin).length, 2);

    vm.expectEmit(true, true, true, true);
    emit IFeeRegistry.SentFee(alice, customRefCode, aliceRecipient, share);

    assertEq(aliceRecipient.balance, 0);
    bytes32[] memory beneficiaryArr;
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr;
    (cryptoLegacy, cryptoLegacyLens, beneficiaryArr, beneficiaryConfigArr) = _buildCryptoLegacy(bob, buildFee - discount, customRefCode);
    assertEq(aliceRecipient.balance, share);

    ICryptoLegacyLens.CryptoLegacyListData memory clListData = cryptoLegacyLens.getCryptoLegacyListData(_getEmptyAddressList());
    assertEq(clListData.plugins.length, 2);
    assertEq(clListData.plugins[0].name, "base");
    assertEq(clListData.plugins[1].name, "lens");
    assertEq(clListData.plugins[0].descriptionBlockNumbers.length, 1);

    assertEq(beneficiaryArr.length, clListData.beneficiaries.length);
    assertEq(beneficiaryArr[0], clListData.beneficiaries[0]);
    assertEq(beneficiaryArr[1], clListData.beneficiaries[1]);
    assertEq(beneficiaryArr[0], addressToHash(bobBeneficiary1));
    assertEq(beneficiaryArr[1], addressToHash(bobBeneficiary2));

    assertEq(beneficiaryConfigArr.length, clListData.beneficiaryConfigArr.length);
    assertEq(beneficiaryConfigArr[0].shareBps, clListData.beneficiaryConfigArr[0].shareBps);
    assertEq(beneficiaryConfigArr[0].claimDelay, clListData.beneficiaryConfigArr[0].claimDelay);
    assertEq(beneficiaryConfigArr[0].vestingPeriod, clListData.beneficiaryConfigArr[0].vestingPeriod);
    assertEq(beneficiaryConfigArr[1].shareBps, clListData.beneficiaryConfigArr[1].shareBps);
    assertEq(beneficiaryConfigArr[1].claimDelay, clListData.beneficiaryConfigArr[1].claimDelay);
    assertEq(beneficiaryConfigArr[1].vestingPeriod, clListData.beneficiaryConfigArr[1].vestingPeriod);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    assertEq(clData.lastUpdateAt, createdAt);

    vm.warp(block.timestamp + clData.updateInterval);
    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacy.update{value: 0.09 ether}(_getEmptyUintList(), _getEmptyUintList());

    vm.startPrank(bob);
    vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.IncorrectFee.selector, 0.09 ether));
    cryptoLegacy.update{value: 0.08 ether}(_getEmptyUintList(), _getEmptyUintList());

    CryptoLegacy cl = CryptoLegacy(payable(address(cryptoLegacy)));
    assertEq(cl.storageFacetAddress(CryptoLegacyBasePlugin.update.selector), address(0));
    cryptoLegacy.update{value: 0.09 ether}(_getEmptyUintList(), _getEmptyUintList());
    assertEq(cl.storageFacetAddress(CryptoLegacyBasePlugin.update.selector), _getBasePlugins()[0]);
    uint256 lastFeePaidAt = cryptoLegacyLens.getCryptoLegacyBaseData().lastFeePaidAt;
    vm.stopPrank();

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacy.setBeneficiaries(beneficiaryArr, beneficiaryConfigArr);

    vm.prank(bob);
    beneficiaryArr = new bytes32[](1);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(0, 0, 10000);
    vm.expectRevert(ICryptoLegacy.ShareSumDoesntMatchBase.selector);
    cryptoLegacy.setBeneficiaries(beneficiaryArr, beneficiaryConfigArr);

    vm.prank(bob);
    beneficiaryArr = new bytes32[](3);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    beneficiaryArr[1] = keccak256(abi.encode(bobBeneficiary2));
    beneficiaryArr[2] = keccak256(abi.encode(bobBeneficiary3));
    beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](3);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(0, 0, 4000);
    beneficiaryConfigArr[1] = ICryptoLegacy.BeneficiaryConfig(0, 0, 0);
    beneficiaryConfigArr[2] = ICryptoLegacy.BeneficiaryConfig(0, 0, 6000);
    cryptoLegacy.setBeneficiaries(beneficiaryArr, beneficiaryConfigArr);

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    vm.prank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.TooEarly.selector);
    cryptoLegacy.initiateChallenge();

    vm.warp(block.timestamp + clData.updateInterval + 1);

    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    cryptoLegacy.initiateChallenge();

    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();
    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(mockToken1);

    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);

    vm.startPrank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.TooEarly.selector);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);

    uint256 distributionStartAt = block.timestamp + clData.challengeTimeout;
    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, distributionStartAt);
    vm.warp(block.timestamp + clData.challengeTimeout + 1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);

    assertEq(mockToken1.balanceOf(bobBeneficiary1), 0);
    assertEq(lastFeePaidAt, cryptoLegacyLens.getCryptoLegacyBaseData().lastFeePaidAt);
    cryptoLegacy.beneficiaryClaim{value: 0.001 ether}(_tokens, address(0), 0);
    uint256 newLastFeePaidAt = cryptoLegacyLens.getCryptoLegacyBaseData().lastFeePaidAt;
    assertNotEq(lastFeePaidAt, newLastFeePaidAt);
    assertEq(lastFeePaidAt + clData.updateInterval, newLastFeePaidAt);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 40 ether);
    vm.stopPrank();

    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);

    assertEq(mockToken1.balanceOf(bobBeneficiary3), 0);
    vm.prank(bobBeneficiary3);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 60 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 40 ether);
  }

  function _buildCryptoLegacyWithVesting() internal returns(CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, bytes32[] memory beneficiaryArr, ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr) {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    beneficiaryArr = new bytes32[](2);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    beneficiaryArr[1] = keccak256(abi.encode(bobBeneficiary2));
    beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](2);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 4000);
    beneficiaryConfigArr[1] = ICryptoLegacy.BeneficiaryConfig(20, 100, 6000);

    buildRoll();
    vm.prank(bob);
    uint256 createdAt = block.timestamp;
    ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(bytes8(0), beneficiaryArr, beneficiaryConfigArr, _getBasePlugins(), 180 days, 90 days);
    address payable cl = buildManager.buildCryptoLegacy{value: buildFee}(buildArgs, _getRefArgsStruct(bob), _getCreate2ArgsStruct(address(0), bytes32(uint(0))));
    cryptoLegacy = CryptoLegacyBasePlugin(cl);
    cryptoLegacyLens = ICryptoLegacyLens(cl);
    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.lastUpdateAt, createdAt);
  }

  function testCreateCryptoLegacyVesting() public {
    (
      CryptoLegacyBasePlugin cryptoLegacy,
      ICryptoLegacyLens cryptoLegacyLens,
      bytes32[] memory beneficiaryArr,
      ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr
    ) = _buildCryptoLegacyWithVesting();

    ICryptoLegacyLens.CryptoLegacyListData memory clListData = cryptoLegacyLens.getCryptoLegacyListData(_getEmptyAddressList());

    assertEq(beneficiaryConfigArr.length, clListData.beneficiaryConfigArr.length);
    assertEq(beneficiaryConfigArr[0].shareBps, clListData.beneficiaryConfigArr[0].shareBps);
    assertEq(beneficiaryConfigArr[0].claimDelay, clListData.beneficiaryConfigArr[0].claimDelay);
    assertEq(beneficiaryConfigArr[0].vestingPeriod, clListData.beneficiaryConfigArr[0].vestingPeriod);
    assertEq(beneficiaryConfigArr[1].shareBps, clListData.beneficiaryConfigArr[1].shareBps);
    assertEq(beneficiaryConfigArr[1].claimDelay, clListData.beneficiaryConfigArr[1].claimDelay);
    assertEq(beneficiaryConfigArr[1].vestingPeriod, clListData.beneficiaryConfigArr[1].vestingPeriod);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval);
    vm.prank(bob);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();
    uint256 distributionStartAt = block.timestamp + clData.challengeTimeout;
    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, distributionStartAt);

    vm.warp(block.timestamp + clData.challengeTimeout + 1);
    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;

    vm.prank(bobBeneficiary1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _getOneAddressList(address(mockToken1)));

    (LensPlugin.BeneficiaryTokenData[] memory tokenData, uint64 startDate, uint64 endDate) = cryptoLegacyLens.getVestedAndClaimedData(addressToHash(bobBeneficiary2), _getOneAddressList(address(mockToken1)));
    assertEq(tokenData[0].claimedAmount, 0);
    assertEq(tokenData[0].vestedAmount, 0);
    assertEq(tokenData[0].totalAmount, 60 ether);

    assertEq(mockToken1.balanceOf(bobBeneficiary1), 0);
    vm.startPrank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.TooEarly.selector);
    cryptoLegacy.beneficiaryClaim{value: updateFee}(_getOneAddressList(address(mockToken1)), address(0), 0);

    vm.warp(block.timestamp + 10 + 1);
    cryptoLegacy.beneficiaryClaim{value: updateFee}(_getOneAddressList(address(mockToken1)), address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 0.8 ether);

    vm.warp(block.timestamp + 2);
    cryptoLegacy.beneficiaryClaim{value: updateFee}(_getOneAddressList(address(mockToken1)), address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 1.6 ether);

    feeRegistry.withdrawAccumulatedFee();

    vm.stopPrank();

    vm.prank(bob);
    vm.expectRevert(ICryptoLegacy.DistributionStarted.selector);
    cryptoLegacy.setBeneficiaries(beneficiaryArr, beneficiaryConfigArr);

    vm.startPrank(bobBeneficiary2);

    assertEq(mockToken1.balanceOf(bobBeneficiary2), 0);

    vm.expectRevert(ICryptoLegacy.TooEarly.selector);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);

    vm.warp(block.timestamp + 8);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary2), 1.2 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 1.6 ether);

    vm.warp(block.timestamp + 3);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary2), 3 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 1.6 ether);

    vm.stopPrank();

    vm.prank(bobBeneficiary1);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary2), 3 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 6 ether);

    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    cryptoLegacy.beneficiarySwitch(addressToHash(bobBeneficiary3));

    address[] memory cryptoLegacyGot = beneficiaryRegistry.getCryptoLegacyListByBeneficiary(addressToHash(bobBeneficiary1));
    assertEq(cryptoLegacyGot.length, 1);
    assertEq(cryptoLegacyGot[0], address(cryptoLegacy));

    uint256[] memory cryptoLegacyBlockNumbers = beneficiaryRegistry.getCryptoLegacyBlockNumberChanges(address(cryptoLegacy));
    assertEq(cryptoLegacyBlockNumbers.length, 1);
    assertEq(cryptoLegacyBlockNumbers[cryptoLegacyBlockNumbers.length - 1], block.number);

    cryptoLegacyGot = beneficiaryRegistry.getCryptoLegacyListByBeneficiary(addressToHash(bobBeneficiary3));
    assertEq(cryptoLegacyGot.length, 0);

    vm.roll(150);

    vm.startPrank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.AlreadySet.selector);
    cryptoLegacy.beneficiarySwitch(keccak256(abi.encode(bobBeneficiary1)));
    vm.expectRevert(ICryptoLegacy.AlreadySet.selector);
    cryptoLegacy.beneficiarySwitch(keccak256(abi.encode(bobBeneficiary2)));

    cryptoLegacy.beneficiarySwitch(keccak256(abi.encode(bobBeneficiary3)));

    vm.stopPrank();

    cryptoLegacyGot = beneficiaryRegistry.getCryptoLegacyListByBeneficiary(addressToHash(bobBeneficiary1));
    assertEq(cryptoLegacyGot.length, 0);

    cryptoLegacyBlockNumbers = beneficiaryRegistry.getCryptoLegacyBlockNumberChanges(address(cryptoLegacy));
    assertEq(cryptoLegacyBlockNumbers.length, 2);
    assertEq(cryptoLegacyBlockNumbers[cryptoLegacyBlockNumbers.length - 1], block.number);

    cryptoLegacyGot = beneficiaryRegistry.getCryptoLegacyListByBeneficiary(addressToHash(bobBeneficiary3));
    assertEq(cryptoLegacyGot.length, 1);
    assertEq(cryptoLegacyGot[0], address(cryptoLegacy));

    assertEq(cryptoLegacyGot[0], address(cryptoLegacy));

    clListData = cryptoLegacyLens.getCryptoLegacyListData(_getEmptyAddressList());

    assertEq(beneficiaryArr.length, clListData.beneficiaries.length);
    assertEq(clListData.beneficiaries[0], addressToHash(bobBeneficiary2));
    assertEq(clListData.beneficiaries[1], addressToHash(bobBeneficiary3));

    assertEq(beneficiaryConfigArr.length, clListData.beneficiaryConfigArr.length);
    assertEq(beneficiaryConfigArr[0].shareBps, clListData.beneficiaryConfigArr[1].shareBps);
    assertEq(beneficiaryConfigArr[0].claimDelay, clListData.beneficiaryConfigArr[1].claimDelay);
    assertEq(beneficiaryConfigArr[0].vestingPeriod, clListData.beneficiaryConfigArr[1].vestingPeriod);
    assertEq(beneficiaryConfigArr[1].shareBps, clListData.beneficiaryConfigArr[0].shareBps);
    assertEq(beneficiaryConfigArr[1].claimDelay, clListData.beneficiaryConfigArr[0].claimDelay);
    assertEq(beneficiaryConfigArr[1].vestingPeriod, clListData.beneficiaryConfigArr[0].vestingPeriod);

    vm.warp(block.timestamp + 2);

    vm.prank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);

    vm.prank(bobBeneficiary3);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);

    assertEq(mockToken1.balanceOf(bobBeneficiary2), 3 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 6 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 0.8 ether);

    (tokenData, startDate, endDate) = cryptoLegacyLens.getVestedAndClaimedData(addressToHash(bobBeneficiary2), _getOneAddressList(address(mockToken1)));
    assertEq(tokenData[0].claimedAmount, 3 ether);
    assertEq(tokenData[0].vestedAmount, 4.2 ether);
    assertEq(tokenData[0].totalAmount, 60 ether);

    vm.warp(block.timestamp + 2);

    vm.prank(bob);
    mockToken1.transfer(address(cryptoLegacy), 100 ether);

    clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));

    vm.startPrank(bobBeneficiary3);
    assertEq(clListData.tokenDistributions[0].amountToDistribute, 100 ether);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);
    clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));
    assertEq(clListData.tokenDistributions[0].amountToDistribute, 200 ether);

    (tokenData, startDate, endDate) = cryptoLegacyLens.getVestedAndClaimedData(addressToHash(bobBeneficiary2), _getOneAddressList(address(mockToken1)));
    assertEq(tokenData[0].claimedAmount, 3 ether);
    assertEq(tokenData[0].vestedAmount, 10.8 ether);
    assertEq(tokenData[0].totalAmount, 120 ether);

    assertEq(mockToken1.balanceOf(bobBeneficiary2), 3 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 6 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 9.2 ether);
    vm.stopPrank();

    vm.prank(owner);
    mockToken1.mockTransferFrom(address(cryptoLegacy), address(1), 50 ether);

    vm.warp(block.timestamp + 10);

    clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));

    vm.startPrank(bobBeneficiary3);
    assertEq(clListData.tokenDistributions[0].amountToDistribute, 200 ether);
    assertEq(clListData.tokenDistributions[0].totalClaimedAmount, 18.2 ether);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);
    clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));
    assertEq(clListData.tokenDistributions[0].amountToDistribute, 150 ether);

    assertEq(mockToken1.balanceOf(bobBeneficiary2), 3 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 11.4 ether);

    vm.startPrank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);

    assertEq(mockToken1.balanceOf(bobBeneficiary2), 17.1 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 11.4 ether);

    vm.warp(block.timestamp + 10);
    vm.startPrank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);
    vm.startPrank(bobBeneficiary3);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);

    assertEq(mockToken1.balanceOf(bobBeneficiary2), 26.1 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 17.4 ether);

    vm.warp(block.timestamp + 100);
    vm.startPrank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);
    vm.startPrank(bobBeneficiary3);
    cryptoLegacy.beneficiaryClaim(_getOneAddressList(address(mockToken1)), address(0), 0);

    assertEq(mockToken1.balanceOf(bobBeneficiary1), 6 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary2), 90 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 54 ether);
  }

  function testCreateCryptoLegacyVestingAndAddTokens() public {
    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacyWithVesting();

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();

    vm.warp(block.timestamp + clData.challengeTimeout + 1);
    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(mockToken1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);

    vm.startPrank(bobBeneficiary1);
    vm.warp(block.timestamp + 10 + 1);
    cryptoLegacy.beneficiaryClaim{value: updateFee}(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 0.8 ether);
    (ICryptoLegacyLens.BeneficiaryTokenData[] memory result, uint64 startDate, uint64 endDate) = cryptoLegacyLens.getVestedAndClaimedData(addressToHash(bobBeneficiary1), _getOneAddressList(address(mockToken1)));
    assertEq(result[0].vestedAmount, 0.8 ether);
    assertEq(result[0].claimedAmount, 0.8 ether);

    vm.warp(block.timestamp + 1);

    (result, startDate, endDate) = cryptoLegacyLens.getVestedAndClaimedData(addressToHash(bobBeneficiary1), _getOneAddressList(address(mockToken1)));
    assertEq(result[0].vestedAmount, 1.2 ether);
    assertEq(result[0].claimedAmount, 0.8 ether);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 1.2 ether);
    vm.stopPrank();

    vm.prank(bob);
    mockToken1.transfer(address(cryptoLegacy), 100 ether);

    vm.startPrank(bobBeneficiary1);
    ICryptoLegacyLens.CryptoLegacyListData memory clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));

    assertEq(clListData.tokenDistributions[0].amountToDistribute, 100 ether);
    vm.warp(block.timestamp + 1);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));
    assertEq(clListData.tokenDistributions[0].amountToDistribute, 200 ether);

    assertEq(mockToken1.balanceOf(bobBeneficiary1), 3.2 ether);

    vm.warp(block.timestamp + 200);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 80 ether);
    vm.stopPrank();

    vm.startPrank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary2), 120 ether);
    vm.stopPrank();
  }

  function testCreateCryptoLegacyVestingAndSubTokens() public {
    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacyWithVesting();

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();

    vm.warp(block.timestamp + clData.challengeTimeout + 1);
    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(mockToken1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);

    vm.startPrank(bobBeneficiary1);
    vm.warp(block.timestamp + 10 + 1);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 0.8 ether);

    vm.warp(block.timestamp + 1);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 1.2 ether);
    vm.stopPrank();

    vm.prank(owner);
    mockToken1.mockTransferFrom(address(cryptoLegacy), address(1), 50 ether);

    ICryptoLegacyLens.CryptoLegacyListData memory clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));
    assertEq(clListData.tokenDistributions[0].amountToDistribute, 100 ether);
    vm.warp(block.timestamp + 10);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    clListData = cryptoLegacyLens.getCryptoLegacyListData(_getOneAddressList(address(mockToken1)));
    assertEq(clListData.tokenDistributions[0].amountToDistribute, 50 ether);

    vm.prank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);

    assertEq(mockToken1.balanceOf(bobBeneficiary1), 2.6 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary2), 0.9 ether);

    vm.warp(block.timestamp + 200);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 20 ether);

    vm.prank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary2), 30 ether);
  }

  function testIncreaseUpdateFee() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getOneInitPluginList(lensPlugin));
    vm.warp(block.timestamp + 1);

    vm.prank(bob);
    vm.expectEmit(true, false, false, false);
    emit ICryptoLegacy.FeePaidByDefault(bytes8(0), false, 0, address(9), 0);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.expectRevert("Ownable: caller is not the owner");
    feeRegistry.setContractCaseFee(address(buildManager), 2, updateFee * 2);

    vm.prank(owner);
    feeRegistry.setContractCaseFee(address(buildManager), 2, updateFee * 2);

    vm.warp(block.timestamp + cryptoLegacyLens.getCryptoLegacyBaseData().updateInterval + 1);

    vm.prank(bob);
    vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.IncorrectFee.selector, updateFee * 2));
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(bob);
    vm.expectEmit(true, false, false, false);
    emit ICryptoLegacy.FeePaidByDefault(bytes8(0), false, 0, address(9), 0);
    cryptoLegacy.update{value: updateFee * 2}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(owner);
    feeRegistry.setContractCaseFee(address(buildManager), 2, updateFee);

    bytes8 customRefCode = 0x0123456789abcdef;
    vm.prank(alice);
    buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());

    (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(dan, buildFee, customRefCode, _getOneInitPluginList(lensPlugin));

    uint256 discount = updateFee * refDiscountPct / 10000;
    uint256 share = updateFee * refSharePct / 10000;

    assertEq(feeRegistry.getContractCaseFee(address(buildManager), buildManager.REGISTRY_UPDATE_CASE()), updateFee);
    (uint256 discountGot, uint256 shareGot, ) = feeRegistry.calculateFee(customRefCode, updateFee);
    assertEq(discount, discountGot);
    assertEq(share, shareGot);
    vm.expectEmit(true, true, true, true);
    emit IFeeRegistry.SentFee(alice, customRefCode, aliceRecipient, share);

    vm.warp(block.timestamp + cryptoLegacyLens.getCryptoLegacyBaseData().updateInterval + 1);

    vm.prank(dan);
    vm.expectEmit(true, false, false, false);
    emit ICryptoLegacy.FeePaidByDefault(customRefCode, false, 0, address(9), 0);
    cryptoLegacy.update{value: updateFee - discount}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(owner);
    feeRegistry.setContractCaseFee(address(buildManager), 2, updateFee * 2);

    vm.warp(block.timestamp + cryptoLegacyLens.getCryptoLegacyBaseData().updateInterval + 1);

    vm.prank(dan);
    vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.IncorrectFee.selector, updateFee * 2 - discount * 2));
    cryptoLegacy.update{value: updateFee - discount}(_getEmptyUintList(), _getEmptyUintList());

    address incorrectRecipient = address(new MockMaliciousERC20(address(0)));
    vm.prank(alice);
    feeRegistry.changeRecipientReferrer(customRefCode, incorrectRecipient, _getEmptyUintList(), _getEmptyUintList());

    assertEq(feeRegistry.refererByCode(customRefCode).accumulatedFee, 0);
    vm.expectEmit(true, true, true, true);
    emit IFeeRegistry.AccumulateFee(alice, customRefCode, incorrectRecipient, share * 2);

    vm.prank(dan);
    vm.expectEmit(true, false, false, false);
    emit ICryptoLegacy.FeePaidByDefault(customRefCode, false, 0, address(9), 0);
    cryptoLegacy.update{value: updateFee * 2 - discount * 2}(_getEmptyUintList(), _getEmptyUintList());

    assertEq(feeRegistry.refererByCode(customRefCode).accumulatedFee, share * 2);

    vm.expectRevert();
    feeRegistry.withdrawReferralAccumulatedFee(customRefCode);

    vm.prank(alice);
    feeRegistry.changeRecipientReferrer(customRefCode, aliceRecipient, _getEmptyUintList(), _getEmptyUintList());

    uint256 aliceRecipientBalance = aliceRecipient.balance;
    vm.expectEmit(true, true, true, true);
    emit IFeeRegistry.WithdrawRefFee(aliceRecipient, share * 2);
    feeRegistry.withdrawReferralAccumulatedFee(customRefCode);
    assertEq(aliceRecipient.balance, aliceRecipientBalance + share * 2);
    assertEq(feeRegistry.refererByCode(customRefCode).accumulatedFee, 0);
  }

  function testReplaceBasicPlugin() public {
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    address mockTestPlugin = address(new MockTestPlugin());
    address mockTest2Plugin = address(new MockTest2Plugin());

    vm.startPrank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");
    pluginsRegistry.addPlugin(mockTestPlugin, "");
    pluginsRegistry.addPlugin(mockTest2Plugin, "");
    vm.stopPrank();

    (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getOneInitPluginList(lensPlugin));
    vm.warp(block.timestamp + 1);

    vm.prank(bob);
    address[] memory ps = new address[](1);
    ps[0] = mockTestPlugin;
    CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(ps);
    assertEq(MockTestPlugin(address(cryptoLegacy)).test(), 1);

    vm.prank(bob);
    address[] memory ps2 = new address[](1);
    ps2[0] = mockTest2Plugin;
    CryptoLegacy(payable(address(cryptoLegacy))).replacePlugin(ps, ps2);
    assertEq(MockTestPlugin(address(cryptoLegacy)).test(), 2);

    vm.prank(bob);
    address[] memory ps2i = new address[](1);
    ps2i[0] = mockTest2Plugin;
    CryptoLegacy(payable(address(cryptoLegacy))).removePluginList(ps2i);
    vm.expectRevert();
    MockTestPlugin(address(cryptoLegacy)).test();
  }

  function testReplaceClaimFunction() public {
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    address beneficiaryDistributionRightsPlugin = address(new BeneficiaryPluginAddRights());
    address mockClaimPlugin = address(new MockClaimPlugin());

    vm.startPrank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");
    pluginsRegistry.addPlugin(beneficiaryDistributionRightsPlugin, "");
    vm.stopPrank();

    (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getTwoInitPluginsList(lensPlugin, beneficiaryDistributionRightsPlugin));
    vm.warp(block.timestamp + 1);

    vm.prank(bob);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval + 1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(mockToken1);
    BeneficiaryPluginAddRights cryptoLegacyBeneficiaryPluginLegacy = BeneficiaryPluginAddRights(address(cryptoLegacy));
    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;

    (bytes32[] memory voters, uint256 requiredConfirmations) = cryptoLegacyBeneficiaryPluginLegacy.barGetVotersAndConfirmations();
    assertEq(requiredConfirmations, 2);
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary1));
    assertEq(voters[1], addressToHash(bobBeneficiary2));

    ISafeMinimalMultisig.ProposalWithStatus[] memory proposalsWithStatuses;
    (voters, requiredConfirmations, proposalsWithStatuses) = cryptoLegacyBeneficiaryPluginLegacy.barGetProposalListWithStatuses();
    assertEq(requiredConfirmations, 2);
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary1));
    assertEq(voters[1], addressToHash(bobBeneficiary2));
    assertEq(proposalsWithStatuses.length, 0);

    vm.prank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.TooEarly.selector);
    cryptoLegacyBeneficiaryPluginLegacy.barAddPluginList(_getOneAddressList(mockClaimPlugin));

    vm.expectRevert(ICryptoLegacy.TooEarly.selector);
    vm.prank(bobBeneficiary1);
    cryptoLegacyBeneficiaryPluginLegacy.barPropose(BeneficiaryPluginAddRights.barAddPluginList.selector, abi.encode(_getOneAddressList(mockClaimPlugin)));

    uint256 distributionStartAt = block.timestamp + clData.challengeTimeout;
    vm.warp(distributionStartAt + 1);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.beneficiaryClaim{value: updateFee}(_tokens, address(0), 0);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 40 ether);

    vm.prank(owner);
    pluginsRegistry.addPlugin(mockClaimPlugin, "");

    vm.expectRevert(ISafeMinimalMultisig.MultisigVoterNotAllowed.selector);
    cryptoLegacyBeneficiaryPluginLegacy.barPropose(BeneficiaryPluginAddRights.barAddPluginList.selector, abi.encode(_getOneAddressList(mockClaimPlugin)));

    vm.expectRevert(ISafeMinimalMultisig.MultisigMethodNotAllowed.selector);
    vm.prank(bobBeneficiary1);
    cryptoLegacyBeneficiaryPluginLegacy.barPropose(BeneficiaryPluginAddRights.barConfirm.selector, abi.encode(0));

    vm.prank(bobBeneficiary1);
    cryptoLegacyBeneficiaryPluginLegacy.barPropose(BeneficiaryPluginAddRights.barAddPluginList.selector, abi.encode(_getOneAddressList(mockClaimPlugin)));
    (voters, requiredConfirmations, proposalsWithStatuses) = cryptoLegacyBeneficiaryPluginLegacy.barGetProposalListWithStatuses();
    assertEq(requiredConfirmations, 2);
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary1));
    assertEq(voters[1], addressToHash(bobBeneficiary2));
    assertEq(proposalsWithStatuses[0].confirmedBy[0], true);
    assertEq(proposalsWithStatuses[0].confirmedBy[1], false);
    assertEq(proposalsWithStatuses[0].proposal.confirms, 1);
    assertEq(proposalsWithStatuses[0].proposal.executed, false);
    assertEq(proposalsWithStatuses[0].proposal.selector, BeneficiaryPluginAddRights.barAddPluginList.selector);
    assertEq(proposalsWithStatuses[0].proposal.params, abi.encode(_getOneAddressList(mockClaimPlugin)));

    vm.prank(bobBeneficiary1);
    cryptoLegacy.beneficiarySwitch(addressToHash(bobBeneficiary3));

    (voters, requiredConfirmations, proposalsWithStatuses) = cryptoLegacyBeneficiaryPluginLegacy.barGetProposalListWithStatuses();
    assertEq(requiredConfirmations, 2);
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary2));
    assertEq(voters[1], addressToHash(bobBeneficiary3));
    assertEq(proposalsWithStatuses[0].confirmedBy[0], false);
    assertEq(proposalsWithStatuses[0].confirmedBy[1], false);
    assertEq(proposalsWithStatuses[0].proposal.confirms, 0);
    assertEq(proposalsWithStatuses[0].proposal.executed, false);

    vm.prank(bobBeneficiary3);
    cryptoLegacyBeneficiaryPluginLegacy.barConfirm(0);

    (voters, requiredConfirmations, proposalsWithStatuses) = cryptoLegacyBeneficiaryPluginLegacy.barGetProposalListWithStatuses();
    assertEq(requiredConfirmations, 2);
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary2));
    assertEq(voters[1], addressToHash(bobBeneficiary3));
    assertEq(proposalsWithStatuses[0].confirmedBy[0], false);
    assertEq(proposalsWithStatuses[0].confirmedBy[1], true);
    assertEq(proposalsWithStatuses[0].proposal.confirms, 1);
    assertEq(proposalsWithStatuses[0].proposal.executed, false);

    vm.prank(bobBeneficiary2);
    cryptoLegacyBeneficiaryPluginLegacy.barConfirm(0);
    ( , , proposalsWithStatuses) = cryptoLegacyBeneficiaryPluginLegacy.barGetProposalListWithStatuses();
    assertEq(proposalsWithStatuses[0].proposal.confirms, 2);
    assertEq(proposalsWithStatuses[0].proposal.executed, true);
    assertEq(proposalsWithStatuses[0].confirmedBy[0], true);
    assertEq(proposalsWithStatuses[0].confirmedBy[1], true);

    ISafeMinimalMultisig.ProposalWithStatus memory proposalWithStatus;
    (voters, requiredConfirmations, proposalWithStatus) = cryptoLegacyBeneficiaryPluginLegacy.barGetProposalWithStatus(0);
    assertEq(requiredConfirmations, 2);
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary2));
    assertEq(voters[1], addressToHash(bobBeneficiary3));
    assertEq(proposalWithStatus.proposal.confirms, 2);
    assertEq(proposalWithStatus.proposal.executed, true);
    assertEq(proposalWithStatus.proposal.selector, BeneficiaryPluginAddRights.barAddPluginList.selector);
    assertEq(proposalWithStatus.proposal.params, abi.encode(_getOneAddressList(mockClaimPlugin)));
    assertEq(proposalWithStatus.confirmedBy[0], true);
    assertEq(proposalWithStatus.confirmedBy[1], true);

    (voters, requiredConfirmations) = cryptoLegacyBeneficiaryPluginLegacy.barGetVotersAndConfirmations();
    assertEq(requiredConfirmations, 2);
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary2));
    assertEq(voters[1], addressToHash(bobBeneficiary3));

    MockClaimPlugin mockClaimPluginLegacy = MockClaimPlugin(address(cryptoLegacy));
    mockClaimPluginLegacy.setDefaultClaimDisabled();

    vm.prank(bobBeneficiary3);
    vm.expectRevert(ICryptoLegacy.DisabledFunc.selector);
    cryptoLegacy.beneficiaryClaim{value: updateFee}(_tokens, address(0), 0);

    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    mockClaimPluginLegacy.mockBeneficiaryClaim(_tokens, address(0), 0);

    vm.prank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    mockClaimPluginLegacy.mockBeneficiaryClaim(_tokens, address(0), 0);

    vm.prank(bobBeneficiary3);
    mockClaimPluginLegacy.mockBeneficiaryClaim(_tokens, address(0), 0);

    assertEq(mockToken1.balanceOf(bobBeneficiary1), 40 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary3), 60 ether);
  }

  function testBarMulisigSetFunction() public {
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    address beneficiaryDistributionRightsPlugin = address(new BeneficiaryPluginAddRights());

    vm.startPrank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");
    pluginsRegistry.addPlugin(beneficiaryDistributionRightsPlugin, "");
    vm.stopPrank();

    (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getTwoInitPluginsList(lensPlugin, beneficiaryDistributionRightsPlugin));
    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval + 1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();
    BeneficiaryPluginAddRights cryptoLegacyBeneficiaryPluginLegacy = BeneficiaryPluginAddRights(address(cryptoLegacy));

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacyBeneficiaryPluginLegacy.barSetMultisigConfig(1);

    (bytes32[] memory voters, uint256 requiredConfirmations) = cryptoLegacyBeneficiaryPluginLegacy.barGetVotersAndConfirmations();

    assertEq(requiredConfirmations, 2);
    assertEq(uint(cryptoLegacyBeneficiaryPluginLegacy.barGetInitializationStatus()), uint(ISafeMinimalMultisig.InitializationStatus.NOT_INITIALIZED_NO_NEED));
    vm.prank(bob);
    cryptoLegacyBeneficiaryPluginLegacy.barSetMultisigConfig(1);

    (voters, requiredConfirmations) = cryptoLegacyBeneficiaryPluginLegacy.barGetVotersAndConfirmations();
    assertEq(requiredConfirmations, 1);
    assertEq(uint(cryptoLegacyBeneficiaryPluginLegacy.barGetInitializationStatus()), uint(ISafeMinimalMultisig.InitializationStatus.INITIALIZED));

    uint256 distributionStartAt = block.timestamp + clData.challengeTimeout;
    vm.warp(distributionStartAt + 1);

    vm.prank(bobBeneficiary1);
    cryptoLegacyBeneficiaryPluginLegacy.barPropose(BeneficiaryPluginAddRights.barSetMultisigConfig.selector, abi.encode(2));
    (voters, requiredConfirmations) = cryptoLegacyBeneficiaryPluginLegacy.barGetVotersAndConfirmations();
    assertEq(requiredConfirmations, 2);
  }

  function testDefaultMultisigConfirmations() public pure {
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(1), 1);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(2), 2);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(3), 2);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(4), 3);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(5), 3);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(6), 4);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(7), 4);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(8), 5);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(9), 5);
    assertEq(LibSafeMinimalMultisig._calcDefaultConfirmations(10), 6);
  }

  function testTrustedGuardians() public {
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    {
      address trustedGuardiansPlugin = address(new TrustedGuardiansPlugin());
      address legacyRecoveryPlugin = address(new LegacyRecoveryPlugin());

      vm.startPrank(owner);
      pluginsRegistry.addPlugin(lensPlugin, "");
      pluginsRegistry.addPlugin(trustedGuardiansPlugin, "");
      pluginsRegistry.addPlugin(legacyRecoveryPlugin, "");
      vm.stopPrank();

      (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getThreeInitPluginsList(lensPlugin, trustedGuardiansPlugin, legacyRecoveryPlugin));
      vm.warp(block.timestamp + 1);
    }
    LegacyRecoveryPlugin legacyRecoveryPluginLegacy = LegacyRecoveryPlugin(address(cryptoLegacy));

    vm.prank(bob);
    vm.expectRevert(ISafeMinimalMultisig.MultisigIncorrectRequiredConfirmations.selector);
    legacyRecoveryPluginLegacy.lrSetMultisigConfig(_getTwoBytes32List(addressToHash(alice), addressToHash(dan)), 3);
    vm.prank(bob);
    vm.expectRevert(ISafeMinimalMultisig.MultisigIncorrectRequiredConfirmations.selector);
    legacyRecoveryPluginLegacy.lrSetMultisigConfig(_getTwoBytes32List(addressToHash(alice), addressToHash(dan)), 0);

    vm.prank(bob);
    legacyRecoveryPluginLegacy.lrSetMultisigConfig(_getTwoBytes32List(addressToHash(alice), addressToHash(dan)), 1);

    vm.prank(bob);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    TrustedGuardiansPlugin trustedGuardianPluginLegacy = TrustedGuardiansPlugin(address(cryptoLegacy));

    ICryptoLegacyLens.CryptoLegacyListData memory clListData = cryptoLegacyLens.getCryptoLegacyListData(_getEmptyAddressList());

    (
      bytes32[] memory guardians,
      bytes32[] memory guardiansVoted,
      uint8 guardiansThreshold,
      uint64 guardiansChallengeTimeout
    ) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardians.length, clListData.beneficiaries.length);
    assertEq(guardians[0], clListData.beneficiaries[0]);
    assertEq(guardians[1], clListData.beneficiaries[1]);
    assertEq(guardiansVoted.length, 0);
    assertEq(guardiansThreshold, 2);
    assertEq(guardiansChallengeTimeout, 30 days);

    vm.expectRevert(ITrustedGuardiansPlugin.NotGuardian.selector);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    vm.prank(bobBeneficiary1);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, 0);

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 1);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary1));

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    trustedGuardianPluginLegacy.resetGuardianVoting();

    vm.prank(bob);
    trustedGuardianPluginLegacy.resetGuardianVoting();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 0);

    ITrustedGuardiansPlugin.GuardianToChange[] memory newGuardians = new ITrustedGuardiansPlugin.GuardianToChange[](2);
    newGuardians[0] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(dan), true);
    newGuardians[1] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(alice), true);

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    trustedGuardianPluginLegacy.initializeGuardians(newGuardians, 2, 70);

    vm.roll(10);
    vm.prank(bob);
    trustedGuardianPluginLegacy.initializeGuardians(newGuardians, 2, 70);

    address[] memory clList = beneficiaryRegistry.getCryptoLegacyListByGuardian(newGuardians[0].hash);
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    clList = beneficiaryRegistry.getCryptoLegacyListByGuardian(newGuardians[1].hash);
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    clList = beneficiaryRegistry.getCryptoLegacyListByGuardian(addressToHash(bobBeneficiary1));
    assertEq(clList.length, 0);

    vm.prank(bobBeneficiary1);
    vm.expectRevert(ITrustedGuardiansPlugin.NotGuardian.selector);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    vm.prank(dan);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 1);
    assertEq(guardiansVoted[0], addressToHash(dan));

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, 0);

    vm.prank(dan);
    vm.expectRevert(ITrustedGuardiansPlugin.GuardianAlreadyVoted.selector);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    vm.prank(alice);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 0);

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, block.timestamp + 70);

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    trustedGuardianPluginLegacy.setGuardiansConfig(1, 80);

    newGuardians = new ITrustedGuardiansPlugin.GuardianToChange[](4);
    newGuardians[0] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(dan), false);
    newGuardians[1] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(alice), false);
    newGuardians[2] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(bobBeneficiary1), true);
    newGuardians[3] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(bobBeneficiary2), true);

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    trustedGuardianPluginLegacy.setGuardians(newGuardians);

    vm.expectRevert(ISafeMinimalMultisig.MultisigVoterNotAllowed.selector);
    legacyRecoveryPluginLegacy.lrPropose(LegacyRecoveryPlugin.lrResetGuardianVoting.selector, new bytes(0));

    vm.prank(alice);
    legacyRecoveryPluginLegacy.lrPropose(LegacyRecoveryPlugin.lrResetGuardianVoting.selector, new bytes(0));

    vm.startPrank(bob);

    vm.expectRevert(abi.encodeWithSelector(ITrustedGuardiansPlugin.MaxGuardiansTimeout.selector, 30 days));
    trustedGuardianPluginLegacy.setGuardiansConfig(1, 31 days);

    vm.roll(20);

//    trustedGuardianPluginLegacy.resetGuardianVoting();
    trustedGuardianPluginLegacy.setGuardiansConfig(1, 80);
    trustedGuardianPluginLegacy.setGuardians(newGuardians);

    clList = beneficiaryRegistry.getCryptoLegacyListByGuardian(newGuardians[0].hash);
    assertEq(clList.length, 0);
    clList = beneficiaryRegistry.getCryptoLegacyListByGuardian(newGuardians[1].hash);
    assertEq(clList.length, 0);

    clList = beneficiaryRegistry.getCryptoLegacyListByGuardian(newGuardians[2].hash);
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    clList = beneficiaryRegistry.getCryptoLegacyListByGuardian(newGuardians[3].hash);
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    ( , , guardiansThreshold, guardiansChallengeTimeout) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansThreshold, 1);
    assertEq(guardiansChallengeTimeout, 80);

    vm.roll(30);
    trustedGuardianPluginLegacy.setGuardiansConfig(2, 80);

    ( , , guardiansThreshold, ) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansThreshold, 2);

    vm.stopPrank();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 0);

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, 0);

    vm.prank(bobBeneficiary1);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, 0);

    vm.prank(bobBeneficiary2);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, block.timestamp + 80);

    vm.warp(block.timestamp + 80);

    vm.expectRevert(ICryptoLegacy.TooEarly.selector);
    vm.prank(bobBeneficiary2);
    trustedGuardianPluginLegacy.guardiansTransferTreasuryTokensToLegacy(_getOneAddressList(treasury), _getOneAddressList(address(mockToken1)));

    vm.warp(block.timestamp + 1);

    vm.expectRevert(ITrustedGuardiansPlugin.NotGuardian.selector);
    trustedGuardianPluginLegacy.guardiansTransferTreasuryTokensToLegacy(_getOneAddressList(treasury), _getOneAddressList(address(mockToken1)));

    assertEq(mockToken1.balanceOf(address(cryptoLegacy)), 0);
    vm.prank(bobBeneficiary1);
    trustedGuardianPluginLegacy.guardiansTransferTreasuryTokensToLegacy(_getOneAddressList(treasury), _getOneAddressList(address(mockToken1)));

    assertEq(mockToken1.balanceOf(address(cryptoLegacy)), 100 ether);
  }

  function testSwitchTrustedGuardians() public {
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    {
      address trustedGuardiansPlugin = address(new TrustedGuardiansPlugin());
      address legacyRecoveryPlugin = address(new LegacyRecoveryPlugin());

      vm.startPrank(owner);
      pluginsRegistry.addPlugin(lensPlugin, "");
      pluginsRegistry.addPlugin(trustedGuardiansPlugin, "");
      pluginsRegistry.addPlugin(legacyRecoveryPlugin, "");
      vm.stopPrank();

      bytes32[] memory beneficiaryArr = new bytes32[](4);
      beneficiaryArr[0] = addressToHash(bobBeneficiary1);
      beneficiaryArr[1] = addressToHash(bobBeneficiary2);
      beneficiaryArr[2] = addressToHash(bobBeneficiary3);
      beneficiaryArr[3] = addressToHash(bobBeneficiary4);
      ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](4);
      beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(0, 0, 2000);
      beneficiaryConfigArr[1] = ICryptoLegacy.BeneficiaryConfig(0, 0, 2000);
      beneficiaryConfigArr[2] = ICryptoLegacy.BeneficiaryConfig(0, 0, 3000);
      beneficiaryConfigArr[3] = ICryptoLegacy.BeneficiaryConfig(0, 0, 3000);

      vm.prank(bob);
      ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(bytes8(0), beneficiaryArr, beneficiaryConfigArr, _getThreeInitPluginsList(lensPlugin, trustedGuardiansPlugin, legacyRecoveryPlugin), updateInterval, challengeTimeout);
      buildRoll();
      address payable cl = buildManager.buildCryptoLegacy{value: buildFee}(buildArgs, _getRefArgsStruct(bob), _getCreate2ArgsStruct(address(0), bytes32(uint(0))));
      cryptoLegacy = CryptoLegacyBasePlugin(cl);
      cryptoLegacyLens = ICryptoLegacyLens(cl);

      vm.warp(block.timestamp + 1);
    }

    vm.prank(bob);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    TrustedGuardiansPlugin trustedGuardianPluginLegacy = TrustedGuardiansPlugin(address(cryptoLegacy));

    ICryptoLegacyLens.CryptoLegacyListData memory clListData = cryptoLegacyLens.getCryptoLegacyListData(_getEmptyAddressList());

    bytes32[] memory guardiansVoted;
    {
      bytes32[] memory guardians;
      uint8 guardiansThreshold;
      uint64 guardiansChallengeTimeout;
      (
        guardians,
        guardiansVoted,
        guardiansThreshold,
        guardiansChallengeTimeout
      ) = trustedGuardianPluginLegacy.getGuardiansData();
      assertEq(guardians.length, clListData.beneficiaries.length);
      assertEq(guardians[0], clListData.beneficiaries[0]);
      assertEq(guardians[1], clListData.beneficiaries[1]);
      assertEq(guardians[2], clListData.beneficiaries[2]);
      assertEq(guardians[3], clListData.beneficiaries[3]);
      assertEq(guardiansVoted.length, 0);
      assertEq(guardiansThreshold, 3);
      assertEq(guardiansChallengeTimeout, 30 days);
    }

    vm.prank(bob);
    ITrustedGuardiansPlugin.GuardianToChange[] memory _guardians = new ITrustedGuardiansPlugin.GuardianToChange[](0);
    trustedGuardianPluginLegacy.initializeGuardians(_guardians, 4, 30 days);

    vm.prank(bobBeneficiary3);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, 0);

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 1);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary3));

    vm.prank(bobBeneficiary3);
    cryptoLegacy.beneficiarySwitch(addressToHash(dan));

    vm.prank(bobBeneficiary3);
    vm.expectRevert(ITrustedGuardiansPlugin.NotGuardian.selector);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    vm.prank(bobBeneficiary2);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 1);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary2));

    vm.prank(dan);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 2);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary2));
    assertEq(guardiansVoted[1], addressToHash(dan));

    vm.prank(dan);
    cryptoLegacy.beneficiarySwitch(addressToHash(bobBeneficiary3));

    vm.prank(bobBeneficiary3);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 2);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary2));
    assertEq(guardiansVoted[1], addressToHash(bobBeneficiary3));

    vm.prank(bobBeneficiary2);
    cryptoLegacy.beneficiarySwitch(addressToHash(dan));

    vm.prank(dan);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 2);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary3));
    assertEq(guardiansVoted[1], addressToHash(dan));

    vm.prank(bobBeneficiary1);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 3);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary3));
    assertEq(guardiansVoted[1], addressToHash(dan));
    assertEq(guardiansVoted[2], addressToHash(bobBeneficiary1));

    vm.prank(bobBeneficiary3);
    cryptoLegacy.beneficiarySwitch(addressToHash(charlie));

    vm.prank(charlie);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 3);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary1));
    assertEq(guardiansVoted[1], addressToHash(dan));
    assertEq(guardiansVoted[2], addressToHash(charlie));

    vm.prank(dan);
    cryptoLegacy.beneficiarySwitch(addressToHash(bobBeneficiary3));

    vm.prank(bobBeneficiary3);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 3);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary1));
    assertEq(guardiansVoted[1], addressToHash(charlie));
    assertEq(guardiansVoted[2], addressToHash(bobBeneficiary3));

    vm.prank(bobBeneficiary3);
    cryptoLegacy.beneficiarySwitch(addressToHash(dan));

    vm.prank(dan);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 3);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary1));
    assertEq(guardiansVoted[1], addressToHash(charlie));
    assertEq(guardiansVoted[2], addressToHash(dan));

    vm.prank(dan);
    cryptoLegacy.beneficiarySwitch(addressToHash(bobBeneficiary3));

    vm.prank(charlie);
    cryptoLegacy.beneficiarySwitch(addressToHash(bobBeneficiary2));

    vm.prank(bobBeneficiary1);
    cryptoLegacy.beneficiarySwitch(addressToHash(alice));

    vm.prank(bobBeneficiary2);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    ( , guardiansVoted, ,) = trustedGuardianPluginLegacy.getGuardiansData();
    assertEq(guardiansVoted.length, 1);
    assertEq(guardiansVoted[0], addressToHash(bobBeneficiary2));

    vm.prank(alice);
    cryptoLegacy.beneficiarySwitch(addressToHash(bobBeneficiary1));

    vm.prank(bobBeneficiary1);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    vm.prank(bobBeneficiary3);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    vm.prank(bobBeneficiary4);
    trustedGuardianPluginLegacy.guardiansVoteForDistribution();

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.distributionStartAt, block.timestamp + 30 days);

    vm.prank(bob);
    trustedGuardianPluginLegacy.resetGuardianVoting();

    CryptoLegacyExternalLens externalLens = new CryptoLegacyExternalLens();

    (
      address[] memory listByBeneficiary,
      bool[] memory beneficiaryDefaultGuardian,
      ,
      address[] memory listByGuardian,
    ) = externalLens.getCryptoLegacyListWithStatuses(beneficiaryRegistry, addressToHash(bobBeneficiary1));
    assertEq(listByBeneficiary.length, 1);
    assertEq(listByBeneficiary[0], address(cryptoLegacy));
    assertEq(beneficiaryDefaultGuardian.length, 1);
    assertEq(beneficiaryDefaultGuardian[0], true);
    assertEq(listByGuardian.length, 0);

    ITrustedGuardiansPlugin.GuardianToChange[] memory newGuardians = new ITrustedGuardiansPlugin.GuardianToChange[](4);
    newGuardians[0] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(bobBeneficiary1), true);
    newGuardians[1] = ITrustedGuardiansPlugin.GuardianToChange(addressToHash(alice), true);

    vm.prank(bob);
    trustedGuardianPluginLegacy.setGuardians(newGuardians);

    (listByBeneficiary, beneficiaryDefaultGuardian, , listByGuardian, ) = externalLens.getCryptoLegacyListWithStatuses(beneficiaryRegistry, addressToHash(bobBeneficiary1));
    assertEq(listByBeneficiary.length, 1);
    assertEq(listByBeneficiary[0], address(cryptoLegacy));
    assertEq(beneficiaryDefaultGuardian.length, 1);
    assertEq(beneficiaryDefaultGuardian[0], false);
    assertEq(listByGuardian.length, 1);
    assertEq(listByGuardian[0], address(cryptoLegacy));
  }

  function testLegacyRecoveryPlugin() public {
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    address legacyRecoveryPlugin = address(new LegacyRecoveryPlugin());

    vm.startPrank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");
    pluginsRegistry.addPlugin(legacyRecoveryPlugin, "");
    vm.stopPrank();

    (cryptoLegacy, cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getTwoInitPluginsList(lensPlugin, legacyRecoveryPlugin));
    vm.warp(block.timestamp + 1);

    vm.prank(bob);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), 100 ether);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval + 1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();
    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(mockToken1);

    LegacyRecoveryPlugin legacyRecoveryPluginLegacy = LegacyRecoveryPlugin(address(cryptoLegacy));

    (
      bytes32[] memory voters,
      uint256 requiredConfirmations,
      ISafeMinimalMultisig.ProposalWithStatus[] memory proposalsWithStatuses
    ) = legacyRecoveryPluginLegacy.lrGetProposalListWithStatuses();
    assertEq(voters.length, 0);
    assertEq(requiredConfirmations, 0);

    vm.expectRevert(ISafeMinimalMultisig.MultisigVoterNotAllowed.selector);
    vm.prank(bobBeneficiary1);
    legacyRecoveryPluginLegacy.lrPropose(LegacyRecoveryPlugin.lrTransferTreasuryTokensToLegacy.selector, abi.encode(_treasuries, _tokens));

    voters = new bytes32[](2);
    voters[0] = addressToHash(bobBeneficiary1);
    voters[1] = addressToHash(dan);

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    legacyRecoveryPluginLegacy.lrSetMultisigConfig(voters, 2);

    vm.prank(bob);
    legacyRecoveryPluginLegacy.lrSetMultisigConfig(voters, 2);

    address[] memory clList = beneficiaryRegistry.getCryptoLegacyListByRecovery(addressToHash(bobBeneficiary1));
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    clList = beneficiaryRegistry.getCryptoLegacyListByRecovery(addressToHash(dan));
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    clList = beneficiaryRegistry.getCryptoLegacyListByRecovery(addressToHash(bobBeneficiary2));
    assertEq(clList.length, 0);

    (voters, requiredConfirmations, proposalsWithStatuses) = legacyRecoveryPluginLegacy.lrGetProposalListWithStatuses();
    assertEq(voters.length, 2);
    assertEq(voters[0], addressToHash(bobBeneficiary1));
    assertEq(voters[1], addressToHash(dan));
    assertEq(requiredConfirmations, 2);
    assertEq(proposalsWithStatuses.length, 0);

    vm.expectRevert(ISafeMinimalMultisig.MultisigMethodNotAllowed.selector);
    vm.prank(bobBeneficiary1);
    legacyRecoveryPluginLegacy.lrPropose(LegacyRecoveryPlugin.lrConfirm.selector, abi.encode(0));

    vm.prank(bobBeneficiary1);
    legacyRecoveryPluginLegacy.lrPropose(LegacyRecoveryPlugin.lrTransferTreasuryTokensToLegacy.selector, abi.encode(_treasuries, _tokens));

    (voters, requiredConfirmations, proposalsWithStatuses) = legacyRecoveryPluginLegacy.lrGetProposalListWithStatuses();
    assertEq(proposalsWithStatuses.length, 1);
    assertEq(proposalsWithStatuses[0].confirmedBy.length, 2);
    assertEq(proposalsWithStatuses[0].confirmedBy[0], true);
    assertEq(proposalsWithStatuses[0].confirmedBy[1], false);
    assertEq(proposalsWithStatuses[0].proposal.selector, LegacyRecoveryPlugin.lrTransferTreasuryTokensToLegacy.selector);
    assertEq(proposalsWithStatuses[0].proposal.params, abi.encode(_treasuries, _tokens));
    assertEq(proposalsWithStatuses[0].proposal.executed, false);

    vm.expectRevert(ISafeMinimalMultisig.MultisigAlreadyConfirmed.selector);
    vm.prank(bobBeneficiary1);
    legacyRecoveryPluginLegacy.lrConfirm(0);

    vm.expectRevert(ISafeMinimalMultisig.MultisigVoterNotAllowed.selector);
    vm.prank(bobBeneficiary2);
    legacyRecoveryPluginLegacy.lrConfirm(0);

    vm.prank(dan);
    legacyRecoveryPluginLegacy.lrConfirm(0);

    vm.expectRevert(ISafeMinimalMultisig.MultisigAlreadyExecuted.selector);
    vm.prank(dan);
    legacyRecoveryPluginLegacy.lrConfirm(0);

    (voters, requiredConfirmations, proposalsWithStatuses) = legacyRecoveryPluginLegacy.lrGetProposalListWithStatuses();
    assertEq(proposalsWithStatuses.length, 1);
    assertEq(proposalsWithStatuses[0].confirmedBy.length, 2);
    assertEq(proposalsWithStatuses[0].confirmedBy[0], true);
    assertEq(proposalsWithStatuses[0].confirmedBy[1], true);
    assertEq(proposalsWithStatuses[0].proposal.executed, true);

    assertEq(mockToken1.balanceOf(address(cryptoLegacy)), 100 ether);

    ICryptoLegacy.TokenTransferTo[] memory transfers = new ICryptoLegacy.TokenTransferTo[](2);
    transfers[0] = ICryptoLegacy.TokenTransferTo(address(mockToken1), dan, 40 ether);
    transfers[1] = ICryptoLegacy.TokenTransferTo(address(mockToken1), bobBeneficiary1, 60 ether);
    vm.prank(dan);
    legacyRecoveryPluginLegacy.lrPropose(LegacyRecoveryPlugin.lrWithdrawTokensFromLegacy.selector, abi.encode(transfers));

    (voters, requiredConfirmations, proposalsWithStatuses) = legacyRecoveryPluginLegacy.lrGetProposalListWithStatuses();
    assertEq(proposalsWithStatuses.length, 2);
    assertEq(proposalsWithStatuses[1].confirmedBy.length, 2);
    assertEq(proposalsWithStatuses[1].confirmedBy[0], false);
    assertEq(proposalsWithStatuses[1].confirmedBy[1], true);
    assertEq(proposalsWithStatuses[1].proposal.executed, false);

    assertEq(proposalsWithStatuses[0].proposal.selector, LegacyRecoveryPlugin.lrTransferTreasuryTokensToLegacy.selector);
    assertEq(proposalsWithStatuses[0].proposal.params, abi.encode(_treasuries, _tokens));

    assertEq(proposalsWithStatuses[1].proposal.selector, LegacyRecoveryPlugin.lrWithdrawTokensFromLegacy.selector);
    assertEq(proposalsWithStatuses[1].proposal.params, abi.encode(transfers));

    vm.prank(bobBeneficiary1);
    legacyRecoveryPluginLegacy.lrConfirm(1);

    (voters, requiredConfirmations, proposalsWithStatuses) = legacyRecoveryPluginLegacy.lrGetProposalListWithStatuses();
    assertEq(proposalsWithStatuses.length, 2);
    assertEq(proposalsWithStatuses[1].confirmedBy.length, 2);
    assertEq(proposalsWithStatuses[1].confirmedBy[0], true);
    assertEq(proposalsWithStatuses[1].confirmedBy[1], true);
    assertEq(proposalsWithStatuses[1].proposal.executed, true);

    assertEq(mockToken1.balanceOf(address(cryptoLegacy)), 0);
    assertEq(mockToken1.balanceOf(dan), 40 ether);
    assertEq(mockToken1.balanceOf(bobBeneficiary1), 60 ether);

    voters = new bytes32[](2);
    voters[0] = addressToHash(alice);
    voters[1] = addressToHash(dan);

    vm.prank(bob);
    legacyRecoveryPluginLegacy.lrSetMultisigConfig(voters, 2);

    clList = beneficiaryRegistry.getCryptoLegacyListByRecovery(addressToHash(alice));
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    clList = beneficiaryRegistry.getCryptoLegacyListByRecovery(addressToHash(dan));
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    clList = beneficiaryRegistry.getCryptoLegacyListByRecovery(addressToHash(bobBeneficiary1));
    assertEq(clList.length, 0);
  }

  function testBuyAndLockNftOnUpdate() public {
    bytes8 customRefCode = 0x0123456789abcdef;
    vm.prank(alice);
    buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());

    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, customRefCode);

    assertEq(buildManager.isLifetimeNftLocked(bob), false);
    vm.prank(bob);
    cryptoLegacy.update{value: lifetimeFee - refDiscountPct * lifetimeFee / 10000}(_getEmptyUintList(), _getEmptyUintList());
    assertEq(buildManager.isLifetimeNftLocked(bob), true);
    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.lastUpdateAt, block.timestamp);

    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bob);
    cryptoLegacy.update(_getEmptyUintList(), _getEmptyUintList());
    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.lastUpdateAt, block.timestamp);
  }

  function testCreate2Build() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    bytes32[] memory beneficiaryArr = new bytes32[](1);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);

    ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(bytes8(0), beneficiaryArr, beneficiaryConfigArr, _getBasePlugins(), 180 days, 90 days);
    uint256 initialFeeToPay = 0;
    uint256 updateFee = feeRegistry.getContractCaseFeeForCode(address(buildManager), buildManager.REGISTRY_UPDATE_CASE(), bytes8(0));
    address cl1Address = factory.computeAddress(bytes32(uint(1)), keccak256(factory.cryptoLegacyBytecode(address(buildManager), bob, _getBasePlugins())));
    buildRoll();
    vm.prank(bob);
    address payable cl1 = buildManager.buildCryptoLegacy{value: buildFee}(buildArgs, _getRefArgsStruct(bob), _getCreate2ArgsStruct(cl1Address, bytes32(uint(1))));

    vm.expectRevert(LibCreate2Deploy.AlreadyExists.selector);
    vm.prank(bob);
    buildManager.buildCryptoLegacy{value: buildFee}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(cl1Address, bytes32(uint(1))));

    vm.expectRevert(LibCreate2Deploy.AddressMismatch.selector);
    buildManager.buildCryptoLegacy{value: buildFee}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(cl1Address, bytes32(uint(1))));

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = ICryptoLegacyLens(cl1).getCryptoLegacyBaseData();

    ICryptoLegacyLens.CryptoLegacyListData memory clListData = ICryptoLegacyLens(cl1).getCryptoLegacyListData(_getEmptyAddressList());

    assertEq(beneficiaryArr.length, clListData.beneficiaries.length);
    assertEq(beneficiaryArr[0], clListData.beneficiaries[0]);
    assertEq(beneficiaryArr[0], addressToHash(bobBeneficiary1));

    vm.expectRevert("Ownable: caller is not the owner");
    factory.setBuildOperator(address(buildManager), false);

    vm.prank(owner);
    factory.setBuildOperator(address(buildManager), false);

    (initialFeeToPay, updateFee) = buildManager.getAndPayBuildFee(buildArgs.invitedByRefCode);
    address cl2Address = factory.computeAddress(bytes32(uint(2)), keccak256(factory.cryptoLegacyBytecode(address(buildManager), bob, _getBasePlugins())));
    buildRoll();
    vm.prank(bob);
    vm.expectRevert(ICryptoLegacyFactory.NotBuildOperator.selector);
    buildManager.buildCryptoLegacy(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(cl2Address, bytes32(uint(2))));

    vm.prank(owner);
    factory.setBuildOperator(address(buildManager), true);
    vm.prank(bob);
    address payable cl2 = buildManager.buildCryptoLegacy(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(cl2Address, bytes32(uint(2))));

    CryptoLegacyBasePlugin cryptoLegacy2 = CryptoLegacyBasePlugin(cl2);
    ICryptoLegacyLens cryptoLegacyLens2 = ICryptoLegacyLens(cl2);

    vm.prank(bob);
    clData = cryptoLegacyLens2.getCryptoLegacyBaseData();
    assertEq(clData.lastFeePaidAt, 0);

    vm.prank(bob);
    vm.expectRevert(ICryptoLegacy.InitialFeeNotPaid.selector);
    cryptoLegacy2.setPause(false);

    vm.prank(bob);
    vm.expectRevert(ICryptoLegacy.InitialFeeNotPaid.selector);
    cryptoLegacy2.transferOwnership(alice);

    cryptoLegacy2.payInitialFee{value: buildFee}(_getEmptyUintList(), _getEmptyUintList());
    clData = cryptoLegacyLens2.getCryptoLegacyBaseData();
    assertEq(clData.lastFeePaidAt, block.timestamp);
  }

  function testLegacyMessenger() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, bytes32[] memory beneficiaryArr, ) = _buildCryptoLegacy(bob, buildFee, 0x0);

    vm.startPrank(owner);
    LegacyMessenger lm = new LegacyMessenger(owner);
    lm.setBuildManager(address(buildManager), true);
    vm.stopPrank();

    vm.prank(bob);
    bytes32[] memory messagesHashArr = new bytes32[](2);
    messagesHashArr[0] = keccak256(abi.encode(bytes("1")));
    messagesHashArr[1] = keccak256(abi.encode(bytes("2")));
    bytes[] memory messagesArr = new bytes[](2);
    messagesArr[0] = bytes("1");
    messagesArr[1] = bytes("2");
    bytes[] memory messageChecksArr = new bytes[](2);
    messageChecksArr[0] = bytes("1t");
    messageChecksArr[1] = bytes("2t");
    vm.expectEmit(true, true, true, true);
    emit ILegacyMessenger.LegacyMessage(beneficiaryArr[0], messagesHashArr[0], messagesArr[0], 1);
    vm.roll(100);
    lm.sendMessagesTo(address(cryptoLegacy), beneficiaryArr, messagesHashArr, messagesArr, messageChecksArr, 1);

    uint64[] memory blockNumbers = lm.getMessagesBlockNumbersByRecipient(beneficiaryArr[0]);
    assertEq(blockNumbers.length, 1);
    assertEq(blockNumbers[0], block.number);

    address[] memory buildManagers = lm.getBuildManagerAdded();
    assertEq(buildManagers.length, 1);
    assertEq(buildManagers[0], address(buildManager));
    vm.prank(owner);
    lm.setBuildManager(address(buildManager), false);
    buildManagers = lm.getBuildManagerAdded();
    assertEq(buildManagers.length, 0);

    vm.prank(bob);
    vm.expectRevert(IBuildManagerOwnable.BuildManagerNotAdded.selector);
    lm.sendMessagesTo(address(cryptoLegacy), beneficiaryArr, messagesHashArr, messagesArr, messageChecksArr, 1);

    blockNumbers = lm.getMessagesBlockNumbersByRecipient(beneficiaryArr[1]);
    assertEq(blockNumbers.length, 1);
    assertEq(blockNumbers[0], block.number);

    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacy.sendMessagesToBeneficiary(beneficiaryArr, messagesHashArr, messagesArr, messageChecksArr, 1);

    vm.expectEmit(true, true, true, true);
    emit CryptoLegacyBasePlugin.BeneficiaryMessage(beneficiaryArr[0], messagesHashArr[0], messagesArr[0], 1);

    vm.prank(alice);
    vm.expectRevert(IBuildManagerOwnable.NotTheOwnerOfCryptoLegacy.selector);
    lm.sendMessagesTo(address(cryptoLegacy), beneficiaryArr, messagesHashArr, messagesArr, messageChecksArr, 1);

    CryptoLegacy mockCryptoLegacy = new CryptoLegacy(address(buildManager), bob, _getOneAddressList(address(cryptoLegacyBasePlugin)));

    vm.prank(bob);
    vm.expectRevert(IBuildManagerOwnable.CryptoLegacyNotRegistered.selector);
    lm.sendMessagesTo(address(mockCryptoLegacy), beneficiaryArr, messagesHashArr, messagesArr, messageChecksArr, 1);

    vm.roll(200);
    vm.prank(bob);
    cryptoLegacy.sendMessagesToBeneficiary(beneficiaryArr, messagesHashArr, messagesArr, messageChecksArr, 1);

    blockNumbers = cryptoLegacyLens.getMessagesBlockNumbersByRecipient(beneficiaryArr[0]);
    assertEq(blockNumbers.length, 1);
    assertEq(blockNumbers[0], block.number);

    blockNumbers = cryptoLegacyLens.getMessagesBlockNumbersByRecipient(beneficiaryArr[1]);
    assertEq(blockNumbers.length, 1);
    assertEq(blockNumbers[0], block.number);
  }

  function testReentrancyAttack() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);

    // Deploy a malicious ERC20 token that re-enters the contract during transfer
    MockMaliciousERC20 maliciousToken = new MockMaliciousERC20(address(cryptoLegacy));
    maliciousToken.transfer(treasury, 1000 ether);

    vm.startPrank(treasury);
    maliciousToken.approve(address(cryptoLegacy), 1000 ether);
    vm.stopPrank();

    vm.startPrank(bobBeneficiary1);
    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval + 1);
    cryptoLegacy.initiateChallenge();
    vm.warp(block.timestamp + clData.challengeTimeout + 1);

    address[] memory _treasuries = new address[](1);
    _treasuries[0] = treasury;
    address[] memory _tokens = new address[](1);
    _tokens[0] = address(maliciousToken);

    // Attempt to trigger reentrancy during token transfer
    vm.expectRevert("ReentrancyGuard: reentrant call");
    cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _tokens);
  }

  function testOnlyOwnerFunctions() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);

    vm.prank(alice); // Not the owner
    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    bytes32[] memory beneficiaryArr = new bytes32[](1);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(0, 0, 10000);
    cryptoLegacy.setBeneficiaries(beneficiaryArr, beneficiaryConfigArr);

    vm.prank(alice); // Not the owner
    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacy.setPause(true);

    assertEq(cryptoLegacy.isPaused(), false);
    vm.prank(bob);
    cryptoLegacy.setPause(true);
    assertEq(cryptoLegacy.isPaused(), true);

    vm.warp(block.timestamp + cryptoLegacyLens.getCryptoLegacyBaseData().updateInterval + 1);

    vm.prank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.Pause.selector);
    cryptoLegacy.initiateChallenge();

    vm.prank(alice); // Not the owner
    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacy.update(_getEmptyUintList(), _getEmptyUintList());

    address[] memory clList = beneficiaryRegistry.getCryptoLegacyListByOwner(addressToHash(bob));
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));

    vm.prank(bob);
    cryptoLegacy.transferOwnership(alice);

    clList = beneficiaryRegistry.getCryptoLegacyListByOwner(addressToHash(bob));
    assertEq(clList.length, 0);

    clList = beneficiaryRegistry.getCryptoLegacyListByOwner(addressToHash(alice));
    assertEq(clList.length, 1);
    assertEq(clList[0], address(cryptoLegacy));
  }

  function testClaimAsRemovedBeneficiary() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();

    address[] memory cryptoLegacyGot = beneficiaryRegistry.getCryptoLegacyListByBeneficiary(addressToHash(bobBeneficiary1));
    assertEq(cryptoLegacyGot.length, 1);
    assertEq(cryptoLegacyGot[0], address(cryptoLegacy));

    // Simulate a front-run attack by changing the beneficiary before the challenge timeout
    vm.prank(bob);
    bytes32[] memory beneficiaryArr = new bytes32[](2);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    beneficiaryArr[1] = keccak256(abi.encode(bobBeneficiary2));
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](2);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(0, 0, 0);
    beneficiaryConfigArr[1] = ICryptoLegacy.BeneficiaryConfig(0, 0, 10000);
    cryptoLegacy.setBeneficiaries(beneficiaryArr, beneficiaryConfigArr);

    cryptoLegacyGot = beneficiaryRegistry.getCryptoLegacyListByBeneficiary(addressToHash(bobBeneficiary1));
    assertEq(cryptoLegacyGot.length, 0);

    vm.warp(block.timestamp + clData.challengeTimeout + 1);

    // Ensure the original beneficiary cannot claim
    vm.prank(bobBeneficiary1);
    vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
    cryptoLegacy.beneficiaryClaim(new address[](0), address(0), 0);

    uint256 danBalanceBefore = dan.balance;
    vm.prank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim{value: updateFee}(new address[](0), dan, 1000);

    assertEq(dan.balance - danBalanceBefore, updateFee / 10);
  }

  function testDoubleChallengeReset() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    // The beneficiary tries to challenge after update interval
    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();

    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    uint64 firstDistStart = clData.distributionStartAt;
    assertTrue(firstDistStart > 0);

    // Try to call again
    vm.warp(block.timestamp + 10);
    vm.prank(bobBeneficiary2);
    // The code does not forcibly revert on second attempt,
    // but we want to ensure distributionStartAt isn't changed again
    vm.expectRevert(ICryptoLegacy.DistributionStartAlreadySet.selector);
    cryptoLegacy.initiateChallenge();
    clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    // distributionStartAt should remain the same -> no reset
    assertEq(firstDistStart, clData.distributionStartAt, "Should not reset distribution start");
  }

  function testUpdateAfterDistributionStart() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    // Move forward in time to allow challenge
    vm.warp(block.timestamp + clData.updateInterval + 1);

    // The beneficiary triggers distribution
    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();

    // Advance time so distribution is started
    vm.warp(block.timestamp + clData.challengeTimeout + 1);

    // Now owner tries to do an update, expecting revert
    vm.prank(bob);
    vm.expectRevert(ICryptoLegacy.DistributionStarted.selector); // or ICryptoLegacy.NotTheOwner.selector due to _checkOwner
    cryptoLegacy.update{value: 1 ether}(_getEmptyUintList(), _getEmptyUintList());
  }

  function testUpdateByUpdater() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");
    address updateByUpdaterPlugin = address(new UpdateRolePlugin());
    MockTestPlugin mockTestPlugin = new MockTestPlugin();
    MockTest2Plugin mockTest2Plugin = new MockTest2Plugin();
    vm.startPrank(owner);
    pluginsRegistry.addPlugin(updateByUpdaterPlugin, "");
    pluginsRegistry.addPlugin(address(mockTestPlugin), "");
    pluginsRegistry.addPlugin(address(mockTest2Plugin), "");
    vm.stopPrank();

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);
    UpdateRolePlugin updateByUpdaterLegacy = UpdateRolePlugin(address(cryptoLegacy));

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    address[] memory _plugins = new address[](1);
    _plugins[0] = address(mockTestPlugin);
    vm.expectRevert(ICryptoLegacy.FacetNotFound.selector);
    vm.prank(bob);
    CryptoLegacy(payable(address(cryptoLegacy))).removePluginList(_plugins);

    vm.expectRevert(ICryptoLegacy.CantAddFunctionThatAlreadyExists.selector);
    vm.prank(bob);
    CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(_getTwoAddressList(address(mockTestPlugin), address(mockTest2Plugin)));

    vm.prank(bob);
    _plugins = new address[](1);
    _plugins[0] = cryptoLegacyBasePlugin;
    CryptoLegacy(payable(address(cryptoLegacy))).removePluginList(_plugins);

    vm.expectRevert();
    cryptoLegacy.owner();

    vm.prank(bob);
    CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(_getOneAddressList(cryptoLegacyBasePlugin));
    assertEq(cryptoLegacy.owner(), bob);

    // Move forward in time to allow challenge
    vm.warp(block.timestamp + clData.updateInterval + 1);
    vm.prank(bob);
    CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(_getOneAddressList(updateByUpdaterPlugin));

    vm.startPrank(dan);
    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());
//    vm.expectRevert("NOT_THE_GUARANTOR");
//    updateByGuarantorLegacy.updateByGuarantor{value: updateFee}();
    vm.stopPrank();

    address[] memory _updaters = new address[](1);
    _updaters[0] = dan;

    assertEq(updateByUpdaterLegacy.isUpdater(dan), false);
    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    updateByUpdaterLegacy.setUpdater(dan, true);
    vm.prank(bob);
    updateByUpdaterLegacy.setUpdater(dan, true);
    assertEq(updateByUpdaterLegacy.isUpdater(dan), true);
    assertEq(updateByUpdaterLegacy.getUpdaterList(), _updaters);

    vm.prank(bob);
    updateByUpdaterLegacy.setUpdater(dan, false);
    assertEq(updateByUpdaterLegacy.getUpdaterList(), new address[](0));

    vm.prank(bob);
    updateByUpdaterLegacy.setUpdater(dan, true);
    assertEq(updateByUpdaterLegacy.isUpdater(dan), true);
    assertEq(updateByUpdaterLegacy.getUpdaterList(), _updaters);

    // The beneficiary triggers distribution

    vm.expectRevert(ICryptoLegacyUpdaterPlugin.NotTheUpdater.selector);
    updateByUpdaterLegacy.updateByUpdater{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    uint256 updateAt = block.timestamp;
    vm.startPrank(dan);
    vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());
    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertNotEq(clData.lastUpdateAt, updateAt);
    updateByUpdaterLegacy.updateByUpdater{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());
    vm.stopPrank();
    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.lastUpdateAt, updateAt);
  }

  function testPartialInitialFeePayments() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, 0, 0x0);

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.initialFeeToPay, buildFee);

    // Attempt partial
    vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.IncorrectFee.selector, buildFee));
    cryptoLegacy.payInitialFee{value: buildFee / 2}(_getEmptyUintList(), _getEmptyUintList());

    cryptoLegacy.payInitialFee{value: buildFee}(_getEmptyUintList(), _getEmptyUintList());
    // Now initialFeeToPay should be 0
    clData = cryptoLegacyLens.getCryptoLegacyBaseData();
    assertEq(clData.initialFeeToPay, 0);
    // Trying to pay again should revert with "INITIAL_FEE_ALREADY_PAID"
    vm.expectRevert(ICryptoLegacy.InitialFeeAlreadyPaid.selector);
    cryptoLegacy.payInitialFee{value: buildFee}(_getEmptyUintList(), _getEmptyUintList());
  }
}
