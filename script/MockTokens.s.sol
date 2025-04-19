// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

contract MockTokensDeploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20 mockToken1 = new MockERC20("Mock", "MOCK");
        mockToken1.transfer(0xB6235Af114F0E7416e5c1314dE7f5Cde756156Fc, 100000 ether);

        vm.stopBroadcast();
    }
}