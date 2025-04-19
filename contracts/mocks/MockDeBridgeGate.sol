pragma solidity 0.8.24;

import "../interfaces/IDeBridgeGate.sol";
import "./MockCallProxy.sol";

contract MockDeBridgeGate is IDeBridgeGate {
    MockCallProxy public callProxyInstance;
    uint256 public counter;
    address public targetContractAddress;
    bytes public targetContractCalldata;

    uint256 public constant ADDRESS_LENGTH = 0x14;

    event SentMessage(uint256 chainId, uint256 value);

    constructor(MockCallProxy _callProxy) {
        callProxyInstance = _callProxy;
    }
    function sendMessage(
        uint256 _dstChainId,
        bytes memory _targetContractAddress,
        bytes memory _targetContractCalldata,
        uint256,
        uint32
    ) external payable override returns (bytes32 submissionId) {
        submissionId = keccak256(abi.encode(msg.sender, _dstChainId, _targetContractCalldata));
        address addr;
        assembly {
            addr := mload(add(_targetContractAddress, ADDRESS_LENGTH))
        }
        targetContractAddress = addr;
        targetContractCalldata = _targetContractCalldata;
        emit SentMessage(_dstChainId, msg.value);
    }
    function executeLastMessage() external {
        callProxyInstance.callMessage(targetContractAddress, targetContractCalldata);
    }
    function callProxy() external view override returns (address) {
        return address(callProxyInstance);
    }
    function globalFixedNativeFee() external pure override returns (uint256) {
        return 0.01 ether;
    }
    function globalTransferFeeBps() external pure override returns (uint16) {
        return 100;
    }
    function getDebridgeChainAssetFixedFee(
        bytes32,
        uint256
    ) external pure override returns (uint256) {
        return 0.01 ether;
    }

    function isSubmissionUsed(bytes32) pure external returns (bool) {
        return true;
    }

    function getNativeInfo(address) pure external returns (
        uint256 nativeChainId,
        bytes memory nativeAddress) {
        return(0, new bytes(0));
    }

    function sendMessage(
        uint256,
        bytes memory,
        bytes memory
    ) external payable returns (bytes32 submissionId) {
        counter++;
        return 0;
    }

    function send(
        address,
        uint256,
        uint256,
        bytes memory,
        bytes memory,
        bool,
        uint32,
        bytes calldata
    ) external payable returns (bytes32 submissionId) {
        counter++;
        return 0;
    }

    function claim(
        bytes32,
        uint256,
        uint256,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external {
        counter++;
    }

    function withdrawFee(bytes32) external {
        counter++;
    }
}