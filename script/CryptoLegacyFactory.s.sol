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

contract MockCryptoLegacyFactoryDeploy is Script {
    bytes32 internal salt =              bytes32(uint256(1));
    bytes32 internal proxySalt =         bytes32(uint256(1));
    uint32 internal refDiscountPct =     uint32(500);
    uint32 internal refSharePct =        uint32(1000);
    uint64 internal nftLockPeriod =      12 minutes;
    uint64 internal nftTransferTimeout = 2 minutes;
    uint128 internal lifetimeFee =       uint128(0.000000001 ether);
    uint128 internal buildFee =          uint128(0.000000000001 ether);
    uint128 internal updateFee =         uint128(0.000000000001 ether);

    address internal multiSig1;
    address internal multiSig2;
    address internal multiSig3;

    function run() external {
        salt = bytes32(vm.envUint("SALT"));
        proxySalt = bytes32(vm.envUint("PROXY_SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        multiSig1 = vm.envAddress("MULTISIG_1");
        multiSig2 = vm.envAddress("MULTISIG_2");
        multiSig3 = vm.envAddress("MULTISIG_3");

        Create3Factory factory = LibDeploy._deployCreate3Factory(salt, msg.sender);

        LifetimeNft lifetimeNft;
        if (LibDeploy._getNftMainnetId() == block.chainid) {
            //TODO: change from mock to simple one
            lifetimeNft = LibMockDeploy._deployMockLifeTimeNft(factory, salt, msg.sender);
        } else {
            //TODO: change from mock to simple one
            lifetimeNft = LifetimeNft(LibMockDeploy._mockLifetimeNftPredictedAddress(factory, salt));
        }
        ProxyBuilder proxyBuilder = LibDeploy._deployProxyBuilder(factory, salt, msg.sender);
        FeeRegistry feeRegistry = LibDeploy._deployFeeRegistry(factory, salt, proxySalt, msg.sender, proxyBuilder, refDiscountPct, refSharePct, lifetimeNft, nftLockPeriod, nftTransferTimeout);
        PluginsRegistry pluginRegistry = LibDeploy._deployPluginsRegistryAndSet(factory, salt, msg.sender);

        //TODO: change from mock to simple one
        (CryptoLegacyBuildManager buildManager, , ) = LibMockDeploy._deployMockBuildManager(factory, salt, msg.sender,  feeRegistry, pluginRegistry, lifetimeNft);
        LibDeploy._deployExternalLens(factory, salt, buildManager);

        LibDeploy._initFeeRegistry(feeRegistry, buildManager, lifetimeFee, buildFee, updateFee);
        LibDeploy._setFeeRegistryCrossChains(feeRegistry);
        LegacyMessenger legacyMessenger = LibDeploy._deployLegacyMessenger(factory, salt, msg.sender, buildManager);

        LibDeploy._deployZeroCryptoLegacy(factory, salt);

        SignatureRoleTimelock srt = LibDeploy._deploySignatureRoleTimelock(factory, salt, buildManager, proxyBuilder, legacyMessenger, multiSig1, multiSig2, multiSig3);

        LibDeploy._initMultisigRights(feeRegistry, multiSig2);
        LibDeploy._transferOwnershipWithLm(address(srt), buildManager, proxyBuilder, legacyMessenger);

        vm.stopBroadcast();
    }
}