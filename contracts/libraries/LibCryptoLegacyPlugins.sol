/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/
pragma solidity 0.8.24;

import "./LibDiamond.sol";
import "../interfaces/ICryptoLegacy.sol";
import "../interfaces/ICryptoLegacyPlugin.sol";

library LibCryptoLegacyPlugins {
    /**
     * @notice Validates that a given plugin is registered with the build manager.
     * @dev Uses the isPluginRegistered() method on the buildManager of _cls.
     * Reverts with ICryptoLegacy.PluginNotRegistered if the plugin is not registered.
     * @param _cls The CryptoLegacy storage structure which contains the build manager reference.
     * @param _plugin The address of the plugin to validate.
     */
    function _validatePlugin(ICryptoLegacy.CryptoLegacyStorage storage _cls, address _plugin) internal view {
        if (!_cls.buildManager.isPluginRegistered(_plugin)) {
            revert ICryptoLegacy.PluginNotRegistered();
        }
    }

    /**
     * @notice Adds a list of plugins and their associated functions to the diamond.
     * @dev Iterates over each plugin address in the _plugins array. For each, it first validates the plugin,
     * then retrieves its setup function selectors by calling getSetupSigs(), and finally adds these selectors
     * to the diamond by calling addFunctions().
     * @param _cls The CryptoLegacy storage structure.
     * @param _plugins The array of plugin addresses to be added.
     */
    function _addPluginList(ICryptoLegacy.CryptoLegacyStorage storage _cls, address[] memory _plugins) internal {
        for (uint256 i = 0; i < _plugins.length; i++) {
            _validatePlugin(_cls, _plugins[i]);
            bytes4[] memory functionSelectors = ICryptoLegacyPlugin(_plugins[i]).getSetupSigs();
            addFunctions(_plugins[i], functionSelectors);
        }
    }

    /**
     * @notice Removes a plugin from the diamond by removing its functions.
     * @dev Calls removeFunctions() with the plugin address and the set of selectors returned by getSigs().
     * @param _plugin The plugin contract from which to remove functions.
     */
    function _removePlugin(ICryptoLegacyPlugin _plugin) internal {
        removeFunctions(address(_plugin), _plugin.getSigs());
    }

    /**
     * @notice Retrieves the index position of a facet address within the diamond storage.
     * @dev Iterates over ds.facetAddresses to find a match for _facetAddress.
     * Reverts with ICryptoLegacy.FacetNotFound if the facet address is not present.
     * @param ds The Diamond storage structure.
     * @param _facetAddress The facet address to locate.
     * @return The index position of the facet address in ds.facetAddresses.
     */
    function _getFacetAddressPosition(LibDiamond.DiamondStorage storage ds, address _facetAddress) private view returns(uint256) {
        uint256 length = ds.facetAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            if (ds.facetAddresses[i] == _facetAddress) {
                return i;
            }
        }
        revert ICryptoLegacy.FacetNotFound();
    }

    /**
     * @notice Adds a facet address to the diamond storage if it is not already present.
     * @dev Iterates over ds.facetAddresses; if _facetAddress is not found, enforces that the address contains contract code
     * using LibDiamond.enforceHasContractCode() and then pushes it to the facet addresses array.
     * @param ds The Diamond storage structure.
     * @param _facetAddress The facet address to be added.
     */
    function _addFacetAddressIfNotExists(LibDiamond.DiamondStorage storage ds, address _facetAddress) private {
        uint256 length = ds.facetAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            if (ds.facetAddresses[i] == _facetAddress) {
                return;
            }
        }
        LibDiamond.enforceHasContractCode(_facetAddress, "NO_CODE");
        ds.facetAddresses.push(_facetAddress);
    }

    /**
     * @notice Removes a facet address from the diamond storage.
     * @dev Retrieves the facet address position using _getFacetAddressPosition(). If the facet is not the last element,
     * it swaps it with the last element in the array before removing the last entry with pop().
     * @param ds The Diamond storage structure.
     * @param _facetAddress The facet address to be removed.
     */
    function _removeFacetAddress(LibDiamond.DiamondStorage storage ds, address _facetAddress) private {
        uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
        uint256 facetAddressPosition = _getFacetAddressPosition(ds, _facetAddress);
        if (facetAddressPosition != lastFacetAddressPosition) {
            address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
            ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
        }
        ds.facetAddresses.pop();
    }

    /**
     * @notice Adds function selectors from a facet to the diamond.
     * @dev Validates that _facetAddress is not the zero address and then ensures it is added to the diamond storage.
     * For each selector in _functionSelectors, checks that it does not already map to an existing facet.
     * Reverts with ICryptoLegacy.FacetCantBeZero or ICryptoLegacy.CantAddFunctionThatAlreadyExists if conditions fail.
     * Finally, emits an AddFunctions event (the event documentation is not repeated here).
     * @param _facetAddress The address of the facet that provides the functions.
     * @param _functionSelectors An array of function selectors (bytes4) to be added.
     */
    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        // uint16 selectorCount = uint16(diamondStorage().selectors.length);
        if (_facetAddress == address(0)) {
            revert ICryptoLegacy.FacetCantBeZero();
        }
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        _addFacetAddressIfNotExists(ds, _facetAddress);

        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            if (ds.selectorToFacetAndPosition[selector].facetAddress != address(0)) {
                revert ICryptoLegacy.CantAddFunctionThatAlreadyExists();
            }
            ds.selectorToFacetAndPosition[selector].facetAddress = _facetAddress;
        }

        emit ICryptoLegacy.AddFunctions(_facetAddress, _functionSelectors, uint16(0));
    }

    /**
     * @notice Removes function selectors from a facet within the diamond.
     * @dev Checks that _facetAddress is not zero and is not the current (immutable) contract.
     * Calls _removeFacetAddress() to remove the facet address, then iterates over _functionSelectors to delete their mappings.
     * Reverts with ICryptoLegacy.FacetCantBeZero or ICryptoLegacy.CantRemoveImmutableFunctions if conditions are not met.
     * @param _facetAddress The facet address from which functions are to be removed.
     * @param _functionSelectors An array of function selectors (bytes4) to be removed.
     */
    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (_facetAddress == address(0)) {
            revert ICryptoLegacy.FacetCantBeZero();
        }
        // an immutable function is a function defined directly in a diamond
        if (_facetAddress == address(this)) {
            revert ICryptoLegacy.CantRemoveImmutableFunctions();
        }
        _removeFacetAddress(ds, _facetAddress);
        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            delete ds.selectorToFacetAndPosition[_functionSelectors[i]];
        }
        emit ICryptoLegacy.RemoveFunctions(_facetAddress, _functionSelectors);
    }

    /**
     * @notice Finds the facet address that implements a given function selector.
     * @dev Iterates over all facet addresses stored in ds. For each, it retrieves the signature list using getSigs()
     * from the plugin interface and checks if _selector matches any of them.
     * @param ds The Diamond storage structure.
     * @param _selector The function selector (bytes4) to search for.
     * @return facetAddress The facet address that provides the function matching _selector.
     * If no match is found, returns the zero address.
     */
    function _findFacetBySelector(LibDiamond.DiamondStorage storage ds, bytes4 _selector) internal view returns(address facetAddress) {
        for (uint256 i = 0; i < ds.facetAddresses.length; i++) {
            bytes4[] memory sigs = ICryptoLegacyPlugin(ds.facetAddresses[i]).getSigs();
            for (uint256 j = 0; j < sigs.length; j++) {
                if (_selector == sigs[j]) {
                    facetAddress = ds.facetAddresses[i];
                }
            }
        }
    }
}