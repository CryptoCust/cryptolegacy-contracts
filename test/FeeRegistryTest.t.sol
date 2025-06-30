// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AbstractTestHelper.sol";
import "./CrossChainTestHelper.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockERC721.sol";
import "../contracts/mocks/MockPayable.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/mocks/MockClaimPlugin.sol";
import "../contracts/plugins/NftLegacyPlugin.sol";
import "../contracts/interfaces/ICryptoLegacy.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/mocks/MockMaliciousERC20.sol";
import "../contracts/plugins/UpdateRolePlugin.sol";
import "../contracts/mocks/MockMaliciousERC721.sol";
import "../contracts/libraries/LibCryptoLegacy.sol";
import "../contracts/plugins/LegacyRecoveryPlugin.sol";
import "../contracts/interfaces/ICryptoLegacyLens.sol";
import "../contracts/plugins/TrustedGuardiansPlugin.sol";
import "../contracts/interfaces/ITrustedGuardiansPlugin.sol";
import "../contracts/plugins/BeneficiaryPluginAddRights.sol";

contract FeeRegistryTest is CrossChainTestHelper {

  function setUp() public override {
    super.setUp();
  }

  function testFeeRegistryBuilder() public {
    bytes32 feeRegistrySalt = keccak256(abi.encodePacked("FeeRegistry2", salt));
    address implementation = address(new FeeRegistry{salt: salt}());
    bytes memory initData = LibDeploy.feeRegistryInitialize(owner, uint32(refDiscountPct), uint32(refSharePct), lifetimeNft, 60, 10);

    vm.expectRevert("Ownable: caller is not the owner");
    proxyBuilder.build(address(1), feeRegistrySalt, implementation, initData);

    vm.expectRevert(ProxyBuilder.AddressMismatch.selector);
    vm.prank(owner);
    proxyBuilder.build(address(1), feeRegistrySalt, implementation, initData);
  }

  function testFeeRegistryTooBigPct() public {
    (bytes8 refCode, , ) = buildManager.createRef(aliceRecipient, _getEmptyUintList(), _getEmptyUintList());
    vm.prank(owner);
    feeRegistry.setDefaultPct(10001, 1000);
  
    vm.expectRevert(IFeeRegistry.TooBigPct.selector);
    feeRegistry.calculateFee(refCode, 1 ether);

    vm.prank(owner);
    feeRegistry.setDefaultPct(1000, 10001);
  
    vm.expectRevert(IFeeRegistry.TooBigPct.selector);
    feeRegistry.calculateFee(refCode, 1 ether);

    vm.prank(owner);
    feeRegistry.setDefaultPct(1000, 1000);

    (uint256 discount, uint256 share, uint256 fee) = feeRegistry.calculateFee(refCode, 1 ether);
    assertEq(discount, 0.1 ether);
    assertEq(share, 0.1 ether);
    assertEq(fee, 0.9 ether);
  }

  function testFeeRegistry() public {
    assertEq(feeRegistry.lifetimeNft(), address(lifetimeNft));

    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = SIDE_CHAIN_ID_1;
    chainIds[1] = SIDE_CHAIN_ID_2;

    vm.expectRevert("Ownable: caller is not the owner");
    feeRegistry.setSupportedRefCodeInChains(chainIds, true);

    vm.prank(owner);
    feeRegistry.setSupportedRefCodeInChains(chainIds, true);

    uint256[] memory gotChainIds = feeRegistry.getSupportedRefInChainsList();
    assertEq(gotChainIds, chainIds);

    vm.prank(owner);
    feeRegistry.setSupportedRefCodeInChains(chainIds, false);

    gotChainIds = feeRegistry.getSupportedRefInChainsList();
    assertEq(gotChainIds.length, 0);

    chainIds = new uint256[](1);
    chainIds[0] = SIDE_CHAIN_ID_1;

    vm.prank(owner);
    feeRegistry.setSupportedRefCodeInChains(chainIds, true);

    gotChainIds = feeRegistry.getSupportedRefInChainsList();
    assertEq(gotChainIds, chainIds);

    address[] memory codeOperators = feeRegistry.getCodeOperatorsList();
    assertEq(codeOperators.length, 1);
    assertEq(codeOperators[0], address(buildManager));

    assertEq(feeRegistry.isCodeOperator(address(buildManager)), true);
  }

  function testFeeRegistryBeneficiaries() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    assertEq(feeRegistry.getContractCaseFee(address(buildManager), buildManager.REGISTRY_BUILD_CASE()), buildFee);

    bytes32[] memory beneficiaryArr = new bytes32[](1);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);

    IFeeRegistry.FeeBeneficiary[] memory custBeneficiaryConfigArr = new IFeeRegistry.FeeBeneficiary[](2);
    custBeneficiaryConfigArr[0] = IFeeRegistry.FeeBeneficiary(custFeeRecipient1, 4000);
    custBeneficiaryConfigArr[1] = IFeeRegistry.FeeBeneficiary(custFeeRecipient2, 6000);

    vm.expectRevert("Ownable: caller is not the owner");
    feeRegistry.setFeeBeneficiaries(custBeneficiaryConfigArr);
    vm.prank(owner);
    feeRegistry.setFeeBeneficiaries(custBeneficiaryConfigArr);

    IFeeRegistry.FeeBeneficiary[] memory gotFeeBeneficiaries = feeRegistry.getFeeBeneficiaries();
    assertEq(gotFeeBeneficiaries[0].recipient, custFeeRecipient1);
    assertEq(gotFeeBeneficiaries[0].sharePct, 4000);
    assertEq(gotFeeBeneficiaries[1].recipient, custFeeRecipient2);
    assertEq(gotFeeBeneficiaries[1].sharePct, 6000);

    custBeneficiaryConfigArr[1] = IFeeRegistry.FeeBeneficiary(custFeeRecipient2, 5000);

    vm.expectRevert(IFeeRegistry.PctSumDoesntMatchBase.selector);
    vm.prank(owner);
    feeRegistry.setFeeBeneficiaries(custBeneficiaryConfigArr);

    assertEq(custFeeRecipient1.balance, 0);
    assertEq(custFeeRecipient2.balance, 0);
    address[] memory plugins = _getBasePlugins();
    buildRoll();
    vm.prank(bob);
    assertEq(address(feeRegistry).balance, 0);
    assertEq(feeRegistry.accumulatedFee(), 0);
    ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(bytes8(0), beneficiaryArr, beneficiaryConfigArr, plugins, updateInterval, challengeTimeout);
    address payable cl = buildManager.buildCryptoLegacy{value: buildFee}(buildArgs, _getRefArgsStruct(bob), _getCreate2ArgsStruct(address(0), bytes32(uint(0))));

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    vm.prank(address(buildManager));
    CryptoLegacyBasePlugin(cl).initializeByBuildManager(0, 0, buildArgs.beneficiaryHashes, buildArgs.beneficiaryConfig, bytes8(0), uint64(0), uint64(0));

    assertEq(address(feeRegistry).balance, buildFee);
    assertEq(feeRegistry.accumulatedFee(), buildFee);
    feeRegistry.withdrawAccumulatedFee();
    assertEq(feeRegistry.accumulatedFee(), 0);
    assertEq(address(feeRegistry).balance, 0);

    assertEq(custFeeRecipient1.balance, 0.08 ether);
    assertEq(custFeeRecipient2.balance, 0.12 ether);

    buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), alice, _getEmptyUintList(), _getEmptyUintList());

    assertEq(address(feeRegistry).balance, lifetimeFee);
    assertEq(feeRegistry.accumulatedFee(), lifetimeFee);
    feeRegistry.withdrawAccumulatedFee();
    assertEq(feeRegistry.accumulatedFee(), 0);
    assertEq(address(feeRegistry).balance, 0);

    assertEq(custFeeRecipient1.balance, 0.88 ether);
    assertEq(custFeeRecipient2.balance, 1.32 ether);
  }

  function testChangeCodeReferrer() public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, false);
    emit IPluginsRegistry.AddPlugin(lensPlugin, "123");
    pluginsRegistry.addPlugin(lensPlugin, "123");

    bytes8 customRefCodeAlice = 0x0123456789abcdef;
    bytes8 customRefCodeBob = 0x0123456789abcdee;
    vm.prank(alice);
    buildManager.createCustomRef(customRefCodeAlice, aliceRecipient, _getRefChains(), _getRefChains());

    vm.prank(alice);
    vm.expectRevert(IFeeRegistry.RefAlreadyCreated.selector);
    buildManager.createCustomRef(customRefCodeAlice, aliceRecipient, _getRefChains(), _getRefChains());

    vm.prank(alice);
    vm.expectRevert(IFeeRegistry.AlreadyReferrer.selector);
    buildManager.createCustomRef(customRefCodeBob, aliceRecipient, _getRefChains(), _getRefChains());

    vm.prank(bob);
    buildManager.createCustomRef(customRefCodeBob, bobBeneficiary1, _getRefChains(), _getRefChains());

    vm.expectRevert(IFeeRegistry.NotReferrer.selector);
    feeRegistry.changeCodeReferrer(bytes8(0), dan, dan, _getEmptyUintList(), _getEmptyUintList());

    vm.expectRevert(IFeeRegistry.NotReferrer.selector);
    feeRegistry.changeCodeReferrer(customRefCodeAlice, dan, dan, _getEmptyUintList(), _getEmptyUintList());

    vm.prank(alice);
    vm.expectRevert(IFeeRegistry.AlreadyReferrer.selector);
    feeRegistry.changeCodeReferrer(customRefCodeAlice, bob, bob, _getEmptyUintList(), _getEmptyUintList());

    vm.prank(alice);
    vm.expectRevert(IFeeRegistry.AlreadyReferrer.selector);
    feeRegistry.changeCodeReferrer(customRefCodeAlice, alice, alice, _getEmptyUintList(), _getEmptyUintList());

    vm.prank(alice);
    feeRegistry.changeCodeReferrer(customRefCodeAlice, dan, dan, _getEmptyUintList(), _getEmptyUintList());

    vm.prank(dan);
    feeRegistry.changeRecipientReferrer(customRefCodeAlice, danRecipient, _getEmptyUintList(), _getEmptyUintList());

    bytes32[] memory beneficiaryArr = new bytes32[](1);
    beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
    beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);
    address[] memory plugins = _getBasePlugins();

    buildRoll();

    uint256 discount = buildFee * refDiscountPct / 10000;
    uint256 share = buildFee * refSharePct / 10000;
    assertEq(aliceRecipient.balance, 0);
    assertEq(danRecipient.balance, 0);
    ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(customRefCodeAlice, beneficiaryArr, beneficiaryConfigArr, plugins, updateInterval, challengeTimeout);
    buildManager.buildCryptoLegacy{value: buildFee - discount}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), bytes32(uint(0))));
    assertEq(aliceRecipient.balance, 0);
    assertEq(danRecipient.balance, share);

    vm.prank(owner);
    vm.expectEmit(true, true, true, false);
    emit IPluginsRegistry.RemovePlugin(lensPlugin);
    pluginsRegistry.removePlugin(lensPlugin);

    buildRoll();

    vm.expectRevert(LibCreate3.ErrorCreatingContract.selector);
    buildManager.buildCryptoLegacy{value: buildFee - discount}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), bytes32(uint(0))));
  }

  function testReturnValue() public {
    MockPayable mockPayable = new MockPayable(true);

    (bool success, ) = payable(mockPayable).call{value: 2 ether}(new bytes(0));
    if (!success) {
      revert("Not paid");
    }

    assertEq(mockPayable.received(), 2 ether);

    bytes8 customRefCode = 0x0123456789abcdef;
    vm.prank(address(mockPayable));
    buildManager.createCustomRef{value: 1.1 ether}(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());

    assertEq(mockPayable.received(), 3.1 ether);

    uint256[] memory chainIdsToLock = new uint256[](2);
    chainIdsToLock[0] = SIDE_CHAIN_ID_1;
    chainIdsToLock[1] = SIDE_CHAIN_ID_2;

    vm.prank(address(mockPayable));
    feeRegistry.changeCodeReferrer{value: 0.02 ether}(customRefCode, alice, aliceRecipient, chainIdsToLock, _getTwoUintList(0, 0));

    assertEq(mockPayable.received(), 3.1 ether);

    vm.prank(address(mockPayable));
    (bytes8 refCode, , ) = buildManager.createRef{value: 1.2 ether}(aliceRecipient, chainIdsToLock, _getTwoUintList(0, 0));

    assertEq(mockPayable.received(), 4.28 ether);

    vm.prank(address(mockPayable));
    feeRegistry.changeCodeReferrer(refCode, bob, aliceRecipient, _getRefChains(), _getRefChains());

    mockPayable.setPayableActive(false);
    vm.prank(address(mockPayable));
    vm.expectRevert(abi.encodeWithSelector(ILockChainGate.TransferFeeFailed.selector, new bytes(0)));
    buildManager.createRef{value: 1.2 ether}(aliceRecipient, chainIdsToLock, _getTwoUintList(0, 0));
  }

  function testCrossChainRefs() public {
    uint256[] memory chainIdsToLock = new uint256[](2);
    chainIdsToLock[0] = SIDE_CHAIN_ID_1;
    chainIdsToLock[1] = SIDE_CHAIN_ID_2;

    uint256[] memory crossChainFees = new uint256[](2);
    crossChainFees[0] = deBridgeFee + 1;
    crossChainFees[1] = deBridgeFee + 2;

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee * 2 + 3));
    buildManager.createRef(bob, chainIdsToLock, crossChainFees);

    vm.expectRevert("Ownable: caller is not the owner");
    feeRegistry.setCodeOperator(address(buildManager), false);

    vm.expectRevert("Ownable: caller is not the owner");
    feeRegistry.setSourceChainContract(1, address(2));

    vm.prank(owner);
    feeRegistry.setSourceChainContract(1, address(2));
    (, , address sourceChain) = feeRegistry.deBridgeChainConfig(1);
    assertEq(sourceChain, address(2));

    vm.prank(owner);
    feeRegistry.setCodeOperator(address(buildManager), false);

    vm.prank(alice);
    vm.expectRevert(IFeeRegistry.NotOperator.selector);
    buildManager.createRef{value: deBridgeFee * 2 + 3}(bob, chainIdsToLock, crossChainFees);

    vm.prank(owner);
    feeRegistry.setCodeOperator(address(buildManager), true);

    vm.prank(alice);
    vm.expectEmit(true, true, true, false);
    emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_1, deBridgeFee);
    (bytes8 refCode, ,) = buildManager.createRef{value: deBridgeFee * 2 + 3}(bob, chainIdsToLock, crossChainFees);

    IFeeRegistry.Referrer memory ref = mainLock.refererByCode(refCode);
    assertEq(ref.owner, alice);
    assertEq(ref.recipient, bob);

    assertEq(mainLock.codeByReferrer(alice), refCode);

    mockCallProxy.setSourceChainIdAndContract(mainLock);
    mockDeBridgeGate.executeLastMessage();
    _checkDeBridgeCallData(abi.encodeWithSelector(sideLock2.crossCreateCustomCode.selector, MAIN_CHAIN_ID, alice, bob, refCode, uint32(0), uint32(0)));

    vm.prank(address(mockCallProxy));
    sideLock1.crossCreateCustomCode(MAIN_CHAIN_ID, alice, bob, refCode, uint32(0), uint32(0));

    ref = sideLock1.refererByCode(refCode);
    assertEq(ref.owner, alice);
    assertEq(ref.recipient, bob);

    assertEq(sideLock1.codeByReferrer(alice), refCode);

    ref = sideLock2.refererByCode(refCode);
    assertEq(ref.owner, alice);
    assertEq(ref.recipient, bob);

    assertEq(sideLock2.codeByReferrer(alice), refCode);

    vm.prank(alice);
    feeRegistry.changeRecipientReferrer(refCode, dan, _getEmptyUintList(), _getEmptyUintList());

    uint32 specificDiscountPct = uint32(refDiscountPct + 1);
    uint32 specificSharePct = uint32(refSharePct + 1);
    vm.prank(owner);
    feeRegistry.setRefererSpecificPct(alice, specificDiscountPct, specificSharePct);

    vm.expectRevert(IFeeRegistry.TooBigPct.selector);
    vm.prank(owner);
    feeRegistry.setRefererSpecificPct(alice, 10001, specificSharePct);

    (uint32 discountPct, uint32 sharePct) = feeRegistry.getCodePct(refCode);
    assertEq(discountPct, uint32(refDiscountPct + 1));
    assertEq(sharePct, uint32(refSharePct + 1));

    chainIdsToLock[0] = SIDE_CHAIN_ID_3;
    chainIdsToLock[1] = SIDE_CHAIN_ID_2;

    crossChainFees[0] = 0;
    crossChainFees[1] = 0;

    vm.prank(alice);
    vm.expectRevert(ILockChainGate.ArrayLengthMismatch.selector);
    buildManager.updateCrossChainsRef{value: deBridgeFee * 2}(_getEmptyUintList(), crossChainFees);

    vm.prank(alice);
    buildManager.updateCrossChainsRef{value: deBridgeFee * 2}(chainIdsToLock, crossChainFees);

    mockCallProxy.setSourceChainIdAndContract(mainLock);
    mockDeBridgeGate.executeLastMessage();
    _checkDeBridgeCallData(abi.encodeWithSelector(sideLock2.crossUpdateCustomCode.selector, MAIN_CHAIN_ID, alice, dan, refCode, specificDiscountPct, specificSharePct));

    (discountPct, sharePct) = sideLock2.getCodePct(refCode);
    assertEq(discountPct, uint32(refDiscountPct + 1));
    assertEq(sharePct, uint32(refSharePct + 1));

    vm.prank(address(mockCallProxy));
    sideLock3.crossUpdateCustomCode(MAIN_CHAIN_ID, alice, dan, refCode, specificDiscountPct, specificSharePct);

    ref = sideLock1.refererByCode(refCode);
    assertEq(ref.owner, alice);
    assertEq(ref.recipient, bob);

    ref = sideLock2.refererByCode(refCode);
    assertEq(ref.owner, alice);
    assertEq(ref.recipient, dan);

    ref = sideLock3.refererByCode(refCode);
    assertEq(ref.owner, alice);
    assertEq(ref.recipient, dan);

    vm.prank(alice);
    feeRegistry.changeCodeReferrer(refCode, bob, bob, _getEmptyUintList(), _getEmptyUintList());

    (discountPct, sharePct) = sideLock2.getCodePct(refCode);
    assertEq(discountPct, uint32(refDiscountPct + 1));
    assertEq(sharePct, uint32(refSharePct + 1));

    chainIdsToLock = new uint256[](3);
    chainIdsToLock[0] = SIDE_CHAIN_ID_1;
    chainIdsToLock[1] = SIDE_CHAIN_ID_2;
    chainIdsToLock[2] = SIDE_CHAIN_ID_3;

    crossChainFees = new uint256[](3);
    crossChainFees[0] = deBridgeFee + 1;
    crossChainFees[1] = deBridgeFee + 2;
    crossChainFees[2] = deBridgeFee + 3;

    vm.prank(alice);
    vm.expectRevert(IFeeRegistry.CodeNotCreated.selector);
    buildManager.updateCrossChainsRef{value: deBridgeFee * 3 + 6}(chainIdsToLock, crossChainFees);

    vm.prank(bob);
    buildManager.updateCrossChainsRef{value: deBridgeFee * 3 + 6}(chainIdsToLock, crossChainFees);

    mockCallProxy.setSourceChainIdAndContract(mainLock);
    mockDeBridgeGate.executeLastMessage();
    assertEq(mockDeBridgeGate.targetContractAddress(), address(sideLock3));
    _checkDeBridgeCallData(abi.encodeWithSelector(sideLock3.crossUpdateCustomCode.selector, MAIN_CHAIN_ID, bob, bob, refCode, specificDiscountPct, specificSharePct));

    vm.prank(address(mockCallProxy));
    sideLock2.crossUpdateCustomCode(MAIN_CHAIN_ID, bob, bob, refCode, specificDiscountPct, specificSharePct);

    vm.prank(address(mockCallProxy));
    sideLock1.crossUpdateCustomCode(MAIN_CHAIN_ID, bob, bob, refCode, specificDiscountPct, specificSharePct);

    ref = sideLock1.refererByCode(refCode);
    assertEq(ref.owner, bob);
    assertEq(ref.recipient, bob);

    ref = sideLock2.refererByCode(refCode);
    assertEq(ref.owner, bob);
    assertEq(ref.recipient, bob);

    ref = sideLock3.refererByCode(refCode);
    assertEq(ref.owner, bob);
    assertEq(ref.recipient, bob);

    (discountPct, sharePct) = sideLock2.getCodePct(refCode);
    assertEq(discountPct, specificDiscountPct);
    assertEq(sharePct, specificSharePct);

    vm.prank(owner);
    feeRegistry.setRefererSpecificPct(bob, uint32(0), uint32(0));

    chainIdsToLock = new uint256[](2);
    chainIdsToLock[0] = SIDE_CHAIN_ID_1;
    chainIdsToLock[1] = SIDE_CHAIN_ID_2;

    crossChainFees = new uint256[](2);
    crossChainFees[0] = deBridgeFee + 1;
    crossChainFees[1] = deBridgeFee + 2;

    vm.prank(bob);
    feeRegistry.changeCodeReferrer{value: deBridgeFee * 2 + 3}(refCode, alice, alice, chainIdsToLock, crossChainFees);

    mockDeBridgeGate.executeLastMessage();
    vm.prank(address(mockCallProxy));
    sideLock1.crossUpdateCustomCode(MAIN_CHAIN_ID, alice, dan, refCode, uint32(0), uint32(0));

    (discountPct, sharePct) = sideLock2.getCodePct(refCode);
    assertEq(discountPct, refDiscountPct);
    assertEq(sharePct, refSharePct);

    assertEq(buildManager.calculateCrossChainCreateRefFee(chainIdsToLock, crossChainFees), deBridgeFee * 2 + 3);
    vm.prank(charlie);
    (bytes8 newRefCode, , ) = buildManager.createRef{value: deBridgeFee * 2 + 3}(charlie, chainIdsToLock, crossChainFees);

    ref = sideLock3.refererByCode(refCode);
    assertEq(ref.owner, bob);
    assertEq(ref.recipient, bob);

    chainIdsToLock = new uint256[](1);
    chainIdsToLock[0] = SIDE_CHAIN_ID_3;

    crossChainFees = new uint256[](1);
    crossChainFees[0] = deBridgeFee + 3;

    vm.prank(charlie);
    feeRegistry.changeCodeReferrer{value: deBridgeFee + 3}(newRefCode, bob, bob, chainIdsToLock, crossChainFees);

    mockDeBridgeGate.executeLastMessage();

    ref = sideLock3.refererByCode(refCode);
    assertEq(ref.owner, bob);
    assertEq(ref.recipient, bob);

    ref = sideLock3.refererByCode(newRefCode);
    assertEq(ref.owner, address(0));
    assertEq(ref.recipient, address(0));
  }

  function testBrokenFeeRegistry() public {
    vm.prank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "");

    (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacyWithPlugins(bob, buildFee, bytes8(0), _getOneInitPluginList(lensPlugin));
    vm.warp(block.timestamp + 1);

    vm.prank(bob);
    vm.expectEmit(true, false, false, false);
    emit ICryptoLegacy.FeePaidByDefault(bytes8(0), false, 0, 0, address(9), 0);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    vm.startPrank(owner);
    buildManager.setRegistries(IFeeRegistry(address(0)), buildManager.pluginsRegistry(), buildManager.beneficiaryRegistry());
    vm.stopPrank();

    vm.warp(block.timestamp + cryptoLegacyLens.getCryptoLegacyBaseData().updateInterval + 1);

    vm.prank(bob);
    emit ICryptoLegacy.FeePaidByTransfer(bytes8(0), false, 0, address(9), 0);
    cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

    assertEq(address(buildManager).balance, updateFee);
  }
}
