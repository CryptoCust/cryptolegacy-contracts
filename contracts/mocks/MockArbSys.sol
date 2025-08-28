pragma solidity 0.8.24;

contract MockArbSys {
    function arbBlockNumber() external view returns (uint) {
        return block.number;
    }
}
