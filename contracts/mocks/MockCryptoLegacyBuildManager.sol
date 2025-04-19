/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../CryptoLegacyBuildManager.sol";

contract MockCryptoLegacyBuildManager is CryptoLegacyBuildManager {
  constructor(
    address _owner,
    IFeeRegistry _feeRegistry,
    IPluginsRegistry _pluginsRegistry,
    IBeneficiaryRegistry _beneficiaryRegistry,
    ILifetimeNft _lifetimeNft,
    ICryptoLegacyFactory _factory
  ) CryptoLegacyBuildManager(_owner, _feeRegistry, _pluginsRegistry, _beneficiaryRegistry, _lifetimeNft, _factory) {

  }

  function _checkBuildArgs(BuildArgs memory _buildArgs) internal override {
    // Do not check build args
  }
}
