/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

interface ILido {
    function submit(address _referral) external payable returns (uint256);
    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);
    function transferSharesFrom(address _sender, address _recipient, uint256 _sharesAmount) external returns (uint256);
    function sharesOf(address _account) external view returns (uint256);
}
