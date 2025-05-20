// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./LibDeploy.sol";
import "./LibMockDeploy.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "../contracts/CryptoLegacyExternalLens.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "forge-std/Script.sol";

contract MockCryptoLegacyFactoryDeploy is Script {
    bytes32 internal salt = bytes32(uint256(1));
    bytes32 internal proxySalt = bytes32(uint256(1));

    function run() external {
        salt = bytes32(vm.envUint("SALT"));
        proxySalt = bytes32(vm.envUint("PROXY_SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Create3Factory factory = LibDeploy._deployCreate3Factory(salt, msg.sender);

        LifetimeNft lifetimeNft = LibMockDeploy._deployMockLifeTimeNft(factory, salt, msg.sender);
        ProxyBuilder proxyBuilder = LibDeploy._deployProxyBuilder(factory, salt, msg.sender);
        FeeRegistry feeRegistry = LibDeploy._deployFeeRegistry(factory, salt, proxySalt, msg.sender, proxyBuilder, uint32(500), uint32(1000), lifetimeNft, 60 * 12, 60 * 2);
        PluginsRegistry pluginRegistry = LibDeploy._deployPluginsRegistryAndSet(factory, salt, msg.sender);

        (CryptoLegacyBuildManager buildManager, , ) = LibMockDeploy._deployMockBuildManager(factory, salt, msg.sender,  feeRegistry, pluginRegistry, lifetimeNft);

        LibDeploy._initFeeRegistry(feeRegistry, buildManager, 0.000000001 ether, 0.000000000001 ether, 0.000000000001 ether);
        LibDeploy._setFeeRegistryCrossChains(feeRegistry);
        LibDeploy._deployLegacyMessenger(factory, salt, msg.sender, buildManager);
        LibDeploy._deployExternalLens(factory, salt, buildManager);

        LibDeploy._deployZeroCryptoLegacy(factory, salt);

        vm.stopBroadcast();
    }
}