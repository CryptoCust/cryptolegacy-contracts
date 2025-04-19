// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/plugins/CryptoLegacyBasePlugin.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/PluginsRegistry.sol";
import "forge-std/Script.sol";
import "./LibDeploy.sol";
import "./LibMockDeploy.sol";

contract UpgradeMockCryptoLegacyFactory is Script {
    bytes32 internal salt = bytes32(uint256(1));

    function run() external {
        salt = bytes32(vm.envUint("SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address oldBuildManagerAddress = vm.envAddress("OLD_BUILD_MANAGER");
        address legacyMessengerAddress = vm.envAddress("LEGACY_MESSENGER");
        address proxyBuilderAddress = vm.envAddress("PROXY_BUILDER");

        CryptoLegacyBuildManager oldBuildManager = CryptoLegacyBuildManager(payable(oldBuildManagerAddress));
        FeeRegistry feeRegistry = FeeRegistry(address(oldBuildManager.feeRegistry()));
        LifetimeNft lifetimeNft = LifetimeNft(address(oldBuildManager.lifetimeNft()));
        LegacyMessenger legacyMessenger = LegacyMessenger(legacyMessengerAddress);
        ProxyBuilder proxyBuilder = ProxyBuilder(proxyBuilderAddress);

        PluginsRegistry pluginRegistry = LibDeploy._deployPluginsRegistryAndSet(salt, msg.sender);

        (CryptoLegacyBuildManager buildManager, , ) = LibMockDeploy._deployMockBuildManager(salt, msg.sender, feeRegistry, pluginRegistry, lifetimeNft);

        LibDeploy._initFeeRegistry(feeRegistry, buildManager, 0.00003 ether, 0.00002 ether, 0.00001 ether, 1000, 2000);
        LibDeploy._initLegacyMessenger(legacyMessenger, buildManager);
        LibDeploy._upgradeFeeRegistry(salt, feeRegistry, proxyBuilder);
        LibDeploy._deployExternalLens(salt, buildManager);

        LibDeploy._deployZeroCryptoLegacy(salt);

        vm.stopBroadcast();
    }
}