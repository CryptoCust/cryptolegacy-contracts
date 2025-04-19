// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "../contracts/mocks/MockERC20.sol";
import "../contracts/MultiPermit.sol";
import "./utils/SigUtils.sol";
import "forge-std/Test.sol";

contract MultiPermitTest is Test {
    MockERC20 internal token;
    SigUtils internal sigUtils;
    MultiPermit internal multiPermit;

    uint256 internal ownerPrivateKey;
    uint256 internal spenderPrivateKey;

    address internal owner;
    address internal spender;

    function setUp() public {
        token = new MockERC20("Mock", "MOCK");
        sigUtils = new SigUtils(token.DOMAIN_SEPARATOR());
        multiPermit = new MultiPermit();

        ownerPrivateKey = 0xA11CE;
        spenderPrivateKey = 0xB0B;

        owner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);

        token.mint(owner, 1e18);
    }

    ///                                                          ///
    ///                            PERMIT                        ///
    ///                                                          ///

    function test_Permit() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(
            permit.owner,
            permit.spender,
            permit.value,
            permit.deadline,
            v,
            r,
            s
        );

        assertEq(token.allowance(owner, spender), 1e18);
        assertEq(token.nonces(owner), 1);
    }

    function test_MultiPermit() public {
        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: spender,
            value: 1e18,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        MultiPermit.PermitData[] memory permits = new MultiPermit.PermitData[](1);
        permits[0] = MultiPermit.PermitData({
            token: address(token),
            owner: owner,
            spender: spender,
            value: 1e18,
            deadline: block.timestamp + 1 days,
            v: v,
            r: r,
            s: s
        });

        multiPermit.approveTreasuryTokensToLegacy(permits);

        assertEq(token.allowance(owner, spender), 1e18);
        assertEq(token.nonces(owner), 1);
    }
}