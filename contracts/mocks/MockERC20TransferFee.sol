/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./MockERC20.sol";

contract MockERC20TransferFee is MockERC20 {
  uint256 public transferFee = 1; // 1% transfer fee
  address public feeWallet;

  constructor() MockERC20("Mock Transfer Fee", "MockTF") {
    _mint(msg.sender, 1000000 ether);
    feeWallet = msg.sender;
  }

  function setTransferFee(uint256 _newFee, address _feeWallet) external onlyOwner {
    require(_newFee <= 10, "Fee too high"); // Max 10%
    transferFee = _newFee;
    feeWallet = _feeWallet;
  }

  function _transfer(address sender, address recipient, uint256 amount) internal override {
    require(_balances[sender] >= amount, "Insufficient balance");

    uint256 feeAmount = (amount * transferFee) / 100;
    uint256 transferAmount = amount - feeAmount;

    _balances[sender] -= amount;
    _balances[recipient] += transferAmount;
    _balances[feeWallet] += feeAmount;

    emit Transfer(sender, recipient, transferAmount);
    emit Transfer(sender, feeWallet, feeAmount);
  }
}
