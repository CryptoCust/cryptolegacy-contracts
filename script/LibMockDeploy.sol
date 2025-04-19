/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "./LibDeploy.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "../contracts/mocks/MockCryptoLegacyFactory.sol";
import "../contracts/mocks/MockCryptoLegacyBuildManager.sol";

library LibMockDeploy {
    function _deployMockBuildManager(bytes32 _salt, address _owner, FeeRegistry _feeRegistry, PluginsRegistry _pluginRegistry, LifetimeNft _lifetimeNft) internal returns(CryptoLegacyBuildManager buildManager, BeneficiaryRegistry beneficiaryRegistry, CryptoLegacyFactory factory){
        beneficiaryRegistry = new BeneficiaryRegistry{salt: _salt}(_owner);
        factory = new MockCryptoLegacyFactory{salt: _salt}(_owner);
        buildManager = new MockCryptoLegacyBuildManager{salt: _salt}(_owner, _feeRegistry, _pluginRegistry, beneficiaryRegistry, _lifetimeNft, factory);
        LibDeploy._afterDeployBuildManager(buildManager);
    }

    function _deployMockLifeTimeNft(bytes32 _salt, address _owner) internal returns(MockLifetimeNft lifetimeNft) {
        lifetimeNft = new MockLifetimeNft{salt: _salt}("LIFEC Mock", "LIFEC Mock", "", _owner);
    }

    function _initFeeRegistry(FeeRegistry _feeRegistry, CryptoLegacyBuildManager _buildManager, uint128 _lifetimeFee, uint128 _buildFee, uint128 _updateFee, uint256 _refDiscountPct, uint256 _refSharePct) internal {
        LibDeploy._initFeeRegistry(_feeRegistry, _buildManager, _lifetimeFee, _buildFee, _updateFee, _refDiscountPct, _refSharePct);
        _feeRegistry.setCodeOperator(address(_buildManager), true);
    }
}