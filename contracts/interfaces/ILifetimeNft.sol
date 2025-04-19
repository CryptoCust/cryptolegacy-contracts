/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface ILifetimeNft is IERC721Enumerable {
    enum Tier {
        None,
        Silicon,
        Gallium,
        Indium,
        Based,
        Tantalum
    }

    function mint(address _tokenOwner) external returns(uint256 tokenId);

    function setMinterOperator(address _minter, bool _isActive) external;

    error NotTheMinter();
}
