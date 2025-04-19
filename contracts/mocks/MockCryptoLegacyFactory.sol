/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../CryptoLegacyFactory.sol";
import "./MockCryptoLegacy.sol";

contract MockCryptoLegacyFactory is CryptoLegacyFactory {
  constructor(address _owner) CryptoLegacyFactory(_owner) {

  }

  function cryptoLegacyBytecode(
    address _buildManager,
    address _owner,
    address[] memory _plugins
  ) public override pure returns (bytes memory) {
    return abi.encodePacked(
      type(MockCryptoLegacy).creationCode,
      abi.encode(_buildManager, _owner, _plugins)
    );
  }
}
