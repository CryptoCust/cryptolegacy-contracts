/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./MockERC20.sol";

contract MockERC20Ownable is MockERC20 {
  constructor(string memory name_, string memory symbol_, address owner_) MockERC20(name_, symbol_) {
    _transferOwnership(owner_);
  }
}
