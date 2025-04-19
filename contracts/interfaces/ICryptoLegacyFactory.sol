/*
* Copyright (c) 2024 CryptoCustoms. All Rights Reserved.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ICryptoLegacy.sol";
import {stdMath} from "../../lib/forge-std/src/StdMath.sol";

interface ICryptoLegacyFactory {
    event AddBuildOperator(address indexed buildOperator);
    event RemoveBuildOperator(address indexed buildOperator);

    struct Create2Args {
        address create2Address;
        bytes32 create2Salt;
    }

    function createCryptoLegacy(
        address _owner,
        address[] memory _plugins,
        Create2Args memory _create2Args
    ) external returns(address payable);

    function setBuildOperator(address _operator, bool _isAdd) external;

    error NotBuildOperator();
}
