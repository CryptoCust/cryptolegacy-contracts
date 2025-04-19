/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../LifetimeNft.sol";

contract MockLifetimeNft is LifetimeNft {
  constructor(string memory name_, string memory symbol_, string memory baseURI_, address _owner) LifetimeNft(name_, symbol_, baseURI_, _owner) {

  }

  function mockMint(address _tokenOwner, uint256 tokenId) external returns(uint256) {
    _mint(_tokenOwner, tokenId);
    return tokenId;
  }
}
