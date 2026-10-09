// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SPEPEToken} from "../src/SPEPEToken.sol";

/// @notice Local simulation / network-operator deployment only; production launch is factory-driven.
contract Deploy is Script {
    function run() external returns (SPEPEToken token) {
        uint256 expected = vm.envUint("EXPECTED_CHAIN_ID");
        require(block.chainid == 31337 || block.chainid == 4663, "unsupported chain");
        require(expected == block.chainid || (expected == 0 && block.chainid == 31337), "chain mismatch");
        vm.startBroadcast();
        token = new SPEPEToken();
        vm.stopBroadcast();
    }
}
