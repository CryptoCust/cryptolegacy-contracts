// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./libraries/LibCreate2Deploy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ProxyBuilder is Ownable {
    ProxyAdmin public proxyAdmin;

    event Build(address proxy, address implementation);
    event SetProxyAdmin(address proxyAdmin);

    constructor(address _owner, address _proxyAdmin) {
        if (_proxyAdmin != address(0)) {
            proxyAdmin = ProxyAdmin(_proxyAdmin);
        }
        _transferOwnership(_owner);
    }

    function setProxyAdmin(address _proxyAdmin) external onlyOwner {
        proxyAdmin = ProxyAdmin(_proxyAdmin);
        emit SetProxyAdmin(_proxyAdmin);
    }

    function build(address _create2Address, bytes32 _create2Salt, address _implementation, bytes calldata _initData) external onlyOwner returns (address) {
        address proxy = LibCreate2Deploy._deployByCreate2(
            _create2Address,
            _create2Salt,
            proxyBytecode(_implementation, _initData)
        );
        emit Build(proxy, _implementation);
        return proxy;
    }

    function proxyBytecode(address _implementation, bytes memory _data) public view returns (bytes memory) {
        return abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(_implementation, address(proxyAdmin), _data)
        );
    }

    function computeAddress(bytes32 _salt, bytes32 _bytecodeHash) public view returns (address) {
        return LibCreate2Deploy._computeAddress(_salt, _bytecodeHash);
    }

    error AdminAlreadyCreated();
}
