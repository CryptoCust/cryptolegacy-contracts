// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AbstractTestHelper.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/mocks/MockERC721.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/plugins/NftLegacyPlugin.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/interfaces/ICryptoLegacy.sol";
import "../contracts/mocks/MockMaliciousERC20.sol";
import "../contracts/mocks/MockMaliciousERC721.sol";
import "../contracts/interfaces/ICryptoLegacyLens.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CryptoLegacyNftTest is AbstractTestHelper {
    address internal nftPlugin;

    function setUp() public override {
        super.setUp();
        vm.startPrank(owner);
        pluginsRegistry.addPlugin(cryptoLegacyBasePlugin, "");

        nftPlugin = address(new NftLegacyPlugin());
        lensPlugin = address(new LensPlugin());
        vm.stopPrank();

        vm.startPrank(owner);
        mockToken1 = new MockERC20("Mock", "MOCK");
        mockToken1.mint(treasury, 1000 ether);
        mockToken1.mint(bob, 100000 ether);
        vm.stopPrank();
    }

    function testTokenUri() public {
        string memory uri = "test/";

        vm.expectRevert("Ownable: caller is not the owner");
        lifetimeNft.setBaseUri(uri);

        vm.prank(owner);
        lifetimeNft.setBaseUri(uri);

        vm.expectRevert(ILifetimeNft.NotTheMinter.selector);
        lifetimeNft.mint(alice);

        vm.prank(owner);
        lifetimeNft.setMinterOperator(owner, true);
        vm.prank(owner);
        lifetimeNft.mint(alice);

        assertEq(lifetimeNft.tokenURI(1), "test/1");
    }

    function testLifetimeFee() public {
        assertEq(feeRegistry.getLockOperatorsList().length, 1);
        assertEq(feeRegistry.getLockOperatorsList()[0], address(buildManager));
        assertEq(feeRegistry.isLockOperator(address(buildManager)), true);

        vm.startPrank(owner);
        feeRegistry.setLockOperator(address(buildManager), false);
        pluginsRegistry.addPlugin(lensPlugin, "");

        assertEq(feeRegistry.getLockOperatorsList().length, 0);
        assertEq(feeRegistry.isLockOperator(address(buildManager)), false);

        IFeeRegistry.FeeBeneficiary[] memory custBeneficiaryConfigArr = new IFeeRegistry.FeeBeneficiary[](1);
        custBeneficiaryConfigArr[0] = IFeeRegistry.FeeBeneficiary(custFeeRecipient1, 10000);
        feeRegistry.setFeeBeneficiaries(custBeneficiaryConfigArr);
        vm.stopPrank();

        bytes8 customRefCode = 0x0123456789abcdef;
        vm.prank(alice);
        buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());

        bytes32[] memory beneficiaryArr = new bytes32[](1);
        beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
        ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
        beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);
        address[] memory plugins = _getOneInitPluginList(lensPlugin);

        vm.startPrank(dan);

        address payable cl;
        ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(bytes8(0), beneficiaryArr, beneficiaryConfigArr, plugins, updateInterval, challengeTimeout);
        buildRoll();
        cl = buildManager.buildCryptoLegacy{value: buildFee}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), 0));
        assertEq(feeRegistry.isNftLocked(dan), false);
        assertEq(lifetimeNft.totalSupply(), 0);
        feeRegistry.withdrawAccumulatedFee();

        uint256 discount = lifetimeFee * refDiscountPct / 10000;
        uint256 share = lifetimeFee * refSharePct / 10000;
        buildArgs.invitedByRefCode = customRefCode;
        buildRoll();
        uint256 createdAt = block.timestamp;
        vm.expectRevert(ILockChainGate.NotAllowed.selector);
        buildManager.buildCryptoLegacy{value: lifetimeFee - discount}(buildArgs, _getRefArgsStruct(address(0)),  _getCreate2ArgsStruct(address(0), 0));
        vm.stopPrank();

        vm.expectRevert("Ownable: caller is not the owner");
        feeRegistry.setLockOperator(address(buildManager), true);

        vm.prank(owner);
        feeRegistry.setLockOperator(address(buildManager), true);

        vm.startPrank(dan);
        cl = buildManager.buildCryptoLegacy{value: lifetimeFee - discount}(buildArgs, _getRefArgsStruct(address(0)),  _getCreate2ArgsStruct(address(0), 0));

        assertEq(aliceRecipient.balance, share);
        assertEq(address(feeRegistry).balance, lifetimeFee - discount - share);
        assertEq(feeRegistry.isNftLocked(dan), true);
        assertEq(lifetimeNft.totalSupply(), 1);

        vm.warp(block.timestamp + 1);

        ILockChainGate.LockedNft memory lockedNft = feeRegistry.lockedNft(dan);
        assertEq(createdAt, lockedNft.lockedAt);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        assertEq(tokenIds, lifetimeNft.tokensOfOwner(address(feeRegistry)));

        vm.expectRevert(ICryptoLegacy.TooEarly.selector);
        feeRegistry.unlockLifetimeNft(1);

        vm.warp(block.timestamp + 1);

        CryptoLegacyBasePlugin cryptoLegacy = CryptoLegacyBasePlugin(cl);
        ICryptoLegacyLens cryptoLegacyLens = ICryptoLegacyLens(cl);
        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        vm.warp(block.timestamp + clData.updateInterval);

        vm.expectRevert(ICryptoLegacy.NoValueAllowed.selector);
        cryptoLegacy.update{value: updateFee}(_getEmptyUintList(), _getEmptyUintList());

        cryptoLegacy.update(_getEmptyUintList(), _getEmptyUintList());
        clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        assertEq(clData.lastUpdateAt, block.timestamp);
        assertEq(clData.lastFeePaidAt, block.timestamp);

        vm.warp(block.timestamp + 1);

        buildRoll();
        vm.expectRevert(ILockChainGate.AlreadyLocked.selector);
        cl = buildManager.buildCryptoLegacy{value: lifetimeFee - discount}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), 0));

        assertGt(feeRegistry.getLockedUntil(dan), block.timestamp);
        vm.warp(block.timestamp + 61);
        assertGt(block.timestamp, feeRegistry.getLockedUntil(dan));

        lockedNft = feeRegistry.lockedNft(dan);
        uint lockedAtBefore = lockedNft.lockedAt;

        buildRoll();
        cl = buildManager.buildCryptoLegacy(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), 0));
        clData = ICryptoLegacyLens(cl).getCryptoLegacyBaseData();
        assertEq(clData.lastUpdateAt, block.timestamp);

        lockedNft = feeRegistry.lockedNft(dan);
        assertNotEq(lockedAtBefore, lockedNft.lockedAt);
        assertGt(feeRegistry.getLockedUntil(dan), block.timestamp);
        assertNotEq(createdAt, lockedNft.lockedAt);
        assertEq(block.timestamp, lockedNft.lockedAt);

        vm.warp(block.timestamp + 61);

        lockedNft = feeRegistry.lockedNft(dan);
        assertGt(block.timestamp, feeRegistry.getLockedUntil(dan));

        cryptoLegacy.update(_getEmptyUintList(), _getEmptyUintList());

        lockedNft = feeRegistry.lockedNft(dan);
        assertGt(feeRegistry.getLockedUntil(dan), block.timestamp);
        assertNotEq(createdAt, lockedNft.lockedAt);
        assertEq(block.timestamp, lockedNft.lockedAt);

        vm.warp(block.timestamp + 1);

        lockedNft = feeRegistry.lockedNft(dan);
        lockedAtBefore = lockedNft.lockedAt;
        cryptoLegacy.update(_getEmptyUintList(), _getEmptyUintList());
        lockedNft = feeRegistry.lockedNft(dan);
        assertEq(lockedAtBefore, lockedNft.lockedAt);

        vm.expectRevert(ILockChainGate.TooEarly.selector);
        feeRegistry.unlockLifetimeNft(lockedNft.tokenId);

        vm.warp(block.timestamp + 61);

        tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        assertEq(tokenIds, lifetimeNft.tokensOfOwner(address(feeRegistry)));

        feeRegistry.unlockLifetimeNft(lockedNft.tokenId);
        assertEq(feeRegistry.isNftLocked(dan), false);
        assertEq(cryptoLegacy.owner(), dan);

        vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.IncorrectFee.selector, updateFee - updateFee * refDiscountPct / 10000));
        cryptoLegacy.update(_getEmptyUintList(), _getEmptyUintList());

        vm.stopPrank();
    }

    function testLockingAlreadyLocked() public {
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), alice, _getEmptyUintList(), _getEmptyUintList());
        assertEq(lifetimeNft.totalSupply(), 1);
        vm.expectRevert(ILockChainGate.AlreadyLocked.selector);
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), alice, _getEmptyUintList(), _getEmptyUintList());
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), bob, _getEmptyUintList(), _getEmptyUintList());
        assertEq(lifetimeNft.totalSupply(), 2);

        ILockChainGate.LockedNft memory lockedNft = feeRegistry.lockedNft(alice);
        uint256 tokenId = lockedNft.tokenId;
        uint256 lockedAt = lockedNft.lockedAt;
        assertEq(lifetimeNft.ownerOf(tokenId), address(feeRegistry));

        vm.startPrank(alice);
        vm.expectRevert(ICryptoLegacy.TooEarly.selector);
        feeRegistry.unlockLifetimeNft(tokenId);

        vm.warp(lockedAt + feeRegistry.lockPeriod() / 2);
        vm.expectRevert(ICryptoLegacy.TooEarly.selector);
        feeRegistry.unlockLifetimeNft(tokenId);

        vm.warp(lockedAt + feeRegistry.lockPeriod() + 1);
        feeRegistry.unlockLifetimeNft(tokenId);
        lifetimeNft.transferFrom(alice, bob, tokenId);
        vm.stopPrank();

        vm.startPrank(bob);
        lifetimeNft.approve(address(feeRegistry), tokenId);
        vm.expectRevert(ILockChainGate.AlreadyLocked.selector);
        feeRegistry.lockLifetimeNft(tokenId, bob, _getEmptyUintList(), _getEmptyUintList());
        vm.stopPrank();
    }

    function testUnlockByApprove() public {
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), alice, _getEmptyUintList(), _getEmptyUintList());
        assertEq(lifetimeNft.totalSupply(), 1);

        ILockChainGate.LockedNft memory lockedNft = feeRegistry.lockedNft(alice);
        uint256 tokenId = lockedNft.tokenId;
        uint256 lockedAt = lockedNft.lockedAt;
        assertEq(lifetimeNft.ownerOf(tokenId), address(feeRegistry));

        vm.expectRevert(ILockChainGate.NotAllowed.selector);
        feeRegistry.isNftLockedAndUpdate(alice);

        vm.prank(bob);
        vm.expectRevert(ILockChainGate.NotAllowed.selector);
        feeRegistry.isNftLockedAndUpdate(alice);

        vm.prank(alice);
        assertEq(feeRegistry.isNftLockedAndUpdate(alice), true);

        vm.prank(alice);
        feeRegistry.approveLifetimeNftTo(tokenId, bob);

        vm.prank(alice);
        assertEq(feeRegistry.isNftLockedAndUpdate(alice), true);
        vm.prank(bob);
        assertEq(feeRegistry.isNftLockedAndUpdate(alice), true);

        vm.prank(bob);
        vm.expectRevert(ICryptoLegacy.TooEarly.selector);
        feeRegistry.unlockLifetimeNft(tokenId);

        vm.warp(lockedAt + feeRegistry.lockPeriod() + 1);
        assertEq(feeRegistry.lockedNft(alice).lockedAt, lockedAt);

        vm.prank(bob);
        assertEq(feeRegistry.isNftLockedAndUpdate(alice), true);
        assertNotEq(feeRegistry.lockedNft(alice).lockedAt, lockedAt);
        assertEq(feeRegistry.lockedNft(alice).lockedAt, block.timestamp);

        vm.warp(feeRegistry.lockedNft(alice).lockedAt + feeRegistry.lockPeriod() + 1);

        vm.prank(dan);
        vm.expectRevert(ILockChainGate.NotAvailable.selector);
        feeRegistry.unlockLifetimeNft(tokenId);

        vm.startPrank(bob);
        assertEq(feeRegistry.ownerOfTokenId(tokenId), alice);
        assertEq(feeRegistry.lockedNftApprovedTo(tokenId), bob);
        feeRegistry.unlockLifetimeNft(tokenId);

        assertEq(feeRegistry.ownerOfTokenId(tokenId), address(0));
        assertEq(feeRegistry.lockedNftApprovedTo(tokenId), address(0));
        lockedNft = feeRegistry.lockedNft(alice);
        assertEq(lockedNft.lockedAt, 0);
        assertEq(lockedNft.tokenId, 0);
        assertEq(lifetimeNft.ownerOf(tokenId), bob);

        lifetimeNft.approve(address(feeRegistry), tokenId);
        feeRegistry.lockLifetimeNft(tokenId, bob, _getEmptyUintList(), _getEmptyUintList());

        vm.expectRevert(ICryptoLegacy.TooEarly.selector);
        feeRegistry.unlockLifetimeNft(tokenId);
        vm.stopPrank();

        assertEq(feeRegistry.ownerOfTokenId(tokenId), bob);
        assertEq(lifetimeNft.ownerOf(tokenId), address(feeRegistry));

        lockedNft = feeRegistry.lockedNft(bob);
        assertEq(tokenId, lockedNft.tokenId);
        assertEq(lockedNft.lockedAt, block.timestamp);
    }

    function testNftLegacyPlugin() public {
        vm.prank(owner);
        pluginsRegistry.addPlugin(lensPlugin, "");

        vm.prank(alice);
        (bytes8 refCode, , ) = buildManager.createRef(aliceRecipient, _getRefChains(), _getRefChains());

        vm.startPrank(owner);
        MockERC721 nft = new MockERC721();
        nft.transferFrom(owner, treasury, 1);
        nft.transferFrom(owner, treasury, 2);
        nft.transferFrom(owner, treasury, 3);
        vm.stopPrank();

        bytes32[] memory beneficiaryArr = new bytes32[](2);
        beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
        beneficiaryArr[1] = keccak256(abi.encode(bobBeneficiary2));
        ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](2);
        beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 4000);
        beneficiaryConfigArr[1] = ICryptoLegacy.BeneficiaryConfig(20, 100, 6000);

        address[] memory plugins = _getOneInitPluginList(lensPlugin);

        buildRoll();
        vm.startPrank(bob);
        ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(refCode, beneficiaryArr, beneficiaryConfigArr, plugins, updateInterval, challengeTimeout);
        CryptoLegacyBasePlugin cryptoLegacy = CryptoLegacyBasePlugin(buildManager.buildCryptoLegacy(buildArgs, _getRefArgsStruct(bob), _getCreate2ArgsStruct(address(0), 0)));
        ICryptoLegacyLens cryptoLegacyLens = ICryptoLegacyLens(address(cryptoLegacy));
        NftLegacyPlugin nftLegacy = NftLegacyPlugin(address(cryptoLegacy));

        plugins = _getOneAddressList(address(new NftLegacyPlugin()));
        vm.expectRevert(ICryptoLegacy.InitialFeeNotPaid.selector);
        CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(plugins);
        vm.stopPrank();

        // can be paid by anyone
        cryptoLegacy.payInitialFee{value: 0.18 ether}(_getEmptyUintList(), _getEmptyUintList());

        vm.prank(bob);
        vm.expectRevert(ICryptoLegacy.PluginNotRegistered.selector);
        CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(plugins);

        vm.prank(owner);
        pluginsRegistry.addPlugin(plugins[0], "");

        {
            (
                string memory name,
                uint16 version,
                uint64[] memory descriptionBlockNumbers
            ) = pluginsRegistry.getPluginMetadata(plugins[0]);
            assertEq(descriptionBlockNumbers.length, 1);
            assertEq(descriptionBlockNumbers[0], block.number);
            assertEq(name, "nft_legacy");
            assertEq(version, uint16(1));
        }

        vm.expectRevert(ICryptoLegacy.NotTheOwner.selector);
        CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(plugins);

        vm.startPrank(bob);
        CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(plugins);

        vm.expectRevert(ICryptoLegacy.CantAddFunctionThatAlreadyExists.selector);
        plugins[0] = cryptoLegacyBasePlugin;
        CryptoLegacy(payable(address(cryptoLegacy))).addPluginList(plugins);
        vm.stopPrank();

        vm.prank(owner);
        pluginsRegistry.addPlugin(address(cryptoLegacy), "");

        vm.startPrank(bob);
        vm.expectRevert(ICryptoLegacy.CantRemoveImmutableFunctions.selector);
        plugins[0] = address(cryptoLegacy);
        CryptoLegacy(payable(address(cryptoLegacy))).removePluginList(plugins);

        uint256[] memory tokenIds1 = new uint256[](1);
        tokenIds1[0] = 1;
        uint256[] memory tokenIds2 = new uint256[](2);
        tokenIds2[0] = 2;
        tokenIds2[1] = 3;

        nftLegacy.setNftBeneficiary(keccak256(abi.encode(bobBeneficiary1)), address(nft), tokenIds1, 0);
        nftLegacy.setNftBeneficiary(keccak256(abi.encode(bobBeneficiary2)), address(nft), tokenIds2, 10);

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        vm.warp(block.timestamp + clData.updateInterval);
        cryptoLegacy.update{value: 0.09 ether}(_getEmptyUintList(), _getEmptyUintList());
        vm.stopPrank();

        vm.startPrank(treasury);
        mockToken1.approve(address(cryptoLegacy), 100 ether);
        nft.approve(address(cryptoLegacy), 1);
        nft.approve(address(cryptoLegacy), 2);
        nft.approve(address(cryptoLegacy), 3);
        vm.stopPrank();

        vm.warp(block.timestamp + clData.updateInterval + 1);
        vm.prank(bobBeneficiary1);
        cryptoLegacy.initiateChallenge();
        clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        assertEq(clData.distributionStartAt, block.timestamp + clData.challengeTimeout);

        vm.warp(block.timestamp + clData.challengeTimeout + 1);
        address[] memory _treasuries = new address[](1);
        _treasuries[0] = treasury;

        vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
        nftLegacy.transferNftTokensToLegacy(address(nft), _getThreeUintList(1, 2, 3));

        vm.startPrank(bobBeneficiary1);
        cryptoLegacy.transferTreasuryTokensToLegacy(_treasuries, _getOneAddressList(address(mockToken1)));

        vm.expectRevert(ICryptoLegacy.BeneficiaryNotSet.selector);
        nftLegacy.transferNftTokensToLegacy(address(nft), _getFourUintList(1, 2, 3, 4));

        nftLegacy.transferNftTokensToLegacy(address(nft), _getThreeUintList(1, 2, 3));
        vm.stopPrank();

        vm.prank(owner);
        vm.expectRevert(ICryptoLegacy.DistributionStarted.selector);
        nftLegacy.setNftBeneficiary(keccak256(abi.encode(bobBeneficiary1)), address(nft), tokenIds1, 0);

        assertEq(mockToken1.balanceOf(bobBeneficiary1), 0);

        vm.startPrank(bobBeneficiary1);

        vm.expectRevert(ICryptoLegacy.ZeroTokens.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), _getEmptyUintList());

        assertEq(nft.ownerOf(1), address(cryptoLegacy));
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds1);
        assertEq(nft.ownerOf(1), bobBeneficiary1);

        vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds2);

        vm.stopPrank();

        vm.prank(bobBeneficiary2);
        vm.expectRevert(ICryptoLegacy.DistributionDelay.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds2);

        vm.startPrank(bobBeneficiary1);

        vm.warp(block.timestamp + 10 + 1);
        cryptoLegacy.beneficiaryClaim{value: 0.09 ether}(_getOneAddressList(address(mockToken1)), address(0), 0);
        assertEq(mockToken1.balanceOf(bobBeneficiary1), 0.8 ether);

        vm.warp(block.timestamp + 2);
        cryptoLegacy.beneficiaryClaim{value: 0.09 ether}(_getOneAddressList(address(mockToken1)), address(0), 0);
        assertEq(mockToken1.balanceOf(bobBeneficiary1), 1.6 ether);

        vm.stopPrank();

        assertEq(nft.ownerOf(2), address(cryptoLegacy));
        assertEq(nft.ownerOf(3), address(cryptoLegacy));
        vm.prank(bobBeneficiary2);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds2);
        assertEq(nft.ownerOf(2), bobBeneficiary2);
        assertEq(nft.ownerOf(3), bobBeneficiary2);
    }

    function testMintAndLockNft() public {
        vm.prank(owner);
        pluginsRegistry.addPlugin(lensPlugin, "");
        vm.prank(owner);
        feeRegistry.setLockOperator(address(buildManager), true);

        bytes8 customRefCode = 0x0123456789abcdef;
        vm.prank(alice);
        (bytes8 refCode, , ) = buildManager.createCustomRef(customRefCode, aliceRecipient, _getRefChains(), _getRefChains());
        assertEq(refCode, customRefCode);

        buildRoll();
        vm.startPrank(dan);

        bytes32[] memory beneficiaryArr = new bytes32[](1);
        beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1));
        ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
        beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig(10, 100, 10000);
        ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(customRefCode, beneficiaryArr, beneficiaryConfigArr, _getOneInitPluginList(lensPlugin), updateInterval, challengeTimeout);
        address payable cl = buildManager.buildCryptoLegacy{value: 0}(buildArgs, _getRefArgsStruct(address(0)), _getCreate2ArgsStruct(address(0), 0));
        CryptoLegacyBasePlugin cryptoLegacy = CryptoLegacyBasePlugin(cl);
        ICryptoLegacyLens cryptoLegacyLens = ICryptoLegacyLens(cl);

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        assertEq(clData.initialFeeToPay, 0.18 ether);
        assertEq(clData.lastFeePaidAt, 0);
        vm.expectRevert(abi.encodeWithSelector(ICryptoLegacy.IncorrectFee.selector, buildFee - buildFee * refDiscountPct / 10000));
        cryptoLegacy.payInitialFee{value: 0}(_getEmptyUintList(), _getEmptyUintList());

        assertEq(feeRegistry.isNftLocked(dan), false);
        uint256 discount = lifetimeFee * refDiscountPct / 10000;
        uint256 share = lifetimeFee * refSharePct / 10000;
        buildManager.payInitialFee{value: lifetimeFee - discount}(customRefCode, dan, _getEmptyUintList(), _getEmptyUintList());
        assertEq(feeRegistry.isNftLocked(dan), true);
        assertEq(lifetimeNft.totalSupply(), 1);

        assertEq(aliceRecipient.balance, share);
        assertEq(address(feeRegistry).balance, lifetimeFee - discount - share);

        vm.expectRevert(ICryptoLegacy.NoValueAllowed.selector);
        cryptoLegacy.payInitialFee{value: lifetimeFee - discount}(_getEmptyUintList(), _getEmptyUintList());

        cryptoLegacy.payInitialFee{value: 0}(_getEmptyUintList(), _getEmptyUintList());
        clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        assertEq(clData.lastFeePaidAt, block.timestamp);
    }

    function testNftReentrancyAttack() public {
        _setPlugins();
        (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);
        NftLegacyPlugin nftLegacy = NftLegacyPlugin(address(cryptoLegacy));

        // Deploy a malicious ERC721 token that re-enters the contract during transfer
        MockMaliciousERC721 maliciousNft = new MockMaliciousERC721(address(cryptoLegacy));
        maliciousNft.transferFrom(address(this), treasury, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        vm.prank(bob);
        nftLegacy.setNftBeneficiary(keccak256(abi.encode(bobBeneficiary1)), address(maliciousNft), tokenIds, 0);

        vm.startPrank(treasury);
        maliciousNft.approve(address(cryptoLegacy), 1);
        vm.stopPrank();

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        vm.warp(block.timestamp + clData.updateInterval + 1);

        vm.startPrank(bobBeneficiary1);
        cryptoLegacy.initiateChallenge();
        vm.warp(block.timestamp + clData.challengeTimeout + 1);

        address[] memory _treasuries = new address[](1);
        _treasuries[0] = treasury;
        address[] memory _tokens = new address[](1);
        _tokens[0] = address(maliciousNft);

        // Attempt to trigger reentrancy during NFT transfer
        vm.expectRevert();
        nftLegacy.transferNftTokensToLegacy(address(maliciousNft), tokenIds);
    }

    function testOverwriteNftBeneficiary() public {
        // 1. Create a referral code for testing (optional).
        vm.prank(alice);
        (bytes8 refCode, , ) = buildManager.createRef(aliceRecipient, _getRefChains(), _getRefChains());

        // 2. Register a plugin (e.g. lensPlugin) so we can build a CryptoLegacy.
        // We'll add only the lens plugin initially
        address[] memory plugins = _setPlugins();

        // 3. Prepare beneficiary arrays for building CryptoLegacy
        bytes32[] memory beneficiaryArr = new bytes32[](1);
        beneficiaryArr[0] = keccak256(abi.encode(bobBeneficiary1)); // first beneficiary
        ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr = new ICryptoLegacy.BeneficiaryConfig[](1);
        beneficiaryConfigArr[0] = ICryptoLegacy.BeneficiaryConfig({claimDelay: 10, vestingPeriod: 100, shareBps: 10000});

        // 4. Build the CryptoLegacy for 'bob'
        buildRoll();
        vm.startPrank(bob);
        ICryptoLegacyBuildManager.BuildArgs memory buildArgs = ICryptoLegacyBuildManager.BuildArgs(refCode, beneficiaryArr, beneficiaryConfigArr, plugins, updateInterval, challengeTimeout);
        address payable cl = buildManager.buildCryptoLegacy{value: 0.18 ether}(buildArgs, _getRefArgsStruct(bob), _getCreate2ArgsStruct(address(0), 0));
        CryptoLegacyBasePlugin cryptoLegacy = CryptoLegacyBasePlugin(cl);
        ICryptoLegacyLens cryptoLegacyLens = ICryptoLegacyLens(cl);
        NftLegacyPlugin nftLegacy = NftLegacyPlugin(cl);

        // 5. Deploy a MockERC721 and move some tokens into 'treasury'
        //    (similar to your existing approach).
        vm.startPrank(owner);
        MockERC721 nft = new MockERC721();
        nft.transferFrom(owner, treasury, 1);
        vm.stopPrank();

        // 6. Set the NFT beneficiary for token #1 to 'bobBeneficiary1'
        vm.startPrank(bob);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        nftLegacy.setNftBeneficiary(
            addressToHash(bobBeneficiary1),
            address(nft),
            tokenIds,
            0 // claimDelay override for the NFT
        );

        // 7. Overwrite the same token #1 to a new beneficiary 'bobBeneficiary2'
        nftLegacy.setNftBeneficiary(
            addressToHash(bobBeneficiary2),
            address(nft),
            tokenIds,
            20 // new delay
        );

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        // 8. Simulate passing time so we can do an update
        vm.warp(block.timestamp + clData.updateInterval);
        cryptoLegacy.update{value: 0.09 ether}(_getEmptyUintList(), _getEmptyUintList());
        vm.stopPrank();

        // 9. Treasury approves the legacy to pull NFTs
        vm.prank(treasury);
        nft.approve(cl, 1);

        clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        // 10. Start the challenge from bobBeneficiary1 => distribution set
        vm.warp(block.timestamp + clData.updateInterval + 1);
        vm.prank(bobBeneficiary1);
        cryptoLegacy.initiateChallenge();
        clData = cryptoLegacyLens.getCryptoLegacyBaseData();
        uint256 distStart = block.timestamp + clData.challengeTimeout;
        assertEq(clData.distributionStartAt, distStart);

        // 11. Wait until distribution is active
        vm.warp(distStart + 1);

        // 12. Transfer token #1 from treasury into the legacy contract
        vm.prank(bobBeneficiary2);
        nftLegacy.transferNftTokensToLegacy(address(nft), tokenIds);
        // Now the contract owns #1
        assertEq(nft.ownerOf(1), address(cryptoLegacy));

        // 13. Try to claim from bobBeneficiary1 => should revert
        vm.prank(bobBeneficiary1);
        vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);

        // 14. bobBeneficiary2 must still respect the new claimDelay=20
        vm.startPrank(bobBeneficiary2);
        vm.expectRevert(ICryptoLegacy.DistributionDelay.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);

        // 15. Warp beyond that 20-second delay
        vm.warp(block.timestamp + 21);

        // Now bobBeneficiary2 can successfully claim
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);
        assertEq(nft.ownerOf(1), bobBeneficiary2);
        vm.stopPrank();
    }

    function testDoubleClaim() public {
        _setPlugins();
        // 1. Build a legacy with NftLegacyPlugin
        (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);
        NftLegacyPlugin nftLegacy = NftLegacyPlugin(address(cryptoLegacy));

        // 2. Deploy an NFT, pay initial fee, add plugin
        vm.startPrank(owner);
        MockERC721 nft = new MockERC721();
        nft.transferFrom(owner, treasury, 1);
        vm.stopPrank();

        // 3. Set beneficiary => bobBeneficiary1
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.prank(bob);
        nftLegacy.setNftBeneficiary(keccak256(abi.encode(bobBeneficiary1)), address(nft), tokenIds, 0);

        // 4. Transfer token #1 from test contract -> treasury for approval
        vm.prank(treasury);
        nft.approve(address(cryptoLegacy), 1);

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        // 5. Start distribution
        vm.warp(block.timestamp + clData.updateInterval + 1);
        vm.prank(bobBeneficiary1);
        cryptoLegacy.initiateChallenge();
        vm.warp(block.timestamp + clData.challengeTimeout + 1);

        // 6. bobBeneficiary1 calls transferNftTokensToLegacy => now contract owns #1
        vm.startPrank(bobBeneficiary1);
        nftLegacy.transferNftTokensToLegacy(address(nft), tokenIds);
        assertEq(nft.ownerOf(1), address(cryptoLegacy));

        // 7. First claim => success
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);
        assertEq(nft.ownerOf(1), bobBeneficiary1);

        // 8. Double claim => revert because the contract no longer owns #1
        vm.expectRevert(); // e.g. "ERC721: transfer from incorrect owner"
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);
        vm.stopPrank();
    }

    function testWrongBeneficiaryClaim() public {
        _setPlugins();
        // 1. Build a legacy with NftLegacyPlugin
        (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);
        NftLegacyPlugin nftLegacy = NftLegacyPlugin(address(cryptoLegacy));

        // 2. Deploy NFT, set beneficiary => bobBeneficiary1
        vm.startPrank(owner);
        MockERC721 nft = new MockERC721();
        nft.transferFrom(owner, treasury, 1);
        vm.stopPrank();

        vm.prank(bob);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        nftLegacy.setNftBeneficiary(
            keccak256(abi.encode(bobBeneficiary1)),
            address(nft),
            tokenIds,
            0
        );

        // 3. Approve contract
        vm.startPrank(treasury);
        nft.approve(address(cryptoLegacy), 1);
        vm.stopPrank();

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        // 4. Start distribution
        vm.warp(block.timestamp + clData.updateInterval + 1);
        vm.prank(bobBeneficiary1);
        cryptoLegacy.initiateChallenge();
        vm.warp(block.timestamp + clData.challengeTimeout + 1);

        // 5. Transfer NFT to the contract
        vm.startPrank(bobBeneficiary1);
        nftLegacy.transferNftTokensToLegacy(address(nft), tokenIds);
        assertEq(nft.ownerOf(1), address(cryptoLegacy));
        vm.stopPrank();

        // 6. Another user tries to claim => revert with "SENDER_IS_NOT_BENEFICIARY"
        vm.startPrank(bobBeneficiary2);
        vm.expectRevert(ICryptoLegacy.NotTheBeneficiary.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);
        vm.stopPrank();
    }

    function testClaimNftBeforeClaimDelay() public {
        _setPlugins();
        // 1. Build a legacy with NftLegacyPlugin
        (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);
        NftLegacyPlugin nftLegacy = NftLegacyPlugin(address(cryptoLegacy));

        // 2. Deploy NFT, set beneficiary => claimDelay=50
        vm.startPrank(owner);
        MockERC721 nft = new MockERC721();
        nft.transferFrom(owner, treasury, 42);
        vm.stopPrank();

        vm.prank(bob);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 42;
        nftLegacy.setNftBeneficiary(
            keccak256(abi.encode(bobBeneficiary1)),
            address(nft),
            tokenIds,
            50 // claimDelay
        );

        // 3. Approve contract
        vm.startPrank(treasury);
        nft.approve(address(cryptoLegacy), 42);
        vm.stopPrank();

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        // 4. Start distribution
        vm.warp(block.timestamp + clData.updateInterval + 1);
        vm.prank(bobBeneficiary1);
        cryptoLegacy.initiateChallenge();
        uint256 distStart = block.timestamp + clData.challengeTimeout;
        vm.warp(distStart + 1);

        // 5. Transfer NFT to the contract
        vm.prank(bobBeneficiary1);
        nftLegacy.transferNftTokensToLegacy(address(nft), tokenIds);
        assertEq(nft.ownerOf(42), address(cryptoLegacy));

        // 6. Try claiming before distributionStart + claimDelay => revert
        vm.startPrank(bobBeneficiary1);
        vm.expectRevert(ICryptoLegacy.DistributionDelay.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);

        // 7. Warp < 50 seconds => still revert
        vm.warp(block.timestamp + 25);
        vm.expectRevert(ICryptoLegacy.DistributionDelay.selector);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);
        vm.stopPrank();

        // 8. Warp enough to pass claimDelay
        vm.warp(block.timestamp + 26);
        vm.startPrank(bobBeneficiary1);
        nftLegacy.beneficiaryClaimNft(address(nft), tokenIds);
        assertEq(nft.ownerOf(42), bobBeneficiary1);
        vm.stopPrank();
    }

    function testSetNftBeneficiaryAfterDistributionStart() public {
        _setPlugins();
        // 1. Build a legacy with NftLegacyPlugin
        (CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, , ) = _buildCryptoLegacy(bob, buildFee, 0x0);
        NftLegacyPlugin nftLegacy = NftLegacyPlugin(address(cryptoLegacy));

        // 2. Deploy NFT, pay initial fee, add plugin
        vm.startPrank(owner);
        MockERC721 nft = new MockERC721();
        nft.transferFrom(owner, treasury, 1);
        vm.stopPrank();

        ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

        // 3. Warp time => distribution
        vm.warp(block.timestamp + clData.updateInterval + 1);
        vm.prank(bobBeneficiary1);
        cryptoLegacy.initiateChallenge();
        vm.warp(block.timestamp + clData.challengeTimeout + 1);

        // 4. Attempt to setNftBeneficiary => revert with "DISTRIBUTION_STARTED"
        vm.prank(bob);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        vm.expectRevert(ICryptoLegacy.DistributionStarted.selector);
        nftLegacy.setNftBeneficiary(
            keccak256(abi.encode(bobBeneficiary1)),
            address(nft),
            tokenIds,
            0
        );
    }

    function testNftTier() public {
        vm.prank(owner);
        lifetimeNft.mockMint(owner, 1);
        lifetimeNft.mockMint(owner, 98);
        lifetimeNft.mockMint(owner, 99);
        lifetimeNft.mockMint(owner, 100);
        lifetimeNft.mockMint(owner, 298);
        lifetimeNft.mockMint(owner, 299);
        lifetimeNft.mockMint(owner, 300);
        lifetimeNft.mockMint(owner, 599);
        lifetimeNft.mockMint(owner, 600);
        lifetimeNft.mockMint(owner, 1000);

        _checkTokenTier(1, ILifetimeNft.Tier.Silicon);
        _checkTokenTier(98, ILifetimeNft.Tier.Silicon);
        _checkTokenTier(98, ILifetimeNft.Tier.Silicon);
        _checkTokenTier(99, ILifetimeNft.Tier.Silicon);
        _checkTokenTier(100, ILifetimeNft.Tier.Silicon);
        _checkTokenTier(198, ILifetimeNft.Tier.Gallium);
        _checkTokenTier(199, ILifetimeNft.Tier.Gallium);
        _checkTokenTier(300, ILifetimeNft.Tier.Gallium);
        _checkTokenTier(399, ILifetimeNft.Tier.Indium);
        _checkTokenTier(400, ILifetimeNft.Tier.Indium);
        _checkTokenTier(700, ILifetimeNft.Tier.Indium);
        _checkTokenTier(701, ILifetimeNft.Tier.Tantalum);
        _checkTokenTier(1000, ILifetimeNft.Tier.Tantalum);
        _checkTokenTier(1500, ILifetimeNft.Tier.Tantalum);
        _checkTokenTier(1501, ILifetimeNft.Tier.Based);
        _checkTokenTier(1601, ILifetimeNft.Tier.Based);
        _checkTokenTier(2000, ILifetimeNft.Tier.Based);
    }

    function testPayForMultipleLifetimeNft() public {
        assertEq(lifetimeNft.balanceOf(bob), 0);
        assertEq(lifetimeNft.balanceOf(alice), 0);

        vm.expectRevert("Ownable: caller is not the owner");
        buildManager.setSupplyLimit(5);

        vm.prank(owner);
        buildManager.setSupplyLimit(2);

        ICryptoLegacyBuildManager.LifetimeNftMint[] memory mintList = new ICryptoLegacyBuildManager.LifetimeNftMint[](2);
        mintList[0] = ICryptoLegacyBuildManager.LifetimeNftMint(bob, 2);
        mintList[1] = ICryptoLegacyBuildManager.LifetimeNftMint(alice, 3);

        vm.expectRevert(abi.encodeWithSelector(ICryptoLegacyBuildManager.BellowMinimumSupply.selector, 2));
        buildManager.payForMultipleLifetimeNft{value: 10 ether}(bytes8(0), mintList);

        assertEq(feeRegistry.isNftLocked(alice), false);
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), alice, _getEmptyUintList(), _getEmptyUintList());
        assertEq(lifetimeNft.totalSupply(), 1);
        assertEq(feeRegistry.isNftLocked(alice), true);

        vm.expectRevert(abi.encodeWithSelector(ICryptoLegacyBuildManager.BellowMinimumSupply.selector, 2));
        buildManager.payForMultipleLifetimeNft{value: 10 ether}(bytes8(0), mintList);

        assertEq(feeRegistry.isNftLocked(dan), false);
        buildManager.payInitialFee{value: lifetimeFee}(bytes8(0), dan, _getEmptyUintList(), _getEmptyUintList());
        assertEq(lifetimeNft.totalSupply(), 2);
        assertEq(feeRegistry.isNftLocked(dan), true);

        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, 2 ether));
        buildManager.payForMultipleLifetimeNft{value: 0}(bytes8(0), mintList);

        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, 2 ether));
        buildManager.payForMultipleLifetimeNft{value: 1}(bytes8(0), mintList);

        vm.expectRevert(abi.encodeWithSelector(ILockChainGate.IncorrectFee.selector, 8 ether));
        buildManager.payForMultipleLifetimeNft{value: 9 ether}(bytes8(0), mintList);

        buildManager.payForMultipleLifetimeNft{value: 10 ether}(bytes8(0), mintList);

        assertEq(lifetimeNft.balanceOf(bob), 2);
        assertEq(lifetimeNft.balanceOf(alice), 3);
        assertEq(lifetimeNft.totalSupply(), 7);
    }

    function _checkTokenTier(uint256 _tokenId, LifetimeNft.Tier _tier) internal view {
        assertEq(uint256(lifetimeNft.getTier(_tokenId)), uint256(_tier));
    }

    function _buildCryptoLegacy(address _prank, uint256 _fee, bytes8 _refCode) internal override returns(CryptoLegacyBasePlugin cryptoLegacy, ICryptoLegacyLens cryptoLegacyLens, bytes32[] memory beneficiaryArr, ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr) {
        return _buildCryptoLegacyWithPlugins(_prank, _fee, _refCode, _getBasePlugins());
    }

    function _getBasePlugins() internal view override returns(address[] memory plugins){
        plugins = new address[](3);
        plugins[0] = cryptoLegacyBasePlugin;
        plugins[1] = lensPlugin;
        plugins[2] = nftPlugin;
        return plugins;
    }

    function _setPlugins() internal returns(address[] memory plugins) {
        plugins = new address[](3);
        plugins[0] = cryptoLegacyBasePlugin;
        plugins[1] = lensPlugin;
        plugins[2] = nftPlugin;
        vm.startPrank(owner);
        pluginsRegistry.addPlugin(lensPlugin, "");
        pluginsRegistry.addPlugin(nftPlugin, "");
        vm.stopPrank();
    }
}
