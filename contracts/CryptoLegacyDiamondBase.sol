/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

pragma solidity 0.8.24;

import "./libraries/LibDiamond.sol";
import "./interfaces/ICryptoLegacy.sol";
import "./libraries/LibCryptoLegacy.sol";
import "./libraries/DiamondLoupeFacet.sol";
import "./libraries/LibCryptoLegacyPlugins.sol";
import "./interfaces/ICryptoLegacyDiamondBase.sol";

/**
 * @title CryptoLegacyDiamondBase
 * @notice Base contract implementing a fallback function for delegate-calls to facets, per EIP-2535 Diamond Standard.
 */
contract CryptoLegacyDiamondBase is ICryptoLegacyDiamondBase, DiamondLoupeFacet {

    /**
     * @notice A checker function to detect whether a call is static or not.
     * @dev Reverts if not called by the contract itself. This is used by fallback logic to determine call type.
     */
    function staticCallChecker() external {
        if (msg.sender != address(this)) {
            revert NotSelfCall();
        }
        emit StaticCallCheck();
    }
    /**
     * @notice Fallback function that delegates calls to the appropriate facet.
     * @dev Retrieves the facet address corresponding to the caller’s function selector.
     *      - If the facet address is zero, attempts a low‑gas event emitting to check is it static call.
     *      - If a facet is found via the plugins library and the call is not static, caches the facet address.
     *      - Reverts with {FunctionNotExists} if no facet address is found.
     *      Uses assembly to perform a delegatecall to the found facet with full calldata forwarding.
     *      Any revert from the delegated call is bubbled to the caller.
     */
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        if (facet == address(0)) {
            ICryptoLegacy.CryptoLegacyStorage storage cls = LibCryptoLegacy.getCryptoLegacyStorage();

            bool isStaticCall = false;
            try this.staticCallChecker{gas: 1e5 * uint(cls.gasLimitMultiplier == 0 ? 1 : cls.gasLimitMultiplier)}() {} catch {
                isStaticCall = true;
            }
            facet = LibCryptoLegacyPlugins._findFacetBySelector(ds, msg.sig);
            if (facet != address(0) && !isStaticCall) {
                ds.selectorToFacetAndPosition[msg.sig].facetAddress = facet;
            }
        }

        if (facet == address(0)) {
            revert FunctionNotExists(msg.sig);
        }
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
