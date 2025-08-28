/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./interfaces/ArbSys.sol";
import "./BuildManagerOwnable.sol";
import "./interfaces/ILegacyMessenger.sol";

/**
 * @title LegacyMessenger
 * @notice Forwards messages to beneficiaries and logs message block numbers.
 */
contract LegacyMessenger is ILegacyMessenger, BuildManagerOwnable {

  mapping(bytes32 => uint64[]) public messagesGotByBlockNumber;

  constructor(address _owner) BuildManagerOwnable() {
    _transferOwnership(_owner);
  }

  /**
   * @notice Sends messages to a list of recipients.
   * @param _cryptoLegacy The CryptoLegacy contract address.
   * @param _recipientList Array of recipient hashes.
   * @param _messageHashList Array of message hashes.
   * @param _messageList Array of message bytes.
   * @param _messageCheckList Array of message check bytes.
   * @param _messageType The type identifier for the messages.
   */
  function sendMessagesTo(
    address _cryptoLegacy,
    bytes32[] memory _recipientList,
    bytes32[] memory _messageHashList,
    bytes[] memory _messageList,
    bytes[] memory _messageCheckList,
    uint256 _messageType
  ) public {
    _checkBuildManagerValid(_cryptoLegacy, msg.sender);

    for (uint256 i = 0; i < _recipientList.length; i++) {
      emit LegacyMessage(_cryptoLegacy, _recipientList[i], _messageHashList[i], _messageList[i], _messageType);
      emit LegacyMessageCheck(_cryptoLegacy, _recipientList[i], _messageHashList[i], _messageCheckList[i], _messageType);
      messagesGotByBlockNumber[_recipientList[i]].push(uint64(block.chainid == 42161 ? ArbSys(address(100)).arbBlockNumber() : block.number));
    }
  }


  /**
   * @notice Returns the block numbers at which messages were received for a given recipient.
   * @param _recipient The recipient hash.
   * @return blockNumbers Array of block numbers.
   */
  function getMessagesBlockNumbersByRecipient(bytes32 _recipient) external view returns(uint64[] memory blockNumbers) {
    return messagesGotByBlockNumber[_recipient];
  }
}
