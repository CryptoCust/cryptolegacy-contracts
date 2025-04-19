/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../plugins/CryptoLegacyBasePlugin.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockMaliciousERC721 is ERC721, Ownable {
    address public targetContract; // The contract to re-enter
    bool public isReentering; // Flag to prevent infinite loops

    constructor(address _targetContract) ERC721("MaliciousNFT", "MNFT") Ownable() {
        targetContract = _targetContract;
        _mint(msg.sender, 1); // Mint an initial token
    }

    // Override the transferFrom function to re-enter the target contract
    function transferFrom(address from, address to, uint256 tokenId) public override {
        if (!isReentering && to == targetContract) {
            isReentering = true;
            (bool success, bytes memory returnData) = to.call(abi.encodeWithSelector(CryptoLegacyBasePlugin.beneficiaryClaim.selector, new address[](1), address(0), 0));
            // Parse the revert data to extract the error message
            string memory revertMessage;
            if (returnData.length > 0) {
                // Manually extract the revert message starting from byte 4
                bytes memory messageData = new bytes(returnData.length - 4);
                for (uint256 i = 4; i < returnData.length; i++) {
                    messageData[i - 4] = returnData[i];
                }
                // Decode the message data into a string
                revertMessage = abi.decode(messageData, (string));
            }
            // Compare the parsed revert message with the expected message
            require(success, revertMessage);
            isReentering = false;
        }
        super.transferFrom(from, to, tokenId);
    }

    // Override the safeTransferFrom function to re-enter the target contract
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override {
        if (!isReentering && to == targetContract) {
            isReentering = true;
            (bool success, bytes memory returnData) = to.call(abi.encodeWithSelector(CryptoLegacyBasePlugin.beneficiaryClaim.selector, new address[](1), address(0), 0));
            string memory revertMessage;
            if (returnData.length > 0) {
                // Manually extract the revert message starting from byte 4
                bytes memory messageData = new bytes(returnData.length - 4);
                for (uint256 i = 4; i < returnData.length; i++) {
                    messageData[i - 4] = returnData[i];
                }
                // Decode the message data into a string
                revertMessage = abi.decode(messageData, (string));
            }
            // Compare the parsed revert message with the expected message
            require(success, revertMessage);
            isReentering = false;
        }
        super.safeTransferFrom(from, to, tokenId, _data);
    }
}