// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/SignatureRoleTimelock.sol";
import "../contracts/mocks/MockCallProxy.sol";
import "../contracts/mocks/MockDeBridgeGate.sol";
import "../contracts/mocks/MockNewFeeRegistry.sol";
import "./AbstractTestHelper.sol";

contract SignatureRoleTimelockTest is AbstractTestHelper {
    SignatureRoleTimelock internal srt;

    bytes32 constant ROLE_1 = keccak256(abi.encode("role-1"));
    bytes32 constant ROLE_2 = keccak256(abi.encode("role-2"));

    address payable constant internal msig1 = payable(0x2C4F8D00AF9fCac74D4F474A46ac9d614117BE83);
    address payable constant internal msig2 = payable(0x22228669Db4745cB3616236353dCAa92b28Cf515);
    address payable constant internal msig3 = payable(0x848447325EFc03C164f2Ad00215063BA1e531e3b);

    function setUp() public override {
        super.setUp();

    }

    function testSetMaxExecutionPeriod() public {
        ISignatureRoleTimelock.AddressRoleInput[] memory roles = new ISignatureRoleTimelock.AddressRoleInput[](0);
        ISignatureRoleTimelock.SignatureToAdd[] memory sigs = new ISignatureRoleTimelock.SignatureToAdd[](0);

        srt = new SignatureRoleTimelock(1 days, roles, sigs, owner);

        assertEq(srt.getRoleAccounts(srt.ADMIN_ROLE()).length, 1);
        assertEq(srt.getRoleAccounts(srt.ADMIN_ROLE())[0], owner);
        assertEq(srt.maxExecutionPeriod(), 14 days);

        vm.expectRevert(ISignatureRoleTimelock.CallerNotCurrentAddress.selector);
        srt.setMaxExecutionPeriod(10 days);

        vm.startPrank(address(srt));

        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.OutOfMaxExecutionPeriodBounds.selector, 7 days, 21 days));
        srt.setMaxExecutionPeriod(30 days);

        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.OutOfMaxExecutionPeriodBounds.selector, 7 days, 21 days));
        srt.setMaxExecutionPeriod(1 days);

        srt.setMaxExecutionPeriod(10 days);
        assertEq(srt.maxExecutionPeriod(), 10 days);

        vm.stopPrank();

        bytes memory addSignatureBytes = abi.encodeWithSelector(srt.setMaxExecutionPeriod.selector, 11 days);

        ISignatureRoleTimelock.CallToAdd[] memory calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(srt), addSignatureBytes);
        vm.prank(owner);
        bytes32[] memory callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + 1 days);

        srt.executeCallList(callIds);
        assertEq(srt.maxExecutionPeriod(), 11 days);
    }

    function testRoleSignaturesExecute() public {
        _addBasePluginsToRegistry();

        ISignatureRoleTimelock.AddressRoleInput[] memory roles = new ISignatureRoleTimelock.AddressRoleInput[](1);
        roles[0] = ISignatureRoleTimelock.AddressRoleInput(ROLE_1, alice, address(0));

        ISignatureRoleTimelock.SignatureToAdd[] memory sigs = new ISignatureRoleTimelock.SignatureToAdd[](1);
        sigs[0] = ISignatureRoleTimelock.SignatureToAdd(address(feeRegistry), feeRegistry.setDebridgeGate.selector, ROLE_1, 2 days);

        srt = new SignatureRoleTimelock(1 days, roles, sigs, owner);

        assertEq(srt.hasRole(ROLE_1, alice), true);
        assertEq(srt.getRoleAccounts(ROLE_1).length, 1);
        assertEq(srt.getRoleAccounts(ROLE_1)[0], alice);

        roles = new ISignatureRoleTimelock.AddressRoleInput[](3);
        roles[0] = ISignatureRoleTimelock.AddressRoleInput(ROLE_1, bob, address(0));
        roles[1] = ISignatureRoleTimelock.AddressRoleInput(ROLE_1, charlie, address(0));
        roles[2] = ISignatureRoleTimelock.AddressRoleInput(ROLE_2, dan, address(0));

        ISignatureRoleTimelock.TargetSigRes[] memory resSigs = srt.getTargetSigs(address(feeRegistry));
        assertEq(resSigs.length, 1);
        assertEq(resSigs[0].signature, feeRegistry.setDebridgeGate.selector);
        assertEq(resSigs[0].role, ROLE_1);
        assertEq(resSigs[0].timelock, 2 days);

        address[] memory targets = srt.getTargets();
        assertEq(targets.length, 2);
        assertEq(targets[0], address(srt));
        assertEq(targets[1], address(feeRegistry));

        (bytes32 role, uint128 timelock) = srt.signatureRoles(address(feeRegistry), feeRegistry.setDebridgeGate.selector);
        assertEq(timelock, 2 days);

        assertEq(srt.hasRole(ROLE_1, bob), false);
        assertEq(srt.hasRole(ROLE_2, dan), false);

        (role, timelock) = srt.signatureRoles(address(feeRegistry), feeRegistry.setDebridgeNativeFee.selector);
        assertEq(timelock, 0);

        vm.stopPrank();

        sigs = new ISignatureRoleTimelock.SignatureToAdd[](1);
        sigs[0] = ISignatureRoleTimelock.SignatureToAdd(address(feeRegistry), feeRegistry.setDebridgeNativeFee.selector, ROLE_2, 3 days);
        vm.prank(address(srt));
        vm.expectRevert(ISignatureRoleTimelock.RoleDontExist.selector);
        srt.addSignatureRoleList(sigs);

        vm.startPrank(address(srt));
        srt.setRoleAccounts(roles);

        vm.expectRevert(ISignatureRoleTimelock.AlreadyHaveRole.selector);
        srt.setRoleAccounts(roles);

        assertEq(srt.getRoleAccounts(ROLE_1).length, 3);
        assertEq(srt.getRoleAccounts(ROLE_2).length, 1);
        assertEq(srt.getRoleAccounts(ROLE_1)[1], bob);
        assertEq(srt.getRoleAccounts(ROLE_1)[2], charlie);
        assertEq(srt.getRoleAccounts(ROLE_2)[0], dan);
        assertEq(srt.hasRole(ROLE_1, alice), true);
        assertEq(srt.hasRole(ROLE_1, bob), true);
        assertEq(srt.hasRole(ROLE_2, dan), true);

        vm.stopPrank();

        vm.prank(owner);
        feeRegistry.transferOwnership(address(srt));

        vm.startPrank(owner);
        vm.expectRevert(ISignatureRoleTimelock.CallerNotCurrentAddress.selector);
        srt.addSignatureRoleList(sigs);

        bytes memory addSignatureBytes = abi.encodeWithSelector(srt.addSignatureRoleList.selector, sigs);

        ISignatureRoleTimelock.CallToAdd[] memory calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(srt), addSignatureBytes);
        bytes32[] memory callIds = srt.scheduleCallList(calls);
        vm.stopPrank();

        (role, timelock) = srt.signatureRoles(address(feeRegistry), feeRegistry.setDebridgeNativeFee.selector);
        assertEq(timelock, 0 days);

        bytes memory setDebridgeGateBytes = abi.encodeWithSelector(feeRegistry.setDebridgeNativeFee.selector, 0);
        ISignatureRoleTimelock.CallToAdd[] memory feeRegistryCalls = new ISignatureRoleTimelock.CallToAdd[](1);
        feeRegistryCalls[0] = ISignatureRoleTimelock.CallToAdd(address(feeRegistry), setDebridgeGateBytes);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.SignatureTimeLockNotSet.selector, feeRegistry.setDebridgeNativeFee.selector));
        srt.scheduleCallList(feeRegistryCalls);

        resSigs = srt.getTargetSigs(address(feeRegistry));
        assertEq(resSigs.length, 1);
        assertEq(resSigs[0].signature, feeRegistry.setDebridgeGate.selector);
        assertEq(resSigs[0].role, ROLE_1);
        assertEq(resSigs[0].timelock, 2 days);

        targets = srt.getTargets();
        assertEq(targets.length, 2);
        assertEq(targets[0], address(srt));
        assertEq(targets[1], address(feeRegistry));

        vm.warp(block.timestamp + 1 days);
        srt.executeCallList(callIds);

        vm.prank(address(srt));
        vm.expectRevert(ISignatureRoleTimelock.SignatureAlreadyExists.selector);
        srt.addSignatureRoleList(sigs);

        resSigs = srt.getTargetSigs(address(feeRegistry));
        assertEq(resSigs.length, 2);
        assertEq(resSigs[0].signature, feeRegistry.setDebridgeGate.selector);
        assertEq(resSigs[0].role, ROLE_1);
        assertEq(resSigs[0].timelock, 2 days);
        assertEq(resSigs[1].signature, feeRegistry.setDebridgeNativeFee.selector);
        assertEq(resSigs[1].role, ROLE_2);
        assertEq(resSigs[1].timelock, 3 days);

        targets = srt.getTargets();
        assertEq(targets.length, 2);
        assertEq(targets[0], address(srt));
        assertEq(targets[1], address(feeRegistry));

        (role, timelock) = srt.signatureRoles(address(feeRegistry), feeRegistry.setDebridgeGate.selector);
        assertEq(timelock, 2 days);
        assertEq(role, ROLE_1);

        (role, timelock) = srt.signatureRoles(address(feeRegistry), feeRegistry.setDebridgeNativeFee.selector);
        assertEq(timelock, 3 days);
        assertEq(role, ROLE_2);

        setDebridgeGateBytes = abi.encodeWithSelector(feeRegistry.setDebridgeGate.selector, address(1));
        feeRegistryCalls = new ISignatureRoleTimelock.CallToAdd[](1);
        feeRegistryCalls[0] = ISignatureRoleTimelock.CallToAdd(address(feeRegistry), setDebridgeGateBytes);

        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, ROLE_1));
        srt.scheduleCallList(feeRegistryCalls);

        vm.prank(alice);
        callIds = srt.scheduleCallList(feeRegistryCalls);

        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(ISignatureRoleTimelock.TimelockActive.selector);
        srt.executeCallList(callIds);

        vm.warp(block.timestamp + 15 days + 1);

        vm.expectRevert(ISignatureRoleTimelock.TimelockExpired.selector);
        srt.executeCallList(callIds);

        vm.prank(alice);
        callIds = srt.scheduleCallList(feeRegistryCalls);

        vm.warp(block.timestamp + 2 days + 1);

        assertEq(address(feeRegistry.deBridgeGate()), address(0));

        vm.warp(block.timestamp + 1 days + 1);
        srt.executeCallList(callIds);

        vm.expectRevert(ISignatureRoleTimelock.NotPending.selector);
        srt.executeCallList(callIds);

        callIds[0] = bytes32(0);
        vm.expectRevert(ISignatureRoleTimelock.CallNotScheduled.selector);
        srt.executeCallList(callIds);

        vm.prank(alice);
        callIds = srt.scheduleCallList(feeRegistryCalls);

        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, srt.ADMIN_ROLE()));
        srt.cancelCallList(callIds);

        assertEq(srt.getCall(callIds[0]).pending, true);
        vm.prank(owner);
        srt.cancelCallList(callIds);
        assertEq(srt.getCall(callIds[0]).pending, false);

        vm.expectRevert(ISignatureRoleTimelock.NotPending.selector);
        vm.prank(owner);
        srt.cancelCallList(callIds);

        vm.warp(block.timestamp + 3 days + 1);
        vm.expectRevert(ISignatureRoleTimelock.NotPending.selector);
        srt.executeCallList(callIds);

        {
            bytes32[] memory allCallIds = srt.getCallIds();
            assertEq(allCallIds[allCallIds.length - 1], callIds[0]);
            assertEq(allCallIds.length, 4);
            assertEq(srt.getCallsLength(), 4);

            (bytes32[] memory resIds, ISignatureRoleTimelock.CallRequest[] memory resCalls) = srt.getCallsList(0, 2);
            assertEq(resIds.length, 2);
            assertEq(resCalls.length, 2);
            assertEq(resIds[0], allCallIds[0]);
            assertEq(resCalls[0].executeAfter, srt.getCall(allCallIds[0]).executeAfter);
            assertEq(resIds[1], allCallIds[1]);
            assertEq(resCalls[1].executeAfter, srt.getCall(allCallIds[1]).executeAfter);

            (resIds, resCalls) = srt.getCallsList(2, 2);
            assertEq(resIds.length, 2);
            assertEq(resCalls.length, 2);
            assertEq(resIds[0], allCallIds[2]);
            assertEq(resCalls[0].executeAfter, srt.getCall(allCallIds[2]).executeAfter);
            assertEq(resIds[1], allCallIds[3]);
            assertEq(resCalls[1].executeAfter, srt.getCall(allCallIds[3]).executeAfter);

            (resIds, resCalls) = srt.getCallsList(0, 4);
            assertEq(resIds.length, 4);
            assertEq(resCalls.length, 4);
            assertEq(resIds[0], allCallIds[0]);
            assertEq(resCalls[0].executeAfter, srt.getCall(allCallIds[0]).executeAfter);
            assertEq(resIds[1], allCallIds[1]);
            assertEq(resCalls[1].executeAfter, srt.getCall(allCallIds[1]).executeAfter);
            assertEq(resIds[2], allCallIds[2]);
            assertEq(resCalls[2].executeAfter, srt.getCall(allCallIds[2]).executeAfter);
            assertEq(resIds[3], allCallIds[3]);
            assertEq(resCalls[3].executeAfter, srt.getCall(allCallIds[3]).executeAfter);
        }

        callIds[0] = bytes32(0);
        vm.expectRevert(ISignatureRoleTimelock.CallNotScheduled.selector);
        vm.prank(owner);
        srt.cancelCallList(callIds);

        assertEq(address(feeRegistry.deBridgeGate()), address(1));

        roles = new ISignatureRoleTimelock.AddressRoleInput[](1);
        roles[0] = ISignatureRoleTimelock.AddressRoleInput(ROLE_1, address(0), alice);

        assertEq(srt.hasRole(ROLE_1, alice), true);
        assertEq(srt.hasRole(ROLE_1, bob), true);
        assertEq(srt.hasRole(ROLE_2, dan), true);

        vm.expectRevert(ISignatureRoleTimelock.CallerNotCurrentAddress.selector);
        srt.setRoleAccounts(roles);

        vm.prank(address(srt));
        srt.setRoleAccounts(roles);

        vm.prank(address(srt));
        vm.expectRevert(ISignatureRoleTimelock.DoesntHaveRole.selector);
        srt.setRoleAccounts(roles);

        assertEq(srt.getRoleAccounts(ROLE_1).length, 2);
        assertEq(srt.getRoleAccounts(ROLE_1)[0], charlie);
        assertEq(srt.getRoleAccounts(ROLE_1)[1], bob);
        assertEq(srt.getRoleAccounts(ROLE_2).length, 1);
        assertEq(srt.hasRole(ROLE_1, alice), false);
        assertEq(srt.hasRole(ROLE_1, bob), true);
        assertEq(srt.hasRole(ROLE_1, charlie), true);
        assertEq(srt.hasRole(ROLE_2, dan), true);

        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, ROLE_1));
        vm.prank(alice);
        srt.scheduleCallList(feeRegistryCalls);

        roles = new ISignatureRoleTimelock.AddressRoleInput[](2);
        roles[0] = ISignatureRoleTimelock.AddressRoleInput(ROLE_1, address(0), bob);
        roles[1] = ISignatureRoleTimelock.AddressRoleInput(ROLE_1, address(0), charlie);

        assertEq(srt.hasRole(ROLE_1, bob), true);
        assertEq(srt.hasRole(ROLE_2, dan), true);

        vm.prank(address(srt));
        srt.setRoleAccounts(roles);

        assertEq(srt.getRoleAccounts(ROLE_1).length, 0);
        assertEq(srt.getRoleAccounts(ROLE_2).length, 1);
        assertEq(srt.hasRole(ROLE_1, bob), false);
        assertEq(srt.hasRole(ROLE_1, charlie), false);
        assertEq(srt.hasRole(ROLE_2, dan), true);

        ISignatureRoleTimelock.SignatureToRemove[] memory sigsToRemove = new ISignatureRoleTimelock.SignatureToRemove[](1);
        sigsToRemove[0] = ISignatureRoleTimelock.SignatureToRemove(address(feeRegistry), feeRegistry.setDebridgeGate.selector);

        _removeSignatures(owner, sigsToRemove, 1 days);

        resSigs = srt.getTargetSigs(address(feeRegistry));
        assertEq(resSigs.length, 1);
        assertEq(resSigs[0].signature, feeRegistry.setDebridgeNativeFee.selector);
        assertEq(resSigs[0].role, ROLE_2);
        assertEq(resSigs[0].timelock, 3 days);

        targets = srt.getTargets();
        assertEq(targets.length, 2);
        assertEq(targets[0], address(srt));
        assertEq(targets[1], address(feeRegistry));

        sigsToRemove[0] = ISignatureRoleTimelock.SignatureToRemove(address(feeRegistry), feeRegistry.setDebridgeNativeFee.selector);

        _removeSignatures(owner, sigsToRemove, 1 days);

        resSigs = srt.getTargetSigs(address(feeRegistry));
        assertEq(resSigs.length, 0);

        targets = srt.getTargets();
        assertEq(targets.length, 1);
        assertEq(targets[0], address(srt));

        assertEq(srt.hasRole(ROLE_2, dan), true);
        assertEq(srt.hasRole(ROLE_2, alice), false);
        roles = new ISignatureRoleTimelock.AddressRoleInput[](1);
        roles[0] = ISignatureRoleTimelock.AddressRoleInput(ROLE_2, alice, dan);
        vm.prank(address(srt));
        srt.setRoleAccounts(roles);
        assertEq(srt.hasRole(ROLE_2, dan), false);
        assertEq(srt.hasRole(ROLE_2, alice), true);
    }

    function _removeSignatures(address _sender, ISignatureRoleTimelock.SignatureToRemove[] memory _sigs, uint256 _timelock) internal {
        bytes memory removeSignatureBytes = abi.encodeWithSelector(srt.removeSignatureRoleList.selector, _sigs);

        ISignatureRoleTimelock.CallToAdd[] memory calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(srt), removeSignatureBytes);
        vm.prank(_sender);
        bytes32[] memory callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + _timelock);
        srt.executeCallList(callIds);
    }

    function testSignatureRoleTimelockProductionDeploy() public {
        vm.startPrank(owner);

        LegacyMessenger lm = new LegacyMessenger(owner);
        srt = LibDeploy._deploySignatureRoleTimelock(salt, buildManager, proxyBuilder, lm, msig1, msig2, msig3);
        LibDeploy._transferOwnershipWithLm(address(srt), buildManager, proxyBuilder, lm);

        vm.stopPrank();

        address sigTimelock = address(srt);
        _checkOwner(address(buildManager.feeRegistry()), sigTimelock);
        _checkOwner(address(buildManager.pluginsRegistry()), sigTimelock);
        _checkOwner(address(buildManager.beneficiaryRegistry()), sigTimelock);
        _checkOwner(address(buildManager.lifetimeNft()), sigTimelock);
        _checkOwner(address(buildManager.factory()), sigTimelock);
        _checkOwner(address(buildManager), sigTimelock);
        _checkOwner(address(lm), sigTimelock);
        _checkOwner(address(proxyBuilder), sigTimelock);
        _checkOwner(address(proxyBuilder.proxyAdmin()), sigTimelock);

        CryptoLegacyExternalLens newExternalLens = new CryptoLegacyExternalLens();
        bytes memory setExternalBytes = abi.encodeWithSelector(buildManager.setExternalLens.selector, address(newExternalLens));

        ISignatureRoleTimelock.CallToAdd[] memory calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(buildManager), setExternalBytes);

        vm.prank(msig1);
        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, LibDeploy._getMsig2Role()));
        bytes32[] memory callIds = srt.scheduleCallList(calls);

        vm.prank(msig2);
        callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + LibDeploy._getDefaultTimelock() / 2);

        vm.expectRevert(ISignatureRoleTimelock.TimelockActive.selector);
        srt.executeCallList(callIds);

        assertNotEq(address(buildManager.externalLens()), address(newExternalLens));
        vm.warp(block.timestamp + LibDeploy._getDefaultTimelock() / 2 + 1);
        srt.executeCallList(callIds);
        assertEq(address(buildManager.externalLens()), address(newExternalLens));

        ISignatureRoleTimelock.AddressRoleInput[] memory roles = new ISignatureRoleTimelock.AddressRoleInput[](1);
        roles[0] = ISignatureRoleTimelock.AddressRoleInput(LibDeploy._getMsig3Role(), charlie, address(0));

        bytes memory setRolesBytes = abi.encodeWithSelector(srt.setRoleAccounts.selector, roles);

        calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(srt), setRolesBytes);

        vm.prank(msig2);
        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, srt.ADMIN_ROLE()));
        callIds = srt.scheduleCallList(calls);

        vm.prank(msig1);
        callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + 5 days);

        assertEq(srt.hasRole(LibDeploy._getMsig3Role(), charlie), false);
        srt.executeCallList(callIds);
        assertEq(srt.hasRole(LibDeploy._getMsig3Role(), charlie), true);
    }

    function testSignatureRoleTimelockProductionUpgradeFeeRegistry() public {
        vm.startPrank(owner);

        LegacyMessenger lm = new LegacyMessenger(owner);
        srt = LibDeploy._deploySignatureRoleTimelock(salt, buildManager, proxyBuilder, lm, msig1, msig2, msig3);
        LibDeploy._transferOwnershipWithLm(address(srt), buildManager, proxyBuilder, lm);

        vm.stopPrank();

        MockNewFeeRegistry newFeeRegistry = new MockNewFeeRegistry();

        ProxyAdmin pAdmin = proxyBuilder.proxyAdmin();
        bytes memory upgradeBytes = abi.encodeWithSelector(pAdmin.upgrade.selector, address(feeRegistry), address(newFeeRegistry));

        ISignatureRoleTimelock.CallToAdd[] memory calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(pAdmin), upgradeBytes);

        vm.prank(msig2);
        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.CallerHaveNoRequiredRole.selector, LibDeploy._getMsig3Role()));
        bytes32[] memory callIds = srt.scheduleCallList(calls);

        vm.prank(msig3);
        callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + LibDeploy._getDefaultTimelock() + 1);

        MockNewFeeRegistry upgradedFeeRegistry = MockNewFeeRegistry(address(feeRegistry));

        vm.prank(address(srt));
        feeRegistry.setCustomChainId(100);

        vm.expectRevert();
        upgradedFeeRegistry.clearCustomChainId();

        srt.executeCallList(callIds);

        vm.expectRevert("Ownable: caller is not the owner");
        upgradedFeeRegistry.clearCustomChainId();

        bytes memory clearCustomChainIdBytes = abi.encodeWithSelector(upgradedFeeRegistry.clearCustomChainId.selector);
        ISignatureRoleTimelock.CallToAdd[] memory callsToClearCustomChain = new ISignatureRoleTimelock.CallToAdd[](1);
        callsToClearCustomChain[0] = ISignatureRoleTimelock.CallToAdd(address(feeRegistry), clearCustomChainIdBytes);

        vm.expectRevert(abi.encodeWithSelector(ISignatureRoleTimelock.SignatureTimeLockNotSet.selector, upgradedFeeRegistry.clearCustomChainId.selector));
        vm.prank(msig2);
        callIds = srt.scheduleCallList(callsToClearCustomChain);

        ISignatureRoleTimelock.SignatureToAdd[] memory sigs = new ISignatureRoleTimelock.SignatureToAdd[](1);
        sigs[0] = ISignatureRoleTimelock.SignatureToAdd(address(feeRegistry), upgradedFeeRegistry.clearCustomChainId.selector, LibDeploy._getMsig2Role(), LibDeploy._getDefaultTimelock());

        bytes memory addSignatureBytes = abi.encodeWithSelector(srt.addSignatureRoleList.selector, sigs);
        calls = new ISignatureRoleTimelock.CallToAdd[](1);
        calls[0] = ISignatureRoleTimelock.CallToAdd(address(srt), addSignatureBytes);

        vm.prank(msig1);
        callIds = srt.scheduleCallList(calls);

        vm.warp(block.timestamp + 5 days);

        srt.executeCallList(callIds);

        vm.prank(msig2);
        callIds = srt.scheduleCallList(callsToClearCustomChain);

        vm.warp(block.timestamp + LibDeploy._getDefaultTimelock() + 1);

        assertEq(upgradedFeeRegistry.getChainId(), 100);

        srt.executeCallList(callIds);

        assertEq(upgradedFeeRegistry.getChainId(), 31337);

        address[] memory targets = srt.getTargets();
        assertEq(targets.length, 9);
        assertEq(targets[0], address(srt));
        assertEq(targets[1], address(beneficiaryRegistry));
        assertEq(targets[2], address(lm));
        assertEq(targets[3], address(buildManager));
        assertEq(targets[4], address(factory));
        assertEq(targets[5], address(feeRegistry));
        assertEq(targets[6], address(lifetimeNft));
        assertEq(targets[7], address(pluginsRegistry));
        assertEq(targets[8], address(proxyBuilder.proxyAdmin()));

        ISignatureRoleTimelock.TargetSigRes[] memory resSigs = srt.getTargetSigs(address(lm));
        assertEq(resSigs.length, 1);
        assertEq(resSigs[0].signature, lm.setBuildManager.selector);
        assertEq(resSigs[0].role, LibDeploy._getMsig3Role());
        assertEq(resSigs[0].timelock, 5 days);

        ISignatureRoleTimelock.SignatureToRemove[] memory sigsToRemove = new ISignatureRoleTimelock.SignatureToRemove[](1);
        sigsToRemove[0] = ISignatureRoleTimelock.SignatureToRemove(address(lm), lm.setBuildManager.selector);

        _removeSignatures(msig1, sigsToRemove, 5 days);

        resSigs = srt.getTargetSigs(address(lm));
        assertEq(resSigs.length, 0);

        targets = srt.getTargets();
        assertEq(targets.length, 8);
        assertEq(targets[0], address(srt));
        assertEq(targets[1], address(beneficiaryRegistry));
        assertEq(targets[2], address(proxyBuilder.proxyAdmin()));
        assertEq(targets[3], address(buildManager));
        assertEq(targets[4], address(factory));
        assertEq(targets[5], address(feeRegistry));
        assertEq(targets[6], address(lifetimeNft));
        assertEq(targets[7], address(pluginsRegistry));
    }

    function _checkOwner(address _contract, address _owner) internal view {
        assertEq(Ownable(_contract).owner(), _owner);
    }
}