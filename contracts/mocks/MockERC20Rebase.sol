/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./MockERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Rebase is MockERC20 {
  uint256 public startBlock;
  uint256 public rebaseRate = 10; // Growth per block in basis points (e.g., 100 = 1%)

  constructor() MockERC20("Mock Rebase", "MockR") {
    _mint(msg.sender, 1000000 ether);
    startBlock = block.number;
  }

  function setRebaseRate(uint256 _rebaseRate) external onlyOwner {
    rebaseRate = _rebaseRate;
  }

  function growthFactor() public view returns (uint256) {
    uint256 blocksElapsed = block.number - startBlock;
    return (1e18 + (rebaseRate * blocksElapsed)) / 1e18;
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");

    _beforeTokenTransfer(from, to, amount);

    uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
      _balances[from] = fromBalance - (amount * 1e18) / growthFactor();
      // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
      // decrementing then incrementing.
      _balances[to] += (amount * 1e18) / growthFactor();
    }

    emit Transfer(from, to, amount);

    _afterTokenTransfer(from, to, amount);
  }

  function balanceOf(address account) public view override returns (uint256) {
    return (_balances[account] * growthFactor()) / 1e18;
  }
}
