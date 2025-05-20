// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/mocks/MockERC20Ownable.sol";
import "./LibDeploy.sol";
import "forge-std/Script.sol";

contract LegacyMessengerDeploy is Script {
    function run() external {
        bytes32 salt = bytes32(vm.envUint("SALT"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address oldBuildManagerAddress = vm.envAddress("OLD_BUILD_MANAGER");
        address create3FactoryAddress = vm.envAddress("CREATE_3_FACTORY");
        CryptoLegacyBuildManager oldBuildManager = CryptoLegacyBuildManager(payable(oldBuildManagerAddress));
        LibDeploy._deployLegacyMessenger(Create3Factory(create3FactoryAddress), salt, msg.sender, oldBuildManager);

        vm.stopBroadcast();
    }
}