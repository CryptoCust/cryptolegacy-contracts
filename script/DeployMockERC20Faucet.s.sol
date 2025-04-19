// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/CryptoLegacyFactory.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/LifetimeNft.sol";
import "../contracts/mocks/MockERC20Faucet.sol";
import "../contracts/mocks/MockERC20Rebase.sol";
import "../contracts/mocks/MockERC20TransferBurn.sol";
import "../contracts/mocks/MockERC20TransferFee.sol";
import {FeeRegistry} from "../contracts/FeeRegistry.sol";
import {LensPlugin} from "../contracts/plugins/LensPlugin.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {PluginsRegistry} from "../contracts/PluginsRegistry.sol";
import {Script} from "forge-std/Script.sol";

contract DeployMockERC20Faucet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address[] memory tokens = new address[](4);
        tokens[0] = address(new MockERC20("Mock", "MOCK"));
        tokens[1] = address(new MockERC20Rebase());
        tokens[2] = address(new MockERC20TransferBurn());
        tokens[3] = address(new MockERC20TransferFee());

        MockERC20Faucet faucet = new MockERC20Faucet();

        for (uint256 i = 0; i < tokens.length; i++) {
            MockERC20(tokens[i]).transferOwnership(address(faucet));
        }

        faucet.addTokens(tokens, 10000 ether);
        faucet.mintTokens(tokens, 10000000 ether);
        faucet.claimTokens();

        vm.stopBroadcast();
    }
}