/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../interfaces/ICryptoLegacyPlugin.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../libraries/LibCryptoLegacyPlugins.sol";
import "../libraries/LibDiamond.sol";
import "../interfaces/ICryptoLegacy.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract MockClaimPlugin is ICryptoLegacyPlugin, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    function getSigs() external view returns (bytes4[] memory sigs) {
        sigs = new bytes4[](2);
        sigs[0] = MockClaimPlugin(address(this)).setDefaultClaimDisabled.selector;
        sigs[1] = MockClaimPlugin(address(this)).mockBeneficiaryClaim.selector;
    }
    function getSetupSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](0);
    }
    function getPluginName() public pure returns (string memory) {
        return "beneficiary_distribution_rights";
    }
    function getPluginVer() external pure returns (uint16) {
        return uint16(1);
    }

    function owner() public view returns (address) {
        return LibDiamond.contractOwner();
    }

    function setDefaultClaimDisabled() external payable nonReentrant {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        cls.defaultFuncDisabled = cls.defaultFuncDisabled | LibCryptoLegacy.CLAIM_FUNC_FLAG;
    }

    function mockBeneficiaryClaim(address[] memory _tokens, address _ref, uint256 _refShare) external payable nonReentrant {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();
        require((cls.defaultFuncDisabled & LibCryptoLegacy.CLAIM_FUNC_FLAG) != 0, "DEFAULT_CLAIM_NOT_DISABLED");
        uint256[] memory lockToChainIds = new uint256[](0);
        LibCryptoLegacy._takeFee(cls, owner(), _ref, _refShare, lockToChainIds, lockToChainIds);
        LibCryptoLegacy._checkDistributionReadyForBeneficiary(cls);

        for (uint i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).transfer(msg.sender, IERC20(_tokens[i]).balanceOf(address(this)));
        }
    }

    function addressToHash(address _addr) internal pure returns(bytes32) {
        return keccak256(abi.encode(_addr));
    }
}