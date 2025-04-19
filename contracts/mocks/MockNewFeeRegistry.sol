/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../FeeRegistry.sol";

contract MockNewFeeRegistry is FeeRegistry {
  constructor() FeeRegistry() {

  }

  function clearCustomChainId() external onlyOwner {
    LCGStorage storage ls = lockChainGateStorage();
    ls.customChainId = 0;
    emit SetCustomChainId(0);
  }
}
