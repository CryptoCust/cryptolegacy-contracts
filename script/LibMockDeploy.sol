/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "./LibDeploy.sol";
import "../contracts/mocks/MockLifetimeNft.sol";
import "../contracts/mocks/MockCryptoLegacyFactory.sol";
import "../contracts/mocks/MockCryptoLegacyBuildManager.sol";

library LibMockDeploy {
    function _deployMockBuildManager(Create3Factory _factory, bytes32 _salt, address _owner, FeeRegistry _feeRegistry, PluginsRegistry _pluginRegistry, LifetimeNft _lifetimeNft) internal returns(CryptoLegacyBuildManager buildManager, BeneficiaryRegistry beneficiaryRegistry, CryptoLegacyFactory factory){
        beneficiaryRegistry = LibDeploy._deployBeneficiaryRegistry(_factory, _salt, _owner);
        factory = MockCryptoLegacyFactory(LibDeploy.c3(
            _factory,
            _salt,
            LibDeploy.CryptoLegacyFactoryName,
            LibDeploy.contractWithOwnerBytecode(type(MockCryptoLegacyFactory).creationCode, _owner)
        ));
        buildManager = CryptoLegacyBuildManager(payable(LibDeploy.c3(
            _factory,
            _salt,
            LibDeploy.CryptoLegacyBuildManagerName,
            cryptoLegacyBuildManagerBytecode(_owner, _feeRegistry, _pluginRegistry, beneficiaryRegistry, _lifetimeNft, factory)
        )));
        LibDeploy._afterDeployBuildManager(buildManager);
    }

    function _deployMockLifeTimeNft(Create3Factory _factory, bytes32 _salt, address _owner) internal returns(MockLifetimeNft lifetimeNft) {
        lifetimeNft = MockLifetimeNft(LibDeploy.c3(
            _factory,
            _salt,
            LibDeploy.LifetimeNftName,
            lifetimeNftBytecode("LIFEC Mock", "LIFEC Mock", "", _owner)
        ));
    }

    function cryptoLegacyBuildManagerBytecode(
        address _owner,
        IFeeRegistry _feeRegistry,
        IPluginsRegistry _pluginsRegistry,
        IBeneficiaryRegistry _beneficiaryRegistry,
        ILifetimeNft _lifetimeNft,
        ICryptoLegacyFactory _factory
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(MockCryptoLegacyBuildManager).creationCode,
            abi.encode(_owner, _feeRegistry, _pluginsRegistry, _beneficiaryRegistry, _lifetimeNft, _factory)
        );
    }

    function lifetimeNftBytecode(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        address _owner
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            type(MockLifetimeNft).creationCode,
            abi.encode(name_, symbol_, baseURI_, _owner)
        );
    }

    function _mockLifetimeNftBytecodeHash(address _owner) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(
            type(MockLifetimeNft).creationCode,
            abi.encode("LIFEC Mock", "LIFEC Mock", "", _owner)
        ));
    }
    function _mockLifetimeNftPredictedAddress(Create3Factory _factory, bytes32 _salt) internal view returns(address) {
        return LibDeploy._lifetimeNftPredictedAddress(_factory, _salt);
    }

    function _initFeeRegistry(FeeRegistry _feeRegistry, CryptoLegacyBuildManager _buildManager, uint128 _lifetimeFee, uint128 _buildFee, uint128 _updateFee) internal {
        LibDeploy._initFeeRegistry(_feeRegistry, _buildManager, _lifetimeFee, _buildFee, _updateFee);
        _feeRegistry.setCodeOperator(address(_buildManager), true);
    }
}