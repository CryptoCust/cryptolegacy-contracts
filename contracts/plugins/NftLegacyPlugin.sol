/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../libraries/LibDiamond.sol";
import "../interfaces/ICryptoLegacy.sol";
import "../libraries/LibCryptoLegacy.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NftLegacyPlugin
 * @notice Extends CryptoLegacy functionality to support NFT asset inheritance. It allows setting NFT beneficiaries, transferring NFTs into the inheritance contract, and claiming them after specified delays, seamlessly integrating NFTs into legacy plans.
*/
contract NftLegacyPlugin is ICryptoLegacyPlugin, ReentrancyGuard {
    bytes32 public constant PLUGIN_POSITION = keccak256("nft_legacy.plugin.storage");

    event SetNftBeneficiary(address indexed nftContract, uint256 indexed tokenId, bytes32 indexed beneficiaryHash);
    event BeneficiaryClaimNft(address indexed nftContract, uint256 indexed tokenId, bytes32 indexed beneficiaryHash, address beneficiaryAddress);
    event TransferNftToCryptoLegacy(address indexed nftContract, uint256 indexed tokenId);

    /**
     * @notice Returns the list of function selectors provided by this plugin.
     * @dev These selectors represent the externally callable functions of the NFT plugin.
     * @return sigs An array of function selectors.
     */
    function getSigs() external view returns (bytes4[] memory sigs) {
        sigs = new bytes4[](3);
        sigs[0] = NftLegacyPlugin(address(this)).setNftBeneficiary.selector;
        sigs[1] = NftLegacyPlugin(address(this)).transferNftTokensToLegacy.selector;
        sigs[2] = NftLegacyPlugin(address(this)).beneficiaryClaimNft.selector;
    }

    /**
     * @notice Returns the setup function selectors for this plugin.
     * @dev This plugin does not require any setup functions.
     * @return sigs An empty array of function selectors.
     */
    function getSetupSigs() external pure returns (bytes4[] memory sigs) {
        sigs = new bytes4[](0);
    }
    /**
     * @notice Returns the unique name for this plugin.
     * @dev The name is used for identification purposes across the CryptoLegacy ecosystem.
     * @return A string representing the plugin name.
     */
    function getPluginName() external pure returns (string memory) {
        return "nft_legacy";
    }
    /**
     * @notice Returns the version number for this plugin.
     * @dev The version returned is encoded as a uint16.
     * @return The plugin version.
     */
    function getPluginVer() external pure returns (uint16) {
        return uint16(1);
    }

    /**
     * @notice Struct representing the NFT beneficiary configuration.
     * @dev Contains the hashed beneficiary address and a delay value determining when a beneficiary may claim the NFT.
     * @param addressHash The keccak256 hash of the beneficiary's address.
     * @param claimDelay The delay (in seconds) after distribution starts before the NFT becomes claimable.
     */
    struct NftBeneficiary {
        bytes32 addressHash;
        uint64 claimDelay;
    }
    /**
     * @notice Plugin storage for NFT legacy functionality.
     * @dev Maps an NFT contract and token ID to a defined beneficiary.
     */
    struct PluginStorage {
        mapping (address => mapping (uint256 => NftBeneficiary)) nftBeneficiary;
    }

    /**
     * @notice Retrieves the plugin storage using a fixed storage slot.
     * @dev Uses inline assembly to assign a storage slot based on PLUGIN_POSITION.
     * @return storageStruct A reference to the PluginStorage struct.
     */
    function getPluginStorage() internal pure returns (PluginStorage storage storageStruct) {
        bytes32 position = PLUGIN_POSITION;
        assembly {
            storageStruct.slot := position
        }
    }

    /**
     * @notice Modifier that restricts function access to the owner.
     * @dev Invokes LibCryptoLegacy._checkOwner() to verify that msg.sender is the contract owner.
     */
    modifier onlyOwner() {
        LibCryptoLegacy._checkOwner();
        _;
    }

    /**
     * @notice Sets the NFT beneficiary for a list of token IDs from a given NFT contract.
     * @dev Can only be called by the owner. For each token ID, stores the beneficiary hash and claim delay.
     * Emits a SetNftBeneficiary event for each token.
     * @param _beneficiary The keccak256 hash of the beneficiary's address.
     * @param _nftContract The address of the NFT contract.
     * @param _tokenIds An array of NFT token IDs.
     * @param _delay The claim delay (in seconds) before the NFT can be claimed.
     */
    function setNftBeneficiary(bytes32 _beneficiary, address _nftContract, uint256[] memory _tokenIds, uint32 _delay) public onlyOwner {
        PluginStorage storage pluginStorage = getPluginStorage();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            pluginStorage.nftBeneficiary[_nftContract][_tokenIds[i]] = NftBeneficiary({addressHash: _beneficiary, claimDelay: _delay});
            emit SetNftBeneficiary(_nftContract, _tokenIds[i], _beneficiary);
        }
    }

    /**
     * @notice Transfers NFT tokens from their current owners into the CryptoLegacy contract.
     * @dev Checks that distribution is ready; then for each token:
     *   - Verifies that a beneficiary has been set.
     *   - Transfers the token from its current owner to the contract.
     * Requirements:
     * - Distribution must be ready.
     * - If the caller is not the nft beneficiary (as determined by their hash) then they must have a nonzero share.
     * @param _nftContract The address of the NFT contract.
     * @param _tokenIds An array of token IDs to transfer.
     */
    function transferNftTokensToLegacy(address _nftContract, uint256[] memory _tokenIds) public nonReentrant {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

        LibCryptoLegacy._checkDistributionReady(cls);
        bytes32 senderHash = LibCryptoLegacy._addressToHash(msg.sender);
        bool senderIsBeneficiary = false;

        PluginStorage storage pluginStorage = getPluginStorage();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            address tokenOwner = IERC721(_nftContract).ownerOf(_tokenIds[i]);
            NftBeneficiary memory beneficiary = pluginStorage.nftBeneficiary[_nftContract][_tokenIds[i]];
            if (beneficiary.addressHash == bytes32(0)) {
                revert ICryptoLegacy.BeneficiaryNotSet();
            }
            if (beneficiary.addressHash == senderHash) {
                senderIsBeneficiary = true;
            }
            IERC721(_nftContract).transferFrom(tokenOwner, address(this), _tokenIds[i]);
            emit TransferNftToCryptoLegacy(_nftContract, _tokenIds[i]);
        }

        if (!senderIsBeneficiary && cls.beneficiaryConfig[senderHash].shareBps == uint64(0)) {
            revert ICryptoLegacy.NotTheBeneficiary();
        }
    }

    /**
     * @notice Allows the designated beneficiary to claim NFT tokens.
     * @dev For each token ID:
     *   - Verifies that the caller is the designated beneficiary.
     *   - Checks that the current time is at least distributionStartAt + claimDelay.
     *   - Transfers the token from the contract to the caller.
     * Requirements:
     * - Caller’s beneficiary hash must match.
     * - The claim delay condition must be met.
     * @param _nftContract The address of the NFT contract.
     * @param _tokenIds An array of token IDs to claim.
     */
    function beneficiaryClaimNft(address _nftContract, uint256[] memory _tokenIds) public nonReentrant {
        ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

        if (_tokenIds.length == 0) {
            revert ICryptoLegacy.ZeroTokens();
        }
        LibCryptoLegacy._checkDistributionReady(cls);
        bytes32 senderHash = LibCryptoLegacy._addressToHash(msg.sender);

        PluginStorage storage pluginStorage = getPluginStorage();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            address tokenOwner = IERC721(_nftContract).ownerOf(_tokenIds[i]);
            NftBeneficiary memory beneficiary = pluginStorage.nftBeneficiary[_nftContract][_tokenIds[i]];
            if (beneficiary.addressHash != senderHash) {
                revert ICryptoLegacy.NotTheBeneficiary();
            }
            if (uint64(block.timestamp) < beneficiary.claimDelay + cls.distributionStartAt) {
               revert ICryptoLegacy.DistributionDelay();
            }

            IERC721(_nftContract).transferFrom(tokenOwner, msg.sender, _tokenIds[i]);
            emit BeneficiaryClaimNft(_nftContract, _tokenIds[i], beneficiary.addressHash, msg.sender);
        }
    }
}