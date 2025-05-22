// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import "../contracts/mocks/MockERC20.sol";
import "../contracts/MultiPermit.sol";
import "./utils/SigUtils.sol";
import "forge-std/Test.sol";
import "./AbstractTestHelper.sol";

contract MockTestHelper is AbstractTestHelper {

}

contract MultiPermitTest is Test {
    MockERC20 internal token;
    SigUtils internal sigUtils;
    MultiPermit internal multiPermit;

    uint256 internal ownerPrivateKey;
    uint256 internal spenderPrivateKey;

    address internal owner;
    address internal spender;

    function setUp() public {

    }

    function test_setUp() public {
        MockTestHelper ath = new MockTestHelper();
        payable(address(ath)).transfer(70 ether);
        ath.setUp();
    }
}