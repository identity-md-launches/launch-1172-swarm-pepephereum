// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SPEPEToken} from "../src/SPEPEToken.sol";
import {PairFixture, PoolHarness} from "./support/PoolHarness.sol";

abstract contract SPEPEPoolChecks is Test {
    address internal constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant PAIR = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address internal constant TAX = 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193;
    uint256 internal constant SUPPLY = 1e27;
    SPEPEToken internal token;
    IPoolManager internal manager;
    PoolHarness internal lp;
    PoolHarness internal trader;
    PoolKey internal key;
    bool internal tokenIsZero;
    int24 internal lower;
    int24 internal upper;

    function _prepare(bool offline) internal {
        token = new SPEPEToken();
        manager = IPoolManager(MANAGER);
        lp = new PoolHarness(manager);
        trader = new PoolHarness(manager);
        tokenIsZero = address(token) < PAIR;
        key = PoolKey(
            Currency.wrap(tokenIsZero ? address(token) : PAIR),
            Currency.wrap(tokenIsZero ? PAIR : address(token)),
            12500,
            60,
            IHooks(address(0))
        );
        // 1000 IMD / 1e9 SPEPE = 1e-6 IMD per SPEPE, accounting for actual currency order.
        uint160 sqrtPrice = tokenIsZero ? 79228162514264337593543950 : 79228162514264337593543950336000;
        manager.initialize(key, sqrtPrice);
        lower = tokenIsZero ? int24(-138120) : int24(-887220);
        upper = tokenIsZero ? int24(887220) : int24(138120);
        token.transfer(makeAddr("swarm distributor"), SUPPLY / 10);
        token.transfer(address(lp), SUPPLY * 9 / 10);
        lp.seed(key, lower, upper, 8e23);
        uint256 seeded = token.balanceOf(MANAGER);
        assertGt(seeded, 0);
        assertLe(seeded, SUPPLY * 9 / 10);
        assertEq(token.balanceOf(TAX), 0, "seed must be untaxed");
        assertEq(token.balanceOf(address(lp)) + seeded, SUPPLY * 9 / 10);
        if (offline) assertEq(PairFixture(PAIR).balanceOf(MANAGER), 0, "seed must be single-sided");
        if (offline) PairFixture(PAIR).mint(address(trader), 100 ether);
        else deal(PAIR, address(trader), 100 ether);
    }

    function _roundTrip(uint256 amountIn) internal {
        uint256 pairBefore = PairFixture(PAIR).balanceOf(address(trader));
        uint256 managerBefore = token.balanceOf(MANAGER);
        uint256 taxBefore = token.balanceOf(TAX);
        BalanceDelta buy = trader.swap(key, !tokenIsZero, -int256(amountIn));
        int128 outDelta = tokenIsZero ? buy.amount0() : buy.amount1();
        assertGt(outDelta, 0);
        uint256 gross = uint256(int256(outDelta));
        uint256 net = token.balanceOf(address(trader));
        assertEq(token.balanceOf(TAX) - taxBefore, gross / 50);
        assertEq(net, gross - gross / 50);
        assertEq(managerBefore - token.balanceOf(MANAGER), gross);
        assertEq(pairBefore - PairFixture(PAIR).balanceOf(address(trader)), amountIn);

        uint256 managerAfterBuy = token.balanceOf(MANAGER);
        uint256 taxAfterBuy = token.balanceOf(TAX);
        uint256 pairAfterBuy = PairFixture(PAIR).balanceOf(address(trader));
        BalanceDelta sell = trader.swap(key, tokenIsZero, -int256(net));
        int128 inDelta = tokenIsZero ? sell.amount0() : sell.amount1();
        assertEq(-int256(inDelta), int256(net));
        assertEq(token.balanceOf(address(trader)), 0, "all net tokens must be sellable");
        assertEq(token.balanceOf(MANAGER) - managerAfterBuy, net, "sell must settle its full debt");
        assertEq(token.balanceOf(TAX), taxAfterBuy, "sell must not pay tax");
        assertGt(PairFixture(PAIR).balanceOf(address(trader)), pairAfterBuy);
        assertLt(PairFixture(PAIR).balanceOf(address(trader)), pairBefore);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

contract SPEPEPoolTest is SPEPEPoolChecks {
    function setUp() public {
        vm.chainId(4663);
        // Execute creation code at the fixed address so v4's noDelegateCall immutable is correct.
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = MANAGER.call("");
        require(ok && runtime.length > 0, "manager construction failed");
        vm.etch(MANAGER, runtime);
        vm.etch(PAIR, address(new PairFixture()).code);
        _prepare(true);
    }

    function test_RealV4SingleSidedSeedBuyAndSell() public {
        _roundTrip(0.01 ether);
    }

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_RealV4BuyAndSell(uint256 amountIn) public {
        _roundTrip(bound(amountIn, 0.000001 ether, 10 ether));
    }

    function test_ExactOutputQuoteIsGrossAndBuyerReceivesNet() public {
        uint256 wantedGross = 1000 ether;
        BalanceDelta buy = trader.swap(key, !tokenIsZero, int256(wantedGross));
        assertEq(int256(tokenIsZero ? buy.amount0() : buy.amount1()), int256(wantedGross));
        assertEq(token.balanceOf(address(trader)), 980 ether);
        assertEq(token.balanceOf(TAX), 20 ether);
    }

    function test_LiquidityWithdrawalAlsoUsesFromManagerRule() public {
        uint256 lpBefore = token.balanceOf(address(lp));
        uint256 managerBefore = token.balanceOf(MANAGER);
        BalanceDelta withdrawn = lp.seed(key, lower, upper, -int256(8e23));
        uint256 gross = uint256(int256(tokenIsZero ? withdrawn.amount0() : withdrawn.amount1()));
        assertGt(gross, 0);
        assertEq(token.balanceOf(address(lp)) - lpBefore, gross - gross / 50);
        assertEq(token.balanceOf(TAX), gross / 50);
        assertEq(managerBefore - token.balanceOf(MANAGER), gross);
        assertEq(token.totalSupply(), SUPPLY);
    }
}

/// @notice Optional live-state test. No RPC URL is committed; offline verification skips cleanly.
contract SPEPEForkTest is SPEPEPoolChecks {
    function testFork_RobinhoodV4SeedBuyAndSell() public {
        string memory rpc = vm.envOr("ROBINHOOD_FORK_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        uint256 pinnedBlock = vm.envUint("ROBINHOOD_FORK_BLOCK");
        require(pinnedBlock > 0, "pin a fork block");
        vm.createSelectFork(rpc, pinnedBlock);
        assertEq(block.chainid, 4663);
        assertGt(MANAGER.code.length, 0, "manager missing on selected chain");
        assertGt(PAIR.code.length, 0, "IMD missing on selected chain");
        assertEq(PairFixture(PAIR).symbol(), "IMD");
        assertEq(PairFixture(PAIR).decimals(), 18);
        _prepare(false);
        _roundTrip(0.01 ether);
    }
}
