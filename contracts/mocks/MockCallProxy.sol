/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "../interfaces/ICallProxy.sol";
import "../LockChainGate.sol";

contract MockCallProxy is ICallProxy {
    uint256 public submissionChainIdFrom;
    bytes public submissionNativeSender;
    uint256 public counter;

    constructor() {}

    function setSourceChainIdAndContract(LockChainGate _contract) public {
        submissionChainIdFrom = _contract.getChainId();
        submissionNativeSender = abi.encodePacked(address(_contract));
    }

    function setSourceChainIdAndContract(uint256 cid, LockChainGate _contract) public {
        submissionChainIdFrom = cid;
        submissionNativeSender = abi.encodePacked(address(_contract));
    }

    function callMessage(address contractToCall, bytes memory contractCallData) external payable returns(bool, bytes memory) {
        return contractToCall.call(contractCallData);
    }

    function call(
        address,
        address,
        bytes memory,
        uint256,
        bytes memory,
        uint256
    ) external payable override returns (bool) {
        counter++;
        return true;
    }
    function callERC20(
        address,
        address,
        address,
        bytes memory,
        uint256,
        bytes memory,
        uint256
    ) external override returns (bool) {
        counter++;
        return true;
    }
}