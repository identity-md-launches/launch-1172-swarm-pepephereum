// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SPEPEToken} from "../src/SPEPEToken.sol";

contract SPEPEHandler is Test {
    SPEPEToken public token;
    address[5] public actors;

    constructor() {
        token = new SPEPEToken();
        actors =
            [address(this), makeAddr("holder one"), makeAddr("holder two"), token.POOL_MANAGER(), token.TAX_WALLET()];
    }

    function move(uint256 fromIndex, uint256 toIndex, uint256 rawAmount, bool delegated, bool unlimited) external {
        address from = actors[fromIndex % 5];
        address to = actors[toIndex % 5];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        uint256[5] memory expected;
        for (uint256 i; i < 5; ++i) {
            expected[i] = token.balanceOf(actors[i]);
        }
        uint256 tax = fromIndex % 5 == 3 && toIndex % 5 != 3 ? amount / 50 : 0;
        expected[fromIndex % 5] -= amount;
        expected[toIndex % 5] += amount - tax;
        expected[4] += tax;
        if (delegated) {
            vm.prank(from);
            token.approve(address(this), unlimited ? type(uint256).max : amount);
            token.transferFrom(from, to, amount);
            assertEq(token.allowance(from, address(this)), unlimited ? type(uint256).max : 0);
        } else {
            vm.prank(from);
            token.transfer(to, amount);
        }
        for (uint256 i; i < 5; ++i) {
            assertEq(token.balanceOf(actors[i]), expected[i], "unexpected holder balance");
        }
    }
}

contract SPEPEInvariantTest is Test {
    SPEPEHandler internal handler;
    SPEPEToken internal token;

    function setUp() public {
        handler = new SPEPEHandler();
        token = handler.token();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = SPEPEHandler.move.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
