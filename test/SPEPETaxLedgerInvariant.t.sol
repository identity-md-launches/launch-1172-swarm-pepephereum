// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SPEPEToken} from "../src/SPEPEToken.sol";

/// @dev Random transfers, delegated transfers, overdrafts and over-allowance attempts between six
/// actors, with a ghost ledger of what the tax rule should have charged. Expected reverts are caught
/// so that fail-on-revert stays on for everything the handler did not intend to fail.
contract TaxLedgerHandler is Test {
    SPEPEToken public immutable token;
    address public immutable MANAGER;
    address public immutable TAX;
    address[6] public actors;

    uint256 public ghostTax;
    uint256 public ghostGrossFromManager;
    uint256 public ghostNetFromManager;
    uint256 public ghostUntaxedIntoTaxWallet;
    uint256 public ghostOutOfTaxWallet;
    uint256 public taxedTransfers;
    uint256 public rejectedOverdrafts;
    uint256 public rejectedOverspends;

    constructor() {
        token = new SPEPEToken();
        MANAGER = token.POOL_MANAGER();
        TAX = token.TAX_WALLET();
        actors = [address(this), makeAddr("holder a"), makeAddr("holder b"), makeAddr("holder c"), MANAGER, TAX];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 6];
        address to = actors[toSeed % 6];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        vm.prank(from);
        require(token.transfer(to, amount), "transfer returned false");
        _record(from, to, amount);
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount, bool unlimited)
        external
    {
        address from = actors[fromSeed % 6];
        address spender = actors[spenderSeed % 6];
        address to = actors[toSeed % 6];
        uint256 amount = bound(rawAmount, 0, token.balanceOf(from));
        vm.prank(from);
        token.approve(spender, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        require(token.transferFrom(from, to, amount), "transferFrom returned false");
        assertEq(token.allowance(from, spender), unlimited ? type(uint256).max : 0, "allowance consumed on gross");
        _record(from, to, amount);
    }

    function overdraft(uint256 fromSeed, uint256 toSeed, uint256 rawExcess) external {
        address from = actors[fromSeed % 6];
        address to = actors[toSeed % 6];
        uint256 balance = token.balanceOf(from);
        uint256 amount = balance + bound(rawExcess, 1, 1e27);
        uint256[6] memory before = _snapshot();
        vm.prank(from);
        try token.transfer(to, amount) {
            revert("an overdraft must not succeed");
        } catch {
            ++rejectedOverdrafts;
        }
        _assertUnchanged(before);
    }

    function overspend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % 6];
        address spender = actors[spenderSeed % 6];
        address to = actors[toSeed % 6];
        uint256 amount = bound(rawAmount, 1, token.balanceOf(from) == 0 ? 1 : token.balanceOf(from));
        vm.prank(from);
        token.approve(spender, amount - 1);
        uint256[6] memory before = _snapshot();
        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            revert("spending above the allowance must not succeed");
        } catch {
            ++rejectedOverspends;
        }
        _assertUnchanged(before);
        assertEq(token.allowance(from, spender), amount - 1, "a failed transferFrom must not touch the allowance");
    }

    function _record(address from, address to, uint256 amount) private {
        if (from == MANAGER && to != MANAGER) {
            uint256 tax = amount / 50;
            ghostTax += tax;
            ghostGrossFromManager += amount;
            ghostNetFromManager += amount - tax;
            if (to == TAX) ghostUntaxedIntoTaxWallet += amount - tax;
            if (tax != 0) ++taxedTransfers;
        } else {
            if (to == TAX && from != TAX) ghostUntaxedIntoTaxWallet += amount;
            if (from == TAX && to != TAX) ghostOutOfTaxWallet += amount;
        }
    }

    function _snapshot() private view returns (uint256[6] memory s) {
        for (uint256 i; i < 6; ++i) {
            s[i] = token.balanceOf(actors[i]);
        }
    }

    function _assertUnchanged(uint256[6] memory before) private view {
        for (uint256 i; i < 6; ++i) {
            assertEq(token.balanceOf(actors[i]), before[i], "a reverted call changed a balance");
        }
    }
}

contract SPEPETaxLedgerInvariantTest is Test {
    TaxLedgerHandler internal handler;
    SPEPEToken internal token;

    function setUp() public {
        handler = new TaxLedgerHandler();
        token = handler.token();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TaxLedgerHandler.transfer.selector;
        selectors[1] = TaxLedgerHandler.transferFrom.selector;
        selectors[2] = TaxLedgerHandler.overdraft.selector;
        selectors[3] = TaxLedgerHandler.overspend.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_TaxWalletHoldsExactlyWhatTheRuleCharged() public view {
        uint256 expected = handler.ghostTax() + handler.ghostUntaxedIntoTaxWallet() - handler.ghostOutOfTaxWallet();
        assertEq(token.balanceOf(handler.TAX()), expected, "tax wallet balance drifted from the ghost ledger");
        assertEq(
            handler.ghostGrossFromManager(),
            handler.ghostTax() + handler.ghostNetFromManager(),
            "gross debited from the manager must equal net delivered plus tax"
        );
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyIsConservedAcrossSuccessesAndRejections() public view {
        uint256 sum;
        for (uint256 i; i < 6; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, 1e27, "balances must sum to the fixed supply");
        assertEq(token.totalSupply(), 1e27, "supply must never change");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ParametersNeverChange() public view {
        assertEq(token.POOL_MANAGER(), 0x8366a39CC670B4001A1121B8F6A443A643e40951);
        assertEq(token.TAX_WALLET(), 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193);
        assertEq(token.BUY_TAX_BPS(), 200);
        assertEq(token.BPS_DENOMINATOR(), 10_000);
        assertEq(token.INITIAL_SUPPLY(), 1e27);
        assertEq(token.decimals(), 18);
    }
}

/// @notice The token's own ABI under random calldata from random senders, reverts allowed. Whatever
/// anyone calls, in any order, the supply and the fixed parameters do not move.
contract SPEPERawAbiInvariantTest is Test {
    SPEPEToken internal token;
    address internal constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant TAX = 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193;
    address internal holder = makeAddr("raw holder");

    function setUp() public {
        token = new SPEPEToken();
        token.transfer(MANAGER, 3e26);
        token.transfer(holder, 1e26);
        targetContract(address(token));
        targetSender(address(this));
        targetSender(MANAGER);
        targetSender(TAX);
        targetSender(holder);
        targetSender(makeAddr("raw stranger"));
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_RawCallsNeverChangeSupplyOrParameters() public view {
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.POOL_MANAGER(), MANAGER);
        assertEq(token.TAX_WALLET(), TAX);
        assertEq(token.BUY_TAX_BPS(), 200);
        assertEq(token.BPS_DENOMINATOR(), 10_000);
        assertEq(token.INITIAL_SUPPLY(), 1e27);
    }
}
