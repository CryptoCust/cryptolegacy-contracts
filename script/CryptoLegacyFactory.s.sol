// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/BeneficiaryRegistry.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "./LibDeploy.sol";
import {CryptoLegacyExternalLens} from "../contracts/CryptoLegacyExternalLens.sol";
import {FeeRegistry} from "../contracts/FeeRegistry.sol";
import {LensPlugin} from "../contracts/plugins/LensPlugin.sol";
import {PluginsRegistry} from "../contracts/PluginsRegistry.sol";
import {Script} from "forge-std/Script.sol";

contract MockCryptoLegacyFactoryDeploy is Script {
    bytes32 internal salt = bytes32(uint256(1));
    bytes32 internal proxySalt = bytes32(uint256(1));

    function run() external {
        salt = bytes32(vm.envUint("SALT"));
        proxySalt = bytes32(vm.envUint("PROXY_SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address multiSig1 = vm.envAddress("MULTISIG_1");
        address multiSig2 = vm.envAddress("MULTISIG_2");
        address multiSig3 = vm.envAddress("MULTISIG_3");

        LifetimeNft lifetimeNft = LibDeploy._deployLifeTimeNft(salt, msg.sender);
        ProxyBuilder proxyBuilder = LibDeploy._deployProxyBuilder(salt, msg.sender);
        FeeRegistry feeRegistry = LibDeploy._deployFeeRegistry(salt, proxySalt, msg.sender, proxyBuilder, uint32(1000), uint32(2000), lifetimeNft, 60);
        PluginsRegistry pluginRegistry = LibDeploy._deployPluginsRegistryAndSet(salt, msg.sender);

        (CryptoLegacyBuildManager buildManager, , ) = LibDeploy._deployBuildManager(salt, msg.sender,  feeRegistry, pluginRegistry, lifetimeNft);
        LibDeploy._deployExternalLens(salt, buildManager);

        LibDeploy._initFeeRegistry(feeRegistry, buildManager, 0.00003 ether, 0.00002 ether, 0.00001 ether, 1000, 2000);
        LibDeploy._setFeeRegistryCrossChains(feeRegistry);
        LegacyMessenger legacyMessenger = LibDeploy._deployLegacyMessenger(salt, msg.sender, buildManager);

        LibDeploy._deployZeroCryptoLegacy(salt);

        SignatureRoleTimelock srt = LibDeploy._deploySignatureRoleTimelock(salt, buildManager, proxyBuilder, legacyMessenger, multiSig1, multiSig2, multiSig3);

        LibDeploy._transferOwnershipWithLm(address(srt), buildManager, proxyBuilder, legacyMessenger);

        vm.stopBroadcast();
    }
}