// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./libraries/LibCreate3.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @notice Deploys TransparentUpgradeableProxy contracts deterministically (via CREATE3) for upgradeable setups.
 */
contract ProxyBuilder is Ownable {
    ProxyAdmin public proxyAdmin;

    event Build(address proxy, address implementation);
    event SetProxyAdmin(address proxyAdmin);

    /**
     * @notice Constructor that sets the initial owner and optionally a `ProxyAdmin` contract.
     * @dev If `_proxyAdmin` is non-zero, that contract is used to manage proxies.
     * @param _owner The address that will own this ProxyBuilder contract.
     * @param _proxyAdmin The `ProxyAdmin` contract address managing upgradeable proxies.
     */
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

    function build(address _create3Address, bytes32 _create3Salt, address _implementation, bytes calldata _initData) external onlyOwner returns (address) {
        address proxy = LibCreate3.create3(
            _create3Salt,
            proxyBytecode(_implementation, _initData)
        );
        if (proxy != _create3Address) {
            revert AddressMismatch();
        }
        emit Build(proxy, _implementation);
        return proxy;
    }

    function proxyBytecode(address _implementation, bytes memory _data) public view returns (bytes memory) {
        return abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(_implementation, address(proxyAdmin), _data)
        );
    }

    function computeAddress(bytes32 _salt) public view returns (address) {
        return LibCreate3.addressOf(_salt);
    }

    error AdminAlreadyCreated();
    error AddressMismatch();
}
