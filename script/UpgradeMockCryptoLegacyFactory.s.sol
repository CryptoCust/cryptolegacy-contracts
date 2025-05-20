// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./LibDeploy.sol";
import "./LibMockDeploy.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/plugins/CryptoLegacyBasePlugin.sol";
import "forge-std/Script.sol";

contract UpgradeMockCryptoLegacyFactory is Script {
    bytes32 internal salt = bytes32(uint256(1));

    function run() external {
        salt = bytes32(vm.envUint("SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address create3FactoryAddress = vm.envAddress("CREATE3_FACTORY");
        address oldBuildManagerAddress = vm.envAddress("OLD_BUILD_MANAGER");
        address legacyMessengerAddress = vm.envAddress("LEGACY_MESSENGER");
        address proxyBuilderAddress = vm.envAddress("PROXY_BUILDER");

        Create3Factory create3Factory = Create3Factory(create3FactoryAddress);
        CryptoLegacyBuildManager oldBuildManager = CryptoLegacyBuildManager(payable(oldBuildManagerAddress));
        FeeRegistry feeRegistry = FeeRegistry(address(oldBuildManager.feeRegistry()));
        LifetimeNft lifetimeNft = LifetimeNft(address(oldBuildManager.lifetimeNft()));
        LegacyMessenger legacyMessenger = LegacyMessenger(legacyMessengerAddress);
        ProxyBuilder proxyBuilder = ProxyBuilder(proxyBuilderAddress);

        PluginsRegistry pluginRegistry = LibDeploy._deployPluginsRegistryAndSet(create3Factory, salt, msg.sender);

        (CryptoLegacyBuildManager buildManager, , ) = LibMockDeploy._deployMockBuildManager(create3Factory, salt, msg.sender, feeRegistry, pluginRegistry, lifetimeNft);

        LibDeploy._initLegacyMessenger(legacyMessenger, buildManager);
        LibDeploy._upgradeFeeRegistry(create3Factory, salt, feeRegistry, proxyBuilder);
        LibDeploy._deployExternalLens(create3Factory, salt, buildManager);

        LibDeploy._deployZeroCryptoLegacy(create3Factory, salt);

        vm.stopBroadcast();
    }
}