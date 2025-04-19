// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockERC20Faucet is Ownable {
    struct TokenInfo {
        IERC20 token;
        uint256 amount; // Amount per claim
    }

    TokenInfo[] public tokens;
    mapping(address => uint256) public lastClaim;
    uint256 public cooldown = 1 hours; // Default 1-hour cooldown

    event TokensClaimed(address indexed user);
    event TokensAdded(address[] tokens, uint256 amount);
    event TokenAmountUpdated(uint256 index, uint256 newAmount);
    event CooldownUpdated(uint256 newCooldown);

    constructor() {}

    /**
     * @dev Add multiple tokens to the faucet at once.
     * @param tokenAddresses List of ERC20 token addresses.
     * @param amount Corresponding claim amounts for each token.
     */
    function addTokens(address[] calldata tokenAddresses, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            require(tokenAddresses[i] != address(0), "Invalid token address");
            tokens.push(TokenInfo(IERC20(tokenAddresses[i]), amount));
        }
        emit TokensAdded(tokenAddresses, amount);
    }

    function mintTokens(address[] calldata tokenAddresses, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            MockERC20(tokenAddresses[i]).mint(address(this), amount);
        }
    }

    /**
     * @dev Allows users to claim tokens, enforcing cooldown.
     */
    function claimTokens() external {
        require(block.timestamp >= lastClaim[msg.sender] + cooldown, "Claim cooldown active");

        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].token.transfer(msg.sender, tokens[i].amount);
        }

        lastClaim[msg.sender] = block.timestamp;
        emit TokensClaimed(msg.sender);
    }

    /**
     * @dev Update the claim amount for a specific token.
     * @param index Index of the token in the array.
     * @param newAmount New claim amount.
     */
    function updateTokenAmount(uint256 index, uint256 newAmount) external onlyOwner {
        require(index < tokens.length, "Invalid index");
        tokens[index].amount = newAmount;
        emit TokenAmountUpdated(index, newAmount);
    }

    /**
     * @dev Owner can withdraw any excess tokens from the faucet.
     * @param index Index of the token in the array.
     * @param amount Amount to withdraw.
     */
    function withdrawTokens(uint256 index, uint256 amount) external onlyOwner {
        require(index < tokens.length, "Invalid index");
        tokens[index].token.transfer(msg.sender, amount);
    }

    /**
     * @dev Owner can change the cooldown period.
     * @param newCooldown New cooldown time in seconds.
     */
    function setCooldown(uint256 newCooldown) external onlyOwner {
        cooldown = newCooldown;
        emit CooldownUpdated(newCooldown);
    }

    /**
     * @dev Returns all tokens with their claim amounts.
     */
    function getTokens() external view returns (TokenInfo[] memory) {
        return tokens;
    }
}
