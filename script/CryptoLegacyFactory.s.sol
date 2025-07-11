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

contract CryptoLegacyFactoryDeploy is Script {
    bytes32 internal salt =              bytes32(uint256(1));
    bytes32 internal proxySalt =         bytes32(uint256(1));
    uint32 internal refDiscountPct =     uint32(500);
    uint32 internal refSharePct =        uint32(1000);
    uint64 internal nftLockPeriod =      150 days;
    uint64 internal nftTransferTimeout = 14 days;
    uint128 internal lifetimeFee =       uint128(1 ether);
    uint128 internal buildFee =          uint128(0.05 ether);
    uint128 internal updateFee =         uint128(0.05 ether);

    address internal create3Factory;

    address internal multiSig1;
    address internal multiSig2;
    address internal multiSig3;

    SignatureRoleTimelock internal srt;
    CryptoLegacyBuildManager internal buildManager;
    LegacyMessenger internal legacyMessenger;
    ProxyBuilder internal proxyBuilder;
    LifetimeNft internal lifetimeNft;
    FeeRegistry internal feeRegistry;
    PluginsRegistry internal pluginRegistry;

    function run() public virtual {
        salt = bytes32(vm.envUint("SALT"));
        proxySalt = bytes32(vm.envUint("PROXY_SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        create3Factory = vm.envAddress("CREATE_3_FACTORY");

        multiSig1 = vm.envAddress("MULTISIG_1");
        multiSig2 = vm.envAddress("MULTISIG_2");
        multiSig3 = vm.envAddress("MULTISIG_3");

        Create3Factory factory = Create3Factory(create3Factory);

        if (LibDeploy._getNftMainnetId() == block.chainid) {
            lifetimeNft = LibDeploy._deployLifeTimeNft(factory, salt, msg.sender);
        } else {
            lifetimeNft = LifetimeNft(LibDeploy._lifetimeNftPredictedAddress(factory, salt));
        }
        proxyBuilder = LibDeploy._deployProxyBuilder(factory, salt, msg.sender);
        feeRegistry = LibDeploy._deployFeeRegistry(factory, salt, proxySalt, msg.sender, proxyBuilder, refDiscountPct, refSharePct, lifetimeNft, nftLockPeriod, nftTransferTimeout);
        pluginRegistry = LibDeploy._deployPluginsRegistryAndSet(factory, salt, msg.sender);

        (buildManager, , ) = LibDeploy._deployBuildManager(factory, salt, msg.sender,  feeRegistry, pluginRegistry, lifetimeNft);
        LibDeploy._deployExternalLens(factory, salt, buildManager);

        LibDeploy._initFeeRegistry(feeRegistry, buildManager, lifetimeFee, buildFee, updateFee);
        LibDeploy._setFeeRegistryCrossChains(feeRegistry);
        legacyMessenger = LibDeploy._deployLegacyMessenger(factory, salt, msg.sender, buildManager);

        LibDeploy._deployZeroCryptoLegacy(factory, salt);

        srt = LibDeploy._deploySignatureRoleTimelock(factory, salt, buildManager, proxyBuilder, legacyMessenger, multiSig1, multiSig2, multiSig3);

        LibDeploy._initMultisigRights(feeRegistry, multiSig2);
        LibDeploy._transferOwnershipWithLm(address(srt), buildManager, proxyBuilder, legacyMessenger);

        vm.stopBroadcast();
    }
}