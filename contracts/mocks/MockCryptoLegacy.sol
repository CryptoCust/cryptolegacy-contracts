/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../CryptoLegacy.sol";

contract MockCryptoLegacy is CryptoLegacy {
  constructor(address _buildManager, address _owner, address[] memory _plugins) CryptoLegacy(_buildManager, _owner, _plugins) {

  }

  function getSigs() public pure returns (bytes4[] memory sigs) {
    sigs = new bytes4[](0);
  }
  function getSetupSigs() external pure returns (bytes4[] memory sigs) {
    sigs = new bytes4[](0);
  }
  function getPluginName() external pure returns (string memory) {
    return "lens";
  }
  function getPluginVer() external pure returns (uint16) {
    return uint16(1);
  }
}
