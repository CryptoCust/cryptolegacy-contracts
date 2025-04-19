// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract ProxyBuilderAdmin is ProxyAdmin {
    constructor(address _owner) {
        _transferOwnership(_owner);
    }
}
