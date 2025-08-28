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

contract UpdateRegistries is Script {
    bytes32 internal _salt =              bytes32(uint256(1));
    CryptoLegacyBuildManager internal _buildManager = CryptoLegacyBuildManager(payable(0xF056a682A6b68833356D340a149A5bA1e6B1b194));
    PluginsRegistry _pluginRegistry;
    BeneficiaryRegistry _beneficiaryRegistry;
    LegacyMessenger _legacyMessenger;

    function run() public virtual {
        _salt = bytes32(vm.envUint("SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address create3Factory = vm.envAddress("CREATE_3_FACTORY");
        Create3Factory factory = Create3Factory(create3Factory);
        _pluginRegistry = LibDeploy._deployPluginsRegistryAndSet(factory, _salt, msg.sender);
        _beneficiaryRegistry = LibDeploy._deployBeneficiaryRegistry(factory, _salt, msg.sender);
        _legacyMessenger = LibDeploy._deployLegacyMessenger(factory, _salt, msg.sender, _buildManager);

        vm.stopBroadcast();
    }
}