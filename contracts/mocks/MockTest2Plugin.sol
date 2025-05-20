/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../interfaces/ICryptoLegacyPlugin.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../libraries/LibCryptoLegacyPlugins.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/ICryptoLegacy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract MockTest2Plugin is ICryptoLegacyPlugin, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    function getSigs() public view returns (bytes4[] memory sigs) {
        sigs = new bytes4[](1);
        sigs[0] = MockTest2Plugin(address(this)).test.selector;
    }
    function getSetupSigs() external view returns (bytes4[] memory sigs) {
        return getSigs();
    }
    function getPluginName() public pure returns (string memory) {
        return "beneficiary_distribution_rights";
    }
    function getPluginVer() external pure returns (uint16) {
        return uint16(1);
    }

    function test() public pure returns (uint) {
        return 2;
    }
}