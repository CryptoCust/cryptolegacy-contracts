/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

contract MultiPermit {

  constructor() {

  }

  /**
   * @notice Data structure used to pass token permit parameters.
   * @dev Used by approveTreasuryTokensToLegacy to authorize spending without on‑chain approval transactions.
   * @param token The ERC20 token contract address.
   * @param owner The token owner address.
   * @param spender The address allowed to spend the tokens.
   * @param value The token amount to approve.
   * @param deadline The expiration timestamp of the permit.
   * @param v The recovery byte of the signature.
   * @param r Half of the ECDSA signature pair.
   * @param s Half of the ECDSA signature pair.
   */
  struct PermitData {
    address token;
    address owner;
    address spender;
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  /**
   * @notice Executes permit approvals on multiple tokens in a single transaction.
   * @dev Iterates through the array of PermitData and calls permit() on each corresponding token contract.
   * @param _permits An array of PermitData structures containing the necessary parameters for each permit.
   */
  function approveTreasuryTokensToLegacy(PermitData[] memory _permits) external {
    for (uint i = 0; i < _permits.length; i++) {
      PermitData memory p = _permits[i];
      IERC20Permit(p.token).permit(p.owner, p.spender, p.value, p.deadline, p.v, p.r, p.s);
    }
  }
}
