// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolManager} from "v4-core/src/PoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ProtocolFeeLibrary} from "v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {SPEPEPoolChecks} from "./SPEPEPool.t.sol";
import {PairFixture} from "./support/PoolHarness.sol";
import {ClaimsHarness} from "./support/ClaimsHarness.sol";

/// @notice The v4 paths a plain take-and-settle harness never drives: a pool with protocol fees on
/// top of its LP fee, outputs kept as ERC-6909 claims and redeemed later, outputs taken to a third
/// party, and a take-and-repay flash loan. Each one is an outbound ERC-20 transfer from the
/// PoolManager or a transfer into it, so each one must follow the same address-based rule and must
/// still leave v4's flash accounting balanced.
contract SPEPEClaimsAndFeesTest is SPEPEPoolChecks {
    ClaimsHarness internal claims;
    Currency internal spepe;
    Currency internal pair;

    function setUp() public {
        vm.chainId(4663);
        vm.etch(MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool ok, bytes memory runtime) = MANAGER.call("");
        require(ok && runtime.length > 0, "manager construction failed");
        vm.etch(MANAGER, runtime);
        vm.etch(PAIR, address(new PairFixture()).code);
        _prepare(true);
        claims = new ClaimsHarness(manager);
        PairFixture(PAIR).mint(address(claims), 100 ether);
        spepe = Currency.wrap(address(token));
        pair = Currency.wrap(PAIR);
    }

    function _enableMaxProtocolFee() internal {
        uint24 maxFee = ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        PoolManager(MANAGER).setProtocolFeeController(address(this));
        PoolManager(MANAGER).setProtocolFee(key, maxFee | (maxFee << 12));
    }

    // ---------------------------------------------------------------- protocol fees on top of the LP fee

    function test_RoundTripStillBalancesWithProtocolFeeEnabled() public {
        _enableMaxProtocolFee();
        _roundTrip(0.5 ether);
        assertGt(manager.protocolFeesAccrued(pair), 0, "a buy accrues protocol fee in the paired currency");
        assertGt(manager.protocolFeesAccrued(spepe), 0, "a sell accrues protocol fee in SPEPE");
    }

    /// forge-config: default.fuzz.runs = 500
    function testFuzz_RoundTripWithProtocolFee(uint256 amountIn) public {
        _enableMaxProtocolFee();
        _roundTrip(bound(amountIn, 0.000001 ether, 10 ether));
    }

    function test_CollectingSpepeProtocolFeesIsAnOutboundManagerTransferAndIsTaxed() public {
        _enableMaxProtocolFee();
        _roundTrip(1 ether);
        uint256 accrued = manager.protocolFeesAccrued(spepe);
        assertGt(accrued, 0);
        address treasury = makeAddr("protocol treasury");
        uint256 taxBefore = token.balanceOf(TAX);
        uint256 managerBefore = token.balanceOf(MANAGER);
        uint256 collected = PoolManager(MANAGER).collectProtocolFees(treasury, spepe, 0);
        assertEq(collected, accrued, "the manager accounts the gross amount");
        assertEq(managerBefore - token.balanceOf(MANAGER), accrued, "the manager is debited the gross amount");
        assertEq(token.balanceOf(treasury), accrued - accrued / 50, "the treasury receives the net amount");
        assertEq(token.balanceOf(TAX) - taxBefore, accrued / 50, "the tax wallet receives the fee");
        assertEq(manager.protocolFeesAccrued(spepe), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_CollectingPairedProtocolFeesIsUntouchedByTheToken() public {
        _enableMaxProtocolFee();
        _roundTrip(1 ether);
        uint256 accrued = manager.protocolFeesAccrued(pair);
        assertGt(accrued, 0);
        address treasury = makeAddr("protocol treasury");
        uint256 taxBefore = token.balanceOf(TAX);
        PoolManager(MANAGER).collectProtocolFees(treasury, pair, 0);
        assertEq(PairFixture(PAIR).balanceOf(treasury), accrued);
        assertEq(token.balanceOf(TAX), taxBefore, "SPEPE tax wallet is unaffected by paired-currency flows");
    }

    function test_OnlyTheControllerCanSetOrCollectProtocolFees() public {
        _enableMaxProtocolFee();
        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        PoolManager(MANAGER).collectProtocolFees(makeAddr("stranger"), spepe, 0);
        vm.prank(makeAddr("stranger"));
        vm.expectRevert();
        PoolManager(MANAGER).setProtocolFee(key, 1);
    }

    // ---------------------------------------------------------------- ERC-6909 claims

    function test_KeepingBuyOutputAsClaimsDefersTheTaxUntilRedemption() public {
        uint256 managerBefore = token.balanceOf(MANAGER);
        BalanceDelta buy = claims.swapToClaims(key, !tokenIsZero, -int256(0.01 ether));
        uint256 gross = uint256(int256(tokenIsZero ? buy.amount0() : buy.amount1()));
        assertGt(gross, 0);
        assertEq(manager.balanceOf(address(claims), spepe.toId()), gross, "claims are minted for the gross output");
        assertEq(token.balanceOf(MANAGER), managerBefore, "no ERC-20 left the manager");
        assertEq(token.balanceOf(TAX), 0, "no tax without an ERC-20 transfer");
        assertEq(token.balanceOf(address(claims)), 0);

        claims.redeemClaims(spepe, gross, address(claims));
        assertEq(manager.balanceOf(address(claims), spepe.toId()), 0);
        assertEq(managerBefore - token.balanceOf(MANAGER), gross, "redemption debits the gross");
        assertEq(token.balanceOf(address(claims)), gross - gross / 50, "redeemer receives the net");
        assertEq(token.balanceOf(TAX), gross / 50, "tax is paid on redemption");
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_PartialClaimRedemptionsEachPayTheirOwnFee() public {
        BalanceDelta buy = claims.swapToClaims(key, !tokenIsZero, -int256(0.01 ether));
        uint256 gross = uint256(int256(tokenIsZero ? buy.amount0() : buy.amount1()));
        uint256 half = gross / 2;
        claims.redeemClaims(spepe, half, address(claims));
        claims.redeemClaims(spepe, gross - half, address(claims));
        assertEq(manager.balanceOf(address(claims), spepe.toId()), 0);
        assertEq(token.balanceOf(TAX), half / 50 + (gross - half) / 50);
        assertEq(token.balanceOf(address(claims)) + token.balanceOf(TAX), gross);
    }

    function test_RedeemingMoreClaimsThanHeldReverts() public {
        BalanceDelta buy = claims.swapToClaims(key, !tokenIsZero, -int256(0.01 ether));
        uint256 gross = uint256(int256(tokenIsZero ? buy.amount0() : buy.amount1()));
        vm.expectRevert();
        claims.redeemClaims(spepe, gross + 1, address(claims));
        assertEq(manager.balanceOf(address(claims), spepe.toId()), gross);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_SellingWithClaimsPaidTokensStillNeedsNoTax() public {
        BalanceDelta buy = claims.swapToClaims(key, !tokenIsZero, -int256(0.01 ether));
        uint256 gross = uint256(int256(tokenIsZero ? buy.amount0() : buy.amount1()));
        claims.redeemClaims(spepe, gross, address(claims));
        uint256 net = token.balanceOf(address(claims));
        uint256 taxAfterBuy = token.balanceOf(TAX);
        uint256 managerBefore = token.balanceOf(MANAGER);
        // Sell the net back by paying ERC-20 and keeping the paired output as claims.
        BalanceDelta sell = claims.swapToClaims(key, tokenIsZero, -int256(net));
        assertEq(-int256(tokenIsZero ? sell.amount0() : sell.amount1()), int256(net));
        assertEq(token.balanceOf(address(claims)), 0);
        assertEq(token.balanceOf(MANAGER) - managerBefore, net, "the sell settled in full");
        assertEq(token.balanceOf(TAX), taxAfterBuy, "no tax on the sell");
        assertGt(manager.balanceOf(address(claims), pair.toId()), 0, "paired output held as claims");
    }

    // ---------------------------------------------------------------- third-party recipients

    function test_BuyTakenToAThirdPartyTaxesThatRecipient() public {
        address friend = makeAddr("friend");
        BalanceDelta buy = claims.swapTakeTo(key, !tokenIsZero, -int256(0.01 ether), friend);
        uint256 gross = uint256(int256(tokenIsZero ? buy.amount0() : buy.amount1()));
        assertEq(token.balanceOf(friend), gross - gross / 50);
        assertEq(token.balanceOf(TAX), gross / 50);
        assertEq(token.balanceOf(address(claims)), 0);
    }

    function test_BuyTakenToTheTaxWalletDeliversTheGross() public {
        BalanceDelta buy = claims.swapTakeTo(key, !tokenIsZero, -int256(0.01 ether), TAX);
        uint256 gross = uint256(int256(tokenIsZero ? buy.amount0() : buy.amount1()));
        assertEq(token.balanceOf(TAX), gross, "fee leg and net leg both land in the tax wallet");
    }

    function test_BuyTakenToTheManagerItselfIsUntaxedAndLeavesNothingOwed() public {
        uint256 managerBefore = token.balanceOf(MANAGER);
        BalanceDelta buy = claims.swapTakeTo(key, !tokenIsZero, -int256(0.01 ether), MANAGER);
        uint256 gross = uint256(int256(tokenIsZero ? buy.amount0() : buy.amount1()));
        assertGt(gross, 0);
        assertEq(token.balanceOf(MANAGER), managerBefore, "a manager self-transfer moves nothing");
        assertEq(token.balanceOf(TAX), 0, "destination precedence: no tax on a transfer to the manager");
    }

    // ---------------------------------------------------------------- flash accounting

    function test_FlashTakeAndRepayBalancesAndCostsExactlyTheTax() public {
        uint256 amount = 1_000 ether;
        // The deployer holds nothing after the launch split; fund the fee from the swarm's share.
        vm.prank(makeAddr("swarm distributor"));
        token.transfer(address(claims), amount / 50);
        uint256 managerBefore = token.balanceOf(MANAGER);
        (uint256 received, uint256 paid) = claims.flash(spepe, amount);
        assertEq(received, amount - amount / 50, "borrower receives the net");
        assertEq(paid, amount, "settle credits the whole repayment");
        assertEq(token.balanceOf(MANAGER), managerBefore, "the manager is made whole");
        assertEq(token.balanceOf(address(claims)), 0, "the borrower paid the fee out of its own balance");
        assertEq(token.balanceOf(TAX), amount / 50);
    }

    function test_FlashTakeWithoutFundsForTheFeeCannotSettle() public {
        uint256 amount = 1_000 ether;
        uint256 managerBefore = token.balanceOf(MANAGER);
        vm.expectRevert();
        claims.flash(spepe, amount);
        assertEq(token.balanceOf(MANAGER), managerBefore);
        assertEq(token.balanceOf(TAX), 0, "a reverted unlock leaves no fee behind");
    }

    function test_FlashOfPairedCurrencyIsFree() public {
        // The seed is single-sided SPEPE; a buy first puts paired currency into the manager.
        _roundTrip(1 ether);
        uint256 taxBefore = token.balanceOf(TAX);
        uint256 available = PairFixture(PAIR).balanceOf(MANAGER);
        assertGt(available, 0);
        (uint256 received, uint256 paid) = claims.flash(pair, available);
        assertEq(received, available, "the paired currency has no tax");
        assertEq(paid, available);
        assertEq(PairFixture(PAIR).balanceOf(MANAGER), available);
        assertEq(token.balanceOf(TAX), taxBefore);
    }
}
