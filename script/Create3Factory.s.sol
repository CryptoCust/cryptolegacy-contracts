// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./LibDeploy.sol";
import "./LibMockDeploy.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "forge-std/console.sol";
import "forge-std/Script.sol";

contract Create3FactoryDeploy is Script {
    bytes32 internal salt =              bytes32(uint256(1));

    function run() external {
        salt = bytes32(vm.envUint("SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Create3Factory factory = LibDeploy._deployCreate3Factory(salt, msg.sender);
        vm.stopBroadcast();
    }
}