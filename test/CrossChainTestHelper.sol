// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/mocks/MockDeBridgeGate.sol";
import "./AbstractTestHelper.sol";
import "forge-std/Test.sol";

abstract contract CrossChainTestHelper is AbstractTestHelper {
  uint256 internal deBridgeFee;

  FeeRegistry internal mainLock;
  FeeRegistry internal sideLock1;
  FeeRegistry internal sideLock2;
  FeeRegistry internal sideLock3;
  MockCallProxy internal mockCallProxy;
  MockDeBridgeGate internal mockDeBridgeGate;

  uint256 constant internal MAIN_CHAIN_ID = 31337;
  uint256 constant internal SIDE_CHAIN_ID_1 = 2;
  uint256 constant internal SIDE_CHAIN_ID_2 = 42;
  uint256 constant internal SIDE_CHAIN_ID_3 = 4242;

  // Assume a lock period (for unlocking on the main chain) of 60 seconds.
  uint256 constant internal LOCK_PERIOD = 60;

  function setUp() public virtual override {
    super.setUp();

    mockCallProxy = new MockCallProxy();
    mockDeBridgeGate = new MockDeBridgeGate(mockCallProxy);
    mainLock = feeRegistry;

    vm.startPrank(owner);
    pluginsRegistry.addPlugin(cryptoLegacyBasePlugin, "");

    feeRegistry.setLockOperator(address(buildManager), true);

    mainLock.setCustomChainId(MAIN_CHAIN_ID);
    sideLock1 = LibDeploy._deployFeeRegistry(bytes32(uint256(2)), bytes32(uint256(2)), owner, proxyBuilder, uint32(0), uint32(0), lifetimeNft, 60);
    sideLock1.setCustomChainId(SIDE_CHAIN_ID_1);
    sideLock1.setDefaultPct(uint32(refDiscountPct), uint32(refSharePct));

    sideLock2 = LibDeploy._deployFeeRegistry(bytes32(uint256(3)), bytes32(uint256(3)), owner, proxyBuilder, uint32(0), uint32(0), lifetimeNft, 60);
    sideLock2.setCustomChainId(SIDE_CHAIN_ID_2);
    sideLock2.setDefaultPct(uint32(refDiscountPct), uint32(refSharePct));

    sideLock3 = LibDeploy._deployFeeRegistry(bytes32(uint256(4)), bytes32(uint256(4)), owner, proxyBuilder, uint32(0), uint32(0), lifetimeNft, 60);
    sideLock3.setCustomChainId(SIDE_CHAIN_ID_3);
    sideLock3.setDefaultPct(uint32(refDiscountPct), uint32(refSharePct));

    mainLock.setDebridgeGate(address(mockDeBridgeGate));
    sideLock1.setDebridgeGate(address(mockDeBridgeGate));
    sideLock2.setDebridgeGate(address(mockDeBridgeGate));
    sideLock3.setDebridgeGate(address(mockDeBridgeGate));

    mainLock.setSourceAndDestinationChainContract(SIDE_CHAIN_ID_1, address(sideLock1));
    mainLock.setSourceAndDestinationChainContract(SIDE_CHAIN_ID_2, address(sideLock2));
    mainLock.setSourceAndDestinationChainContract(SIDE_CHAIN_ID_3, address(sideLock3));
    sideLock1.setSourceAndDestinationChainContract(MAIN_CHAIN_ID, address(mainLock));
    sideLock2.setSourceAndDestinationChainContract(MAIN_CHAIN_ID, address(mainLock));
    sideLock3.setSourceAndDestinationChainContract(MAIN_CHAIN_ID, address(mainLock));
    vm.stopPrank();

    deBridgeFee = mockDeBridgeGate.globalFixedNativeFee();
  }

  function _checkDeBridgeCallData(bytes memory _data) internal view {
//        emit log_bytes(_data);
//        emit log_bytes(mockDeBridgeGate.targetContractCalldata());
    assertEq(
      keccak256(abi.encodePacked(mockDeBridgeGate.targetContractCalldata())),
      keccak256(abi.encodePacked(_data))
    );
  }
}
