// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/mocks/MockERC20Ownable.sol";
import "forge-std/Script.sol";

contract MockTokensDeploy is Script {
    function run() external {
        bytes32 salt = bytes32(vm.envUint("SALT") + 700000);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockToken1 = new MockERC20Ownable{salt: salt}("Mock", "MOCK", msg.sender);
        mockToken1.totalSupply();
        mockToken1.mint(0xB6235Af114F0E7416e5c1314dE7f5Cde756156Fc, 100000 ether);

        vm.stopBroadcast();
    }
}