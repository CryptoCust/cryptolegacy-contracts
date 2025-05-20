pragma solidity 0.8.24;

import "./MockERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AuditMockERC20Rebase is MockERC20 {
  uint256 public rebaseRate = 1000; // 10%
  uint256 constant BASIS = 10000;
  constructor() MockERC20("Mock Rebase", "MockR") {
    _mint(msg.sender, 1000000 ether);
  }
  function setRebaseRate(uint256 _rebaseRate) external onlyOwner {
    rebaseRate = _rebaseRate;
  }

  function growthFactor() public view returns (uint256) {
    return BASIS + rebaseRate;
  }
  
  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal override {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");

    uint256 sharesAmount = (amount * BASIS) / growthFactor();
    _beforeTokenTransfer(from, to, amount);
    uint256 fromBalance = _balances[from];
    require(fromBalance >= sharesAmount, "ERC20: transfer amount exceeds balance");
    unchecked {
      _balances[from] = fromBalance - sharesAmount;
      _balances[to] += sharesAmount;
    }
    emit Transfer(from, to, sharesAmount);
    _afterTokenTransfer(from, to, amount);
  }

  function balanceOf(address account) public view override returns (uint256) {
    return (_balances[account] * growthFactor()) / BASIS;
  }

  function sharesOf(address account) public view returns (uint256) {
    return _balances[account];
  }
}