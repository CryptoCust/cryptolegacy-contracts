// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AbstractTestHelper.sol";
import "../contracts/FeeRegistry.sol";
import "../contracts/LegacyMessenger.sol";
import "../contracts/PluginsRegistry.sol";
import "../contracts/mocks/MockERC20.sol";
import "../contracts/mocks/MockERC721.sol";
import "../contracts/plugins/LensPlugin.sol";
import "../contracts/mocks/MockTestPlugin.sol";
import "../contracts/mocks/MockTest2Plugin.sol";
import "../contracts/mocks/MockClaimPlugin.sol";
import "../contracts/plugins/NftLegacyPlugin.sol";
import "../contracts/plugins/UpdateRolePlugin.sol";
import "../contracts/CryptoLegacyBuildManager.sol";
import "../contracts/interfaces/ICryptoLegacy.sol";
import "../contracts/mocks/MockMaliciousERC20.sol";
import "../contracts/mocks/MockMaliciousERC721.sol";
import "../contracts/libraries/LibCryptoLegacy.sol";
import "../contracts/mocks/AuditMockERC20Rebase.sol";
import "../contracts/plugins/LegacyRecoveryPlugin.sol";
import "../contracts/interfaces/ICryptoLegacyLens.sol";
import "../contracts/plugins/TrustedGuardiansPlugin.sol";
import "../contracts/interfaces/ITrustedGuardiansPlugin.sol";
import "../contracts/plugins/BeneficiaryPluginAddRights.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CryptoLegacyTest is AbstractTestHelper {

  function setUp() public override {
    super.setUp();
    vm.startPrank(owner);
    pluginsRegistry.addPlugin(cryptoLegacyBasePlugin, "");
    feeRegistry.setLockOperator(address(buildManager), true);
    vm.stopPrank();

    vm.prank(owner);
    mockToken1 = new MockERC20("Mock", "MOCK");
  }

  function testFuzzAuditSubTransferToken(uint128 _tokenAmount, uint128 _subTokens) public {
    vm.startPrank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "123");
    pluginsRegistry.addPluginDescription(lensPlugin, "123");
    vm.stopPrank();

    bytes32[] memory beneficiaryArr;
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr;
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    (cryptoLegacy, cryptoLegacyLens, beneficiaryArr, beneficiaryConfigArr) = _buildCryptoLegacy(bob, buildFee, bytes8(0));

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    vm.warp(block.timestamp + clData.updateInterval);

    vm.prank(bob);
    cryptoLegacy.update{value: 0.1 ether}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(owner);
    mockToken1.mint(treasury, _tokenAmount);
    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), _tokenAmount);

    vm.warp(block.timestamp + clData.updateInterval + 1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();
    address[] memory _tokens = _getOneAddressList(address(mockToken1));

    vm.warp(block.timestamp + clData.challengeTimeout + 1);

    vm.startPrank(bobBeneficiary1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_getOneAddressList(treasury), _tokens);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    vm.stopPrank();

    if (mockToken1.balanceOf(address(cryptoLegacy)) >= _subTokens) {
      vm.prank(owner);
      mockToken1.mockTransferFrom(address(cryptoLegacy), address(1), _subTokens);
    }

    vm.prank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0); 
  }

  function testFuzzAuditAddTransferToken(uint128 _tokenAmount, uint128 _addTokens) public {
    vm.startPrank(owner);
    pluginsRegistry.addPlugin(lensPlugin, "123");
    pluginsRegistry.addPluginDescription(lensPlugin, "123");
    vm.stopPrank();

    bytes32[] memory beneficiaryArr;
    ICryptoLegacy.BeneficiaryConfig[] memory beneficiaryConfigArr;
    CryptoLegacyBasePlugin cryptoLegacy;
    ICryptoLegacyLens cryptoLegacyLens;
    (cryptoLegacy, cryptoLegacyLens, beneficiaryArr, beneficiaryConfigArr) = _buildCryptoLegacy(bob, buildFee, bytes8(0));

    ICryptoLegacyLens.CryptoLegacyBaseData memory clData = cryptoLegacyLens.getCryptoLegacyBaseData();

    vm.warp(block.timestamp + clData.updateInterval);

    vm.prank(bob);
    cryptoLegacy.update{value: 0.1 ether}(_getEmptyUintList(), _getEmptyUintList());

    vm.prank(owner);
    mockToken1.mint(treasury, _tokenAmount);
    vm.prank(treasury);
    mockToken1.approve(address(cryptoLegacy), _tokenAmount);

    vm.warp(block.timestamp + clData.updateInterval + 1);

    vm.prank(bobBeneficiary1);
    cryptoLegacy.initiateChallenge();
    address[] memory _tokens = _getOneAddressList(address(mockToken1));

    vm.warp(block.timestamp + clData.challengeTimeout + 1);

    vm.startPrank(bobBeneficiary1);
    cryptoLegacy.transferTreasuryTokensToLegacy(_getOneAddressList(treasury), _tokens);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0);
    vm.stopPrank();
  
    vm.prank(owner);
    mockToken1.mint(address(cryptoLegacy), _addTokens);

    vm.prank(bobBeneficiary2);
    cryptoLegacy.beneficiaryClaim(_tokens, address(0), 0); 
  }
}
