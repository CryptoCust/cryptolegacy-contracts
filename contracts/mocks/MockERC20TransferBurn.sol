/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./MockERC20.sol";

contract MockERC20TransferBurn is MockERC20 {
  uint256 public burnRate = 2; // 2% burn per transfer

  constructor() MockERC20("Mock Transfer Fee", "MockTF") {
    _mint(msg.sender, 1000000 ether);
  }

  function setBurnRate(uint256 _burnRate) external onlyOwner {
    require(_burnRate <= 10, "Fee too high"); // Max 10%
    burnRate = _burnRate;
  }

  function _transfer(address sender, address recipient, uint256 amount) internal override {
    require(_balances[sender] >= amount, "Insufficient balance");

    uint256 burnAmount = (amount * burnRate) / 100;
    uint256 transferAmount = amount - burnAmount;

    _balances[sender] -= amount;
    _balances[recipient] += transferAmount;
    _totalSupply -= burnAmount; // Burn the tokens

    emit Transfer(sender, recipient, transferAmount);
    emit Transfer(sender, address(0), burnAmount); // Burn event
  }
}
