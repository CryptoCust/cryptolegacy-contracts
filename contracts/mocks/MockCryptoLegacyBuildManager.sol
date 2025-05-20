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

  function _checkBuildArgs(BuildArgs memory _buildArgs) internal pure override {
    if (_buildArgs.updateInterval != 15 minutes || _buildArgs.challengeTimeout != 5 minutes) {
      revert NotValidTimeout();
    }
  }

  function mockSetCryptoLegacyBuilt(address _cryptoLegacy, bool _built) external {
    cryptoLegacyBuilt[_cryptoLegacy] = _built;
  }

  function mockSetBeneficiaryRegistry(address _beneficiaryRegistry) external {
    beneficiaryRegistry = IBeneficiaryRegistry(_beneficiaryRegistry);
  }
}
