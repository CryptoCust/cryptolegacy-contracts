// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "../contracts/FeeRegistry.sol";
import "../contracts/mocks/MockCallProxy.sol";
import "../contracts/mocks/MockDeBridgeGate.sol";
import "./AbstractTestHelper.sol";
import "forge-std/Test.sol";
import "./CrossChainTestHelper.sol";

contract LockChainGateCrosschainTest is CrossChainTestHelper {

    function setUp() public override {
        super.setUp();
    }

    function testLockChainGateOwnerFunctions() public {
        vm.expectRevert("Ownable: caller is not the owner");
        feeRegistry.setLockPeriod(1 days);

        assertEq(feeRegistry.lockPeriod(), 60);
        vm.prank(owner);
        feeRegistry.setLockPeriod(1 days);
        assertEq(feeRegistry.lockPeriod(), 1 days);
    }

    function testDebridgeGateRefCode() public {
        assertEq(feeRegistry.referralCode(), 0);

        uint32 refCode = 22;
        vm.expectRevert("Ownable: caller is not the owner");
        feeRegistry.setReferralCode(refCode);

        vm.prank(owner);
        feeRegistry.setReferralCode(refCode);

        assertEq(feeRegistry.referralCode(), uint256(refCode));
    }

    function testPayOnlyRefFee() public {
        _addBasePluginsToRegistry();

        bytes8 customRefCode = 0x0123456789abcdef;
        vm.prank(alice);
        buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());

        uint256[] memory chainIdsToLock = new uint256[](2);
        chainIdsToLock[0] = SIDE_CHAIN_ID_1;
        chainIdsToLock[1] = SIDE_CHAIN_ID_2;

        uint256[] memory crossChainFees = new uint256[](2);
        crossChainFees[0] = deBridgeFee + 1;
        crossChainFees[1] = deBridgeFee + 2;

        ICryptoLegacyBuildManager.RefArgs memory refArgs = _getCustomRefArgsStructWithChains(dan, bytes4(0), chainIdsToLock, crossChainFees);

        bytes32[] memory beneficiaryArr = new bytes32[](1);
        beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
        ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
        beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);
        address[] memory plugins = _getOneInitPluginList(lensPlugin);
        ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(customRefCode, beneficiaryArr, beneficiaryConfigArr, plugins, 180 days, 90 days);

        buildRoll();
        address payable cl = buildManager.buildCryptoLegacy{value: deBridgeFee * 2 + 3}(buildArgs, refArgs, _getCreate2ArgsStruct(address(0), 0));
        assertEq(LensPlugin(cl).lastUpdateAt(), block.timestamp);
        assertEq(LensPlugin(cl).lastFeePaidAt(), 0);

        vm.startPrank(dan);

        uint256 discount = lifetimeFee * refDiscountPct / 10000;
        feeRegistry.getCodePct(customRefCode);

        buildRoll();
        cl = buildManager.buildCryptoLegacy{value: lifetimeFee - discount}(buildArgs, _getRefArgsStruct(address(0)),  _getCreate2ArgsStruct(address(0), 0));
        assertEq(feeRegistry.isNftLocked(dan), true);
        assertEq(lifetimeNft.totalSupply(), 1);

        vm.warp(block.timestamp + 1);

        buildRoll();
        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee * 2 + 3));
        buildManager.buildCryptoLegacy{value: deBridgeFee * 2}(buildArgs, refArgs, _getCreate2ArgsStruct(address(0), 0));

        buildRoll();
        cl = buildManager.buildCryptoLegacy{value: deBridgeFee * 2 + 3}(buildArgs, refArgs, _getCreate2ArgsStruct(address(0), 0));
        assertEq(LensPlugin(cl).lastUpdateAt(), block.timestamp);
        assertEq(LensPlugin(cl).lastFeePaidAt(), block.timestamp);

        vm.stopPrank();
    }

    function testCrossChainLockAndUnlock() public {
        uint256 tokenId = 1;
        address holder = alice;
        uint256[] memory chainIdsToLock = new uint256[](1);
        chainIdsToLock[0] = SIDE_CHAIN_ID_1;

        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee));
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), holder, chainIdsToLock, chainIdsToLock);

        vm.expectEmit(true, true, true, false);
        emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_1, deBridgeFee);
        buildManager.payInitialFee{value: lifetimeFee + deBridgeFee}(bytes8(0), holder, chainIdsToLock, chainIdsToLock);

        uint256[] memory lockedToChainIds = mainLock.getLockedToChainsIdsOfAccount(holder);
        assertEq(lockedToChainIds.length, 1);
        assertEq(lockedToChainIds[0], chainIdsToLock[0]);

        uint256 lockBlockTimestamp = block.timestamp;
        ILockChainGate.LockedNft memory lNft = mainLock.lockedNft(holder);
        assertEq(lNft.lockedAt, lockBlockTimestamp);
        assertEq(lNft.tokenId, tokenId);

        assertEq(sideLock1.ownerOfTokenId(tokenId), address(0));

        mockCallProxy.setSourceChainIdAndContract(mainLock);

        mockDeBridgeGate.executeLastMessage();
        _checkDeBridgeCallData(abi.encodeWithSelector(sideLock1.crossLockLifetimeNft.selector, MAIN_CHAIN_ID, tokenId, holder));

        assertEq(sideLock1.ownerOfTokenId(tokenId), holder);
        assertEq(sideLock1.lockedNftFromChainId(tokenId), MAIN_CHAIN_ID);

        vm.expectRevert(ILockChainGate.TokenNotLocked.selector);
        sideLock1.unlockLifetimeNftFromChain(tokenId);

        vm.prank(holder);
        vm.expectRevert(ILockChainGate.TooEarly.selector);
        sideLock1.unlockLifetimeNftFromChain(tokenId);

        vm.warp(block.timestamp + LOCK_PERIOD + 1);

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee));
        sideLock1.unlockLifetimeNftFromChain(tokenId);

        vm.prank(owner);
        sideLock1.setDestinationChainContract(MAIN_CHAIN_ID, address(0));

        vm.prank(holder);
        vm.expectRevert(ILockChainGate.DestinationChainNotSpecified.selector);
        sideLock1.unlockLifetimeNftFromChain(tokenId);

        vm.prank(owner);
        sideLock1.setDestinationChainContract(MAIN_CHAIN_ID, address(mainLock));

        vm.prank(holder);
        vm.expectEmit(true, true, true, false);
        emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_1, deBridgeFee + 1);
        sideLock1.unlockLifetimeNftFromChain{value: deBridgeFee + 1}(tokenId);

        vm.expectRevert(ILockChainGate.NotCallProxy.selector);
        mainLock.crossUnlockLifetimeNft(SIDE_CHAIN_ID_1, tokenId, holder);

        mockCallProxy.setSourceChainIdAndContract(sideLock1);
        mockDeBridgeGate.executeLastMessage();
        _checkDeBridgeCallData(abi.encodeWithSelector(mainLock.crossUnlockLifetimeNft.selector, SIDE_CHAIN_ID_1, tokenId, holder));

        lockedToChainIds = mainLock.getLockedToChainsIdsOfAccount(holder);
        assertEq(lockedToChainIds.length, 0);

        lNft = mainLock.lockedNft(holder);
        assertEq(lNft.lockedAt, lockBlockTimestamp);
        assertEq(lNft.tokenId, tokenId);
    }

    function testCrossChainLockAndTransfer() public {
        uint256 tokenId = 1;
        address holder = alice;
        uint256[] memory chainIdsToLock = new uint256[](2);
        chainIdsToLock[0] = SIDE_CHAIN_ID_1;
        chainIdsToLock[1] = SIDE_CHAIN_ID_2;

        uint256[] memory crossChainFees = new uint256[](2);
        crossChainFees[0] = deBridgeFee + 1;
        crossChainFees[1] = deBridgeFee + 2;

        assertEq(feeRegistry.getDeBridgeChainNativeFeeAndCheck{value: deBridgeFee + 1}(SIDE_CHAIN_ID_1, deBridgeFee + 1), deBridgeFee + 1);

        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee * 2 + 3));
        buildManager.payInitialFee{value: lifetimeFee + deBridgeFee * 2}(bytes8(0), holder, chainIdsToLock, crossChainFees);

        vm.expectEmit(true, true, false, false);
        emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_1, deBridgeFee + 1);
        vm.expectEmit(true, true, false, false);
        emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_2, deBridgeFee + 2);
        buildManager.payInitialFee{value: lifetimeFee + deBridgeFee * 2 + 3}(bytes8(0), holder, chainIdsToLock, crossChainFees);

        assertEq(feeRegistry.isNftLocked(charlie), false);
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), charlie, _getEmptyUintList(), _getEmptyUintList());
        assertEq(feeRegistry.isNftLocked(charlie), true);

        uint256[] memory lockedToChainIds = mainLock.getLockedToChainsIdsOfAccount(holder);
        assertEq(lockedToChainIds.length, 2);
        assertEq(lockedToChainIds[0], SIDE_CHAIN_ID_1);
        assertEq(lockedToChainIds[1], SIDE_CHAIN_ID_2);

        mockCallProxy.setSourceChainIdAndContract(mainLock);
        mockDeBridgeGate.executeLastMessage();
        _checkDeBridgeCallData(abi.encodeWithSelector(sideLock2.crossLockLifetimeNft.selector, MAIN_CHAIN_ID, tokenId, holder));

        vm.expectRevert("Ownable: caller is not the owner");
        sideLock1.setSourceChainContract(MAIN_CHAIN_ID, address(0));

        vm.prank(owner);
        sideLock1.setSourceChainContract(MAIN_CHAIN_ID, address(0));

        vm.prank(address(mockCallProxy));
        vm.expectRevert(ILockChainGate.SourceNotSpecified.selector);
        sideLock1.crossLockLifetimeNft(MAIN_CHAIN_ID, tokenId, holder);

        vm.prank(owner);
        sideLock1.setSourceChainContract(MAIN_CHAIN_ID, address(mainLock));

        vm.prank(address(mockCallProxy));
        sideLock1.crossLockLifetimeNft(MAIN_CHAIN_ID, tokenId, holder);

        assertEq(sideLock1.ownerOfTokenId(tokenId), holder);
        assertEq(sideLock2.ownerOfTokenId(tokenId), holder);

        address newHolder = bob;

        vm.expectRevert(ILockChainGate.NotAvailable.selector);
        mainLock.transferLifetimeNftTo(tokenId, newHolder, chainIdsToLock, crossChainFees);

        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee * 2 + 3));
        vm.prank(holder);
        mainLock.transferLifetimeNftTo(tokenId, newHolder, chainIdsToLock, crossChainFees);

        vm.expectRevert("Ownable: caller is not the owner");
        feeRegistry.setDebridgeNativeFee(SIDE_CHAIN_ID_1, deBridgeFee * 2);

        vm.prank(owner);
        feeRegistry.setDebridgeNativeFee(SIDE_CHAIN_ID_1, deBridgeFee * 2);
        assertEq(feeRegistry.getDeBridgeChainNativeFee(SIDE_CHAIN_ID_1, 0), deBridgeFee * 2);
        assertEq(feeRegistry.getDeBridgeChainNativeFee(SIDE_CHAIN_ID_1, deBridgeFee), deBridgeFee * 2);

        assertEq(feeRegistry.calculateCrossChainCreateRefNativeFee(chainIdsToLock, crossChainFees), deBridgeFee * 3 + 2);

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee * 3 + 2));
        mainLock.transferLifetimeNftTo{value: deBridgeFee * 2 + 3}(tokenId, newHolder, chainIdsToLock, crossChainFees);

        vm.prank(holder);
        vm.expectRevert(ILockChainGate.RecipientLocked.selector);
        mainLock.transferLifetimeNftTo{value: deBridgeFee * 2 + 3}(tokenId, charlie, chainIdsToLock, crossChainFees);

        vm.prank(holder);
        vm.expectRevert(ILockChainGate.SameAddress.selector);
        mainLock.transferLifetimeNftTo{value: deBridgeFee * 2 + 3}(tokenId, holder, chainIdsToLock, crossChainFees);

        assertEq(sideLock1.isNftLocked(newHolder), false);
        assertEq(sideLock1.isNftLocked(holder), true);

        vm.prank(holder);
        mainLock.transferLifetimeNftTo{value: deBridgeFee * 3 + 3}(tokenId, newHolder, chainIdsToLock, crossChainFees);

        vm.prank(holder);
        vm.expectRevert(ILockChainGate.NotAvailable.selector);
        mainLock.unlockLifetimeNft(tokenId);

        vm.prank(newHolder);
        vm.expectRevert(ILockChainGate.LockedToChains.selector);
        mainLock.unlockLifetimeNft(tokenId);

        vm.prank(owner);
        feeRegistry.setDebridgeNativeFee(SIDE_CHAIN_ID_1, deBridgeFee);

        assertEq(feeRegistry.calculateCrossChainCreateRefNativeFee(chainIdsToLock, crossChainFees), deBridgeFee * 2 + 3);

        lockedToChainIds = mainLock.getLockedToChainsIdsOfAccount(newHolder);
        assertEq(lockedToChainIds.length, 2);
        assertEq(lockedToChainIds[0], SIDE_CHAIN_ID_1);
        assertEq(lockedToChainIds[1], SIDE_CHAIN_ID_2);

        assertEq(mainLock.ownerOfTokenId(tokenId), newHolder);
        ILockChainGate.LockedNft memory lNft = mainLock.lockedNft(newHolder);
        assertEq(lNft.lockedAt, block.timestamp);
        assertEq(lNft.tokenId, tokenId);

        lNft = mainLock.lockedNft(holder);
        assertEq(lNft.lockedAt, 0);
        assertEq(lNft.tokenId, 0);

        mockCallProxy.setSourceChainIdAndContract(sideLock1);

        vm.prank(address(mockCallProxy));
        vm.expectRevert(ILockChainGate.ChainIdMismatch.selector);
        sideLock2.crossUpdateNftOwner(MAIN_CHAIN_ID, tokenId, newHolder);

        mockCallProxy.setSourceChainIdAndContract(MAIN_CHAIN_ID, sideLock1);

        vm.prank(address(mockCallProxy));
        vm.expectRevert(ILockChainGate.NotValidSender.selector);
        sideLock2.crossUpdateNftOwner(MAIN_CHAIN_ID, tokenId, newHolder);

        mockCallProxy.setSourceChainIdAndContract(mainLock);
        mockDeBridgeGate.executeLastMessage();

        assertEq(mockDeBridgeGate.targetContractAddress(), address(sideLock2));
        _checkDeBridgeCallData(abi.encodeWithSelector(sideLock2.crossUpdateNftOwner.selector, MAIN_CHAIN_ID, tokenId, newHolder));

        vm.prank(address(mockCallProxy));
        sideLock1.crossUpdateNftOwner(MAIN_CHAIN_ID, tokenId, newHolder);

        assertEq(sideLock1.ownerOfTokenId(tokenId), newHolder);
        assertEq(sideLock2.ownerOfTokenId(tokenId), newHolder);

        vm.prank(holder);
        vm.expectRevert(ILockChainGate.TokenNotLocked.selector);
        sideLock1.unlockLifetimeNftFromChain{value: deBridgeFee + 1}(tokenId);

        vm.prank(newHolder);
        vm.expectRevert(ILockChainGate.TooEarly.selector);
        sideLock1.unlockLifetimeNftFromChain{value: deBridgeFee + 1}(tokenId);

        vm.warp(block.timestamp + LOCK_PERIOD + 1);

        vm.prank(newHolder);
        vm.expectRevert(ILockChainGate.CrossChainLock.selector);
        sideLock2.unlockLifetimeNft(tokenId);
        assertEq(sideLock1.isNftLocked(newHolder), true);
        assertEq(sideLock1.isNftLocked(holder), false);

        vm.prank(newHolder);
        vm.expectEmit(true, true, true, false);
        emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_1, deBridgeFee + 1);
        sideLock1.unlockLifetimeNftFromChain{value: deBridgeFee + 1}(tokenId);

        mockCallProxy.setSourceChainIdAndContract(sideLock1);
        mockDeBridgeGate.executeLastMessage();
        _checkDeBridgeCallData(abi.encodeWithSelector(mainLock.crossUnlockLifetimeNft.selector, SIDE_CHAIN_ID_1, tokenId, newHolder));

        lockedToChainIds = mainLock.getLockedToChainsIdsOfAccount(newHolder);
        assertEq(lockedToChainIds.length, 1);
        assertEq(lockedToChainIds[0], SIDE_CHAIN_ID_2);

        vm.prank(newHolder);
        mainLock.transferLifetimeNftTo(tokenId, dan, _getEmptyUintList(), _getEmptyUintList());

        assertEq(mainLock.ownerOfTokenId(tokenId), dan);

        vm.prank(newHolder);
        vm.expectRevert(ILockChainGate.NotAvailable.selector);
        mainLock.updateNftOwnerOnChainList{value: deBridgeFee * 2 + 3}(tokenId, chainIdsToLock, crossChainFees);

        vm.expectRevert("Ownable: caller is not the owner");
        mainLock.setDestinationChainContract(SIDE_CHAIN_ID_1, address(0));

        vm.prank(owner);
        mainLock.setDestinationChainContract(SIDE_CHAIN_ID_1, address(0));

        vm.prank(dan);
        vm.expectRevert(ILockChainGate.DestinationChainNotSpecified.selector);
        mainLock.updateNftOwnerOnChainList{value: deBridgeFee * 2 + 3}(tokenId, chainIdsToLock, crossChainFees);

        vm.prank(owner);
        mainLock.setDestinationChainContract(SIDE_CHAIN_ID_1, address(sideLock1));

        vm.prank(dan);
        mainLock.updateNftOwnerOnChainList{value: deBridgeFee * 2 + 3}(tokenId, chainIdsToLock, crossChainFees);

        mockCallProxy.setSourceChainIdAndContract(mainLock);
        mockDeBridgeGate.executeLastMessage();
        assertEq(mockDeBridgeGate.targetContractAddress(), address(sideLock2));
        _checkDeBridgeCallData(abi.encodeWithSelector(sideLock2.crossUpdateNftOwner.selector, MAIN_CHAIN_ID, tokenId, dan));

        assertEq(sideLock2.ownerOfTokenId(tokenId), dan);
    }

    function testCrossChainLockAndTransferByUpdate() public {
        _addBasePluginsToRegistry();

        address holder = bob;
        uint256[] memory chainIdsToLock = new uint256[](2);
        chainIdsToLock[0] = SIDE_CHAIN_ID_1;
        chainIdsToLock[1] = SIDE_CHAIN_ID_2;

        uint256[] memory crossChainFees = new uint256[](2);
        crossChainFees[0] = deBridgeFee + 1;
        crossChainFees[1] = deBridgeFee + 2;

        bytes8 customRefCode = 0x0123456789abcdef;
        vm.prank(alice);
        buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());

        (CryptoLegacyBasePlugin cryptoLegacy, , , ) = _buildCryptoLegacy(holder, buildFee, customRefCode);
        vm.warp(block.timestamp + 1);

        uint256 discount = lifetimeFee * refDiscountPct / 10000;

        assertEq(buildManager.isLifetimeNftLocked(holder), false);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.IncorrectFee.selector, updateFee - updateFee * refDiscountPct / 10000));
        cryptoLegacy.update{value: lifetimeFee - discount + deBridgeFee * 2}(chainIdsToLock, crossChainFees);

        vm.expectEmit(true, true, false, false);
        emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_1, deBridgeFee + 1);
        vm.expectEmit(true, true, false, false);
        emit MockDeBridgeGate.SentMessage(SIDE_CHAIN_ID_2, deBridgeFee + 2);

        vm.prank(holder);
        uint256[] memory tooLongChainIdsToLock = new uint256[](200);
        vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.TooLongArray.selector, 100));
        cryptoLegacy.update{value: lifetimeFee - discount + deBridgeFee * 2 + 3}(tooLongChainIdsToLock, crossChainFees);

        vm.prank(holder);
        cryptoLegacy.update{value: lifetimeFee - discount + deBridgeFee * 2 + 3}(chainIdsToLock, crossChainFees);

        assertEq(buildManager.isLifetimeNftLocked(holder), true);

        uint256[] memory lockedToChainIds = mainLock.getLockedToChainsIdsOfAccount(holder);
        assertEq(lockedToChainIds.length, 2);
        assertEq(lockedToChainIds[0], SIDE_CHAIN_ID_1);
        assertEq(lockedToChainIds[1], SIDE_CHAIN_ID_2);
    }

    function testTransferLockedNft() public {
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), alice, _getEmptyUintList(), _getEmptyUintList());
        assertEq(lifetimeNft.totalSupply(), 1);

        ILockChainGate.LockedNft memory lNft = feeRegistry.lockedNft(alice);
        assertEq(lifetimeNft.ownerOf(lNft.tokenId), address(feeRegistry));
        uint256 tokenId = lNft.tokenId;

        uint256[] memory chainIdsToLock = new uint256[](1);
        chainIdsToLock[0] = SIDE_CHAIN_ID_1;

        uint256[] memory crossChainFees = new uint256[](1);
        crossChainFees[0] = deBridgeFee + 1;

        vm.prank(alice);
        feeRegistry.approveLifetimeNftTo(lNft.tokenId, dan);

        assertEq(feeRegistry.ownerOfTokenId(lNft.tokenId), alice);
        assertEq(feeRegistry.lockedNftApprovedTo(lNft.tokenId), dan);
        vm.prank(alice);
        feeRegistry.transferLifetimeNftTo{value: deBridgeFee + 1}(lNft.tokenId, bob, chainIdsToLock, crossChainFees);
        assertEq(feeRegistry.ownerOfTokenId(lNft.tokenId), bob);
        assertEq(feeRegistry.lockedNftApprovedTo(lNft.tokenId), address(0));

        lNft = feeRegistry.lockedNft(alice);
        assertEq(lNft.lockedAt, 0);
        assertEq(lNft.tokenId, 0);

        lNft = feeRegistry.lockedNft(bob);
        assertEq(lNft.lockedAt, block.timestamp);
        assertEq(lNft.tokenId, tokenId);

        lNft = sideLock1.lockedNft(bob);
        assertEq(lNft.lockedAt, 0);
        assertEq(lNft.tokenId, 0);

        assertEq(mockDeBridgeGate.targetContractAddress(), address(sideLock1));
        mockCallProxy.setSourceChainIdAndContract(mainLock);
        mockDeBridgeGate.executeLastMessage();

        lNft = sideLock1.lockedNft(bob);
        assertEq(lNft.lockedAt, block.timestamp);
        assertEq(lNft.tokenId, tokenId);

        vm.prank(bob);
        vm.expectRevert(ILockChainGate.LockedToChains.selector);
        feeRegistry.unlockLifetimeNft(tokenId);

        uint256[] memory lockedToChains = feeRegistry.getLockedToChainsIdsOfAccount(bob);
        assertEq(lockedToChains.length, 1);
        assertEq(lockedToChains[0], SIDE_CHAIN_ID_1);

        vm.prank(alice);
        vm.expectRevert(ILockChainGate.TokenNotLocked.selector);
        sideLock1.unlockLifetimeNftFromChain(tokenId);

        vm.prank(bob);
        vm.expectRevert(ILockChainGate.TooEarly.selector);
        sideLock1.unlockLifetimeNftFromChain(tokenId);

        vm.warp(lNft.lockedAt + sideLock1.lockPeriod() + 1);

        vm.prank(bob);
        sideLock1.unlockLifetimeNftFromChain{value: deBridgeFee}(tokenId);
        mockCallProxy.setSourceChainIdAndContract(sideLock1);
        mockDeBridgeGate.executeLastMessage();

        lNft = sideLock1.lockedNft(bob);
        assertEq(lNft.lockedAt, 0);
        assertEq(lNft.tokenId, 0);

        vm.prank(dan);
        vm.expectRevert(ILockChainGate.NotAvailable.selector);
        feeRegistry.unlockLifetimeNft(tokenId);

        vm.startPrank(bob);
        feeRegistry.unlockLifetimeNft(tokenId);

        assertEq(feeRegistry.ownerOfTokenId(tokenId), address(0));
        assertEq(feeRegistry.lockedNftApprovedTo(tokenId), address(0));
        assertEq(lifetimeNft.ownerOf(tokenId), bob);

        lifetimeNft.approve(address(feeRegistry), tokenId);
        feeRegistry.lockLifetimeNft(tokenId, bob, _getEmptyUintList(), _getEmptyUintList());

        vm.expectRevert(ICryptoLegacy.TooEarly.selector);
        feeRegistry.unlockLifetimeNft(tokenId);
        vm.stopPrank();

        assertEq(feeRegistry.ownerOfTokenId(tokenId), bob);
        assertEq(lifetimeNft.ownerOf(tokenId), address(feeRegistry));

        ILockChainGate.LockedNft memory bobLNft = feeRegistry.lockedNft(bob);
        assertEq(tokenId, bobLNft.tokenId);
        assertEq(bobLNft.lockedAt, block.timestamp);
    }

    function testLockingAlreadyLockedToChain() public {
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), alice, _getEmptyUintList(), _getEmptyUintList());
        assertEq(lifetimeNft.totalSupply(), 1);

        uint256 tokenId = 1;

        uint256[] memory chainIdsToLock = new uint256[](2);
        chainIdsToLock[0] = SIDE_CHAIN_ID_1;
        chainIdsToLock[1] = SIDE_CHAIN_ID_2;

        uint256[] memory crossChainFees = new uint256[](2);

        vm.prank(bob);
        vm.expectRevert(ILockChainGate.TokenNotLocked.selector);
        feeRegistry.lockLifetimeNftToChains(chainIdsToLock, crossChainFees);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, deBridgeFee * 2));
        feeRegistry.lockLifetimeNftToChains(chainIdsToLock, crossChainFees);

        vm.prank(alice);
        feeRegistry.lockLifetimeNftToChains{value: deBridgeFee * 2}(chainIdsToLock, crossChainFees);

        uint256[] memory gotChainIds = feeRegistry.getLockedToChainsIds(tokenId);
        assertEq(chainIdsToLock, gotChainIds);

        chainIdsToLock = new uint256[](1);
        chainIdsToLock[0] = SIDE_CHAIN_ID_1;
        crossChainFees = new uint256[](1);

        vm.prank(alice);
        vm.expectRevert(ILockChainGate.AlreadyLockedToChain.selector);
        feeRegistry.lockLifetimeNftToChains(chainIdsToLock, crossChainFees);

        vm.prank(alice);
        vm.expectRevert(ILockChainGate.NotLockedByChain.selector);
        feeRegistry.unlockLifetimeNftFromChain(tokenId);
    }
}