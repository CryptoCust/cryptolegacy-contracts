/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

contract MockPayable {
    bool public payableActive;
    uint256 public received;

    constructor(bool _payableActive) {
        payableActive = _payableActive;
    }

    receive() external payable {
        if (!payableActive) {
            revert();
        }
        received += msg.value;
    }

    function setPayableActive(bool _payableActive) public {
        payableActive = _payableActive;
    }
}