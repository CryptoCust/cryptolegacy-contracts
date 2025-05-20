/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../CryptoLegacy.sol";
import "../libraries/LibCryptoLegacyDeploy.sol";

contract MockCryptoLegacy is CryptoLegacy {
  constructor(address _buildManager, address _owner, address[] memory _plugins) CryptoLegacy(_buildManager, _owner, _plugins) {

  }

  receive() external payable {

  }

  function mockSetBuildManager(address _buildManager) external {
    ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
    cls.buildManager = ICryptoLegacyBuildManager(_buildManager);
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

  function mockIsLifetimeActiveAndUpdate(address _owner) public returns(bool) {
    return LibCryptoLegacy._isLifetimeActiveAndUpdate(LibCryptoLegacy.getCryptoLegacyStorage(), _owner);
  }

  function mockAddFunctions(address _facetAddress, bytes4[] memory _functionSelectors) public {
    LibCryptoLegacyPlugins.addFunctions(_facetAddress, _functionSelectors);
  }

  function mockRemoveFunctions(address _facetAddress, bytes4[] memory _functionSelectors) public {
    LibCryptoLegacyPlugins.removeFunctions(_facetAddress, _functionSelectors);
  }

  function mockDeployByCreate3(
    address _contractOwner,
    bytes32 _factorySalt,
    address _contractAddress,
    bytes memory _contractBytecode
  ) public returns (address addr) {
    return LibCryptoLegacyDeploy._deployByCreate3(_contractOwner, _factorySalt, _contractAddress, _contractBytecode);
  }
}
