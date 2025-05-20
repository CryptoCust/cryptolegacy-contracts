/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./interfaces/ILifetimeNft.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @title LifetimeNft
 * @notice An ERC721 token used to represent lifetime access; includes tier determination.
 */
contract LifetimeNft is ILifetimeNft, ERC721Enumerable, Ownable {
  string internal baseURI;
  mapping(address => bool) public minterOperator;

  event SetBaseURI(string baseURI);
  event SetMinterOperator(address indexed minter, bool indexed isActive);

  /**
   * @notice Constructor for the LifetimeNft contract.
   * @dev Sets the baseURI, name, and symbol for the NFT, and transfers ownership to `_owner`.
   * @param name_ The name for the NFT.
   * @param symbol_ The symbol for the NFT.
   * @param baseURI_ The base URI for token metadata.
   * @param _owner The address to be assigned as owner.
   */
  constructor(string memory name_, string memory symbol_, string memory baseURI_, address _owner) ERC721(name_, symbol_) {
    _setBaseUri(baseURI_);
    _transferOwnership(_owner);
  }

  /**
   * @notice Sets the base URI for all token metadata.
   * @dev Only the owner can call this function. Updates the internal baseURI storage variable.
   * @param baseURI_ The new base URI.
   */
  function setBaseUri(string memory baseURI_) external onlyOwner {
    _setBaseUri(baseURI_);
  }
  /**
   * @notice Internal function to update the base URI.
   * @dev Sets the internal baseURI storage variable and emits a SetBaseURI event.
   * @param baseURI_ The new base URI.
   */
  function _setBaseUri(string memory baseURI_) internal {
    baseURI = baseURI_;
    emit SetBaseURI(baseURI_);
  }

  /**
   * @notice Updates an address’s ability to mint NFTs.
   * @dev This is a setter for the `minterOperator[_minter]` mapping, controlling who can call mint().
   * @param _minter The address to update.
   * @param _isActive Boolean indicating whether `_minter` can mint.
   */
  function setMinterOperator(address _minter, bool _isActive) external onlyOwner {
    minterOperator[_minter] = _isActive;
    emit SetMinterOperator(_minter, _isActive);
  }

  /**
   * @notice Mints a new Lifetime NFT to `_tokenOwner`.
   * @dev Can be called only by an address designated as a minter operator.
   * @param _tokenOwner The address to receive the newly minted NFT.
   * @return tokenId The ID of the newly minted token.
   */
  function mint(address _tokenOwner) external returns(uint256) {
    if (!minterOperator[msg.sender]) {
      revert NotTheMinter();
    }
    uint256 tokenId = totalSupply() + 1;
    _safeMint(_tokenOwner, tokenId);
    return tokenId;
  }

  /**
   * @notice Returns the base URI for token metadata.
   * @dev Overrides ERC721’s _baseURI to return the internal baseURI string.
   * @return The base URI string.
   */
  function _baseURI() internal view override returns (string memory) {
    return baseURI;
  }

  /**
   * @notice Retrieves all token IDs owned by a specified address.
   * @dev Iterates over the tokens owned by _owner and returns them in an array.
   * @param _owner The address whose tokens are to be enumerated.
   * @return tokens An array of token IDs owned by _owner.
   */
  function tokensOfOwner(address _owner) external view returns (uint256[] memory tokens) {
    tokens = new uint256[](balanceOf(_owner));
    for (uint256 i = 0; i < tokens.length; i++) {
      tokens[i] = tokenOfOwnerByIndex(_owner, i);
    }
  }

  /**
   * @notice Determines the tier of a token based on its tokenId.
   * @dev Uses preset thresholds: tokenIds 1–100 are Silicon, 101–300 Gallium, 301–700 Indium, 701–1500 Tantalum, and above 1500 are Based.
   * @param _tokenId The token ID.
   * @return The token tier.
   */
  function getTier(uint256 _tokenId) external pure returns (Tier) {
    if (_tokenId <= 100) {
      return Tier.Silicon;
    } else if (_tokenId <= 300) {
      return Tier.Gallium;
    } else if (_tokenId <= 700) {
      return Tier.Indium;
    } else if (_tokenId <= 1500) {
      return Tier.Tantalum;
    } else {
      return Tier.Based;
    }
  }
}
