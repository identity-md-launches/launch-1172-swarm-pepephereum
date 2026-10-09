// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {SPEPEToken} from "../src/SPEPEToken.sol";

/// @notice Adversarial coverage of the three transfer rules: taxed only FROM the PoolManager, never
/// TO it, never wallet-to-wallet. Every test here either feeds the rule an input the happy path does
/// not (arbitrary addresses, split amounts, overdrafts, the tax wallet itself) or checks what the
/// contract must NOT do (emit a stray event, leave a partial fee, expose a privileged hand).
contract SPEPETaxRulesTest is Test {
    SPEPEToken internal token;
    address internal constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant TAX = 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193;
    uint256 internal constant SUPPLY = 1e27;
    bytes32 internal constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        token = new SPEPEToken();
    }

    // ---------------------------------------------------------------- supply and deployment

    function test_DeployerIsWhoeverCallsTheConstructorNotTxOrigin() public {
        address eoaDeployer = makeAddr("eoa deployer");
        address origin = makeAddr("origin");
        vm.prank(eoaDeployer, origin);
        SPEPEToken fresh = new SPEPEToken();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(eoaDeployer), SUPPLY);
        assertEq(fresh.balanceOf(origin), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
        assertEq(fresh.INITIAL_SUPPLY(), SUPPLY);
        assertEq(fresh.INITIAL_SUPPLY(), 1_000_000_000 * 10 ** uint256(fresh.decimals()));
    }

    function test_TwoDeploymentsAreIndependentAndEachMintsOnce() public {
        SPEPEToken second = new SPEPEToken();
        assertTrue(address(second) != address(token));
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(address(this)), SUPPLY);
        token.transfer(alice, 1 ether);
        assertEq(second.balanceOf(alice), 0, "balances must not leak across deployments");
    }

    function test_ConstructorEmitsExactlyOneMintTransfer() public {
        vm.recordLogs();
        SPEPEToken fresh = new SPEPEToken();
        Vm.Log[] memory logs = _transferLogs(vm.getRecordedLogs(), address(fresh));
        assertEq(logs.length, 1);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(0));
        assertEq(address(uint160(uint256(logs[0].topics[2]))), address(this));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    // ---------------------------------------------------------------- the rule, fuzzed over addresses

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_OnlyManagerOriginatedTransfersPayTax(address from, address to, uint256 amount) public {
        vm.assume(from != address(0) && to != address(0));
        vm.assume(from != address(token) && to != address(token));
        vm.assume(from != TAX && to != TAX);
        vm.assume(from != address(this));
        amount = bound(amount, 0, SUPPLY);
        token.transfer(from, amount);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        bool taxed = from == MANAGER && to != MANAGER;
        uint256 expectedTax = taxed ? amount * token.BUY_TAX_BPS() / token.BPS_DENOMINATOR() : 0;
        assertEq(token.balanceOf(TAX), expectedTax, "tax wallet balance");
        if (from == to) {
            assertEq(token.balanceOf(to), amount, "self transfer keeps the balance");
        } else {
            assertEq(token.balanceOf(to) - toBefore, amount - expectedTax, "recipient receives gross minus tax");
            assertEq(token.balanceOf(from), 0, "sender is fully debited");
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AnyoneSellingToManagerArrivesWhole(address seller, uint256 amount) public {
        vm.assume(seller != address(0) && seller != address(token) && seller != address(this));
        vm.assume(seller != MANAGER);
        amount = bound(amount, 0, SUPPLY);
        token.transfer(seller, amount);
        uint256 managerBefore = token.balanceOf(MANAGER);
        uint256 taxBefore = token.balanceOf(TAX);
        vm.prank(seller);
        token.transfer(MANAGER, amount);
        assertEq(token.balanceOf(MANAGER) - managerBefore, amount, "manager must receive the whole amount");
        // The tax wallet selling its own fees is the one seller whose balance legitimately drops.
        assertEq(token.balanceOf(TAX), seller == TAX ? 0 : taxBefore, "no tax on a transfer to the manager");
        assertEq(token.balanceOf(seller), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SpenderIdentityNeverChangesTheTax(address anySpender, uint256 amount) public {
        vm.assume(anySpender != address(0));
        amount = bound(amount, 0, SUPPLY);
        token.transfer(MANAGER, amount);
        vm.prank(MANAGER);
        token.approve(anySpender, amount);
        vm.prank(anySpender);
        token.transferFrom(MANAGER, alice, amount);
        assertEq(token.balanceOf(TAX), amount / 50);
        assertEq(token.balanceOf(alice), amount - amount / 50);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.allowance(MANAGER, anySpender), 0, "allowance consumed on the gross amount");
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TaxIsFlooredPerTransferSoSplittingNeverPaysMore(uint256 total, uint8 parts) public {
        total = bound(total, 0, SUPPLY);
        parts = uint8(bound(parts, 1, 16));
        token.transfer(MANAGER, total);
        uint256 remaining = total;
        uint256 expectedTax;
        for (uint256 i; i < parts; ++i) {
            uint256 piece = i + 1 == parts ? remaining : remaining / (parts - i);
            expectedTax += piece / 50;
            remaining -= piece;
            vm.prank(MANAGER);
            token.transfer(alice, piece);
        }
        assertEq(token.balanceOf(TAX), expectedTax, "tax is floor(piece / 50) summed per transfer");
        assertLe(expectedTax, total / 50, "splitting can only round the fee down, never up");
        assertGe(expectedTax + parts, total / 50, "each split loses at most one minor unit of fee");
        assertEq(token.balanceOf(alice) + token.balanceOf(TAX), total);
        assertEq(token.balanceOf(MANAGER), 0);
    }

    // ---------------------------------------------------------------- events

    function test_BuyEmitsExactlyTwoTransfersInFeeThenNetOrder() public {
        token.transfer(MANAGER, 1_000 ether);
        vm.recordLogs();
        vm.prank(MANAGER);
        token.transfer(alice, 1_000 ether);
        Vm.Log[] memory logs = _transferLogs(vm.getRecordedLogs(), address(token));
        assertEq(logs.length, 2, "a taxed buy is two Transfer events, nothing else");
        assertEq(address(uint160(uint256(logs[0].topics[1]))), MANAGER);
        assertEq(address(uint160(uint256(logs[0].topics[2]))), TAX);
        assertEq(abi.decode(logs[0].data, (uint256)), 20 ether);
        assertEq(address(uint160(uint256(logs[1].topics[1]))), MANAGER);
        assertEq(address(uint160(uint256(logs[1].topics[2]))), alice);
        assertEq(abi.decode(logs[1].data, (uint256)), 980 ether);
    }

    function test_SubThresholdBuyEmitsOnlyTheNetTransfer() public {
        token.transfer(MANAGER, 49);
        vm.recordLogs();
        vm.prank(MANAGER);
        token.transfer(alice, 49);
        Vm.Log[] memory logs = _transferLogs(vm.getRecordedLogs(), address(token));
        assertEq(logs.length, 1, "no zero-value fee event when the fee rounds to zero");
        assertEq(address(uint160(uint256(logs[0].topics[2]))), alice);
        assertEq(abi.decode(logs[0].data, (uint256)), 49);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_SellAndWalletTransfersEmitExactlyOneTransferEach() public {
        token.transfer(alice, 200 ether);
        vm.recordLogs();
        vm.prank(alice);
        token.transfer(MANAGER, 100 ether);
        vm.prank(alice);
        token.transfer(bob, 100 ether);
        Vm.Log[] memory logs = _transferLogs(vm.getRecordedLogs(), address(token));
        assertEq(logs.length, 2);
        assertEq(address(uint160(uint256(logs[0].topics[2]))), MANAGER);
        assertEq(abi.decode(logs[0].data, (uint256)), 100 ether);
        assertEq(address(uint160(uint256(logs[1].topics[2]))), bob);
        assertEq(abi.decode(logs[1].data, (uint256)), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
    }

    // ---------------------------------------------------------------- failure paths

    function test_BuyWhereEvenTheFeeExceedsManagerBalanceRevertsOnTheFeeLeg() public {
        token.transfer(MANAGER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, MANAGER, 1, 2));
        vm.prank(MANAGER);
        token.transfer(alice, 100);
        assertEq(token.balanceOf(MANAGER), 1);
        assertEq(token.balanceOf(TAX), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ManagerWithNothingCannotBuyEvenOneUnit() public {
        assertEq(token.balanceOf(MANAGER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, MANAGER, 0, 1));
        vm.prank(MANAGER);
        token.transfer(alice, 1);
        vm.prank(MANAGER);
        assertTrue(token.transfer(alice, 0), "a zero transfer from an empty manager is still a valid no-op");
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ManagerSelfTransferOverdraftRevertsWithoutFee() public {
        token.transfer(MANAGER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, MANAGER, 10, 11));
        vm.prank(MANAGER);
        token.transfer(MANAGER, 11);
        assertEq(token.balanceOf(MANAGER), 10);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_DelegatedManagerSelfTransferIsUntaxedButConsumesAllowance() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        token.transferFrom(MANAGER, MANAGER, 60 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
        assertEq(token.allowance(MANAGER, spender), 40 ether);
    }

    function test_WalletOverdraftAndZeroRecipientRevertWithoutMovingFunds() public {
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 10 ether + 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(alice);
        token.approve(address(0), 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ManagerBuyToTaxWalletViaTransferFromCreditsGrossOnce() public {
        token.transfer(MANAGER, 100);
        vm.prank(MANAGER);
        token.approve(spender, 100);
        vm.prank(spender);
        token.transferFrom(MANAGER, TAX, 100);
        assertEq(token.balanceOf(TAX), 100, "fee leg plus net leg equal the gross");
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.allowance(MANAGER, spender), 0);
    }

    function test_TaxWalletCanSpendItsFeesWithoutPayingAgain() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transfer(alice, 100 ether);
        assertEq(token.balanceOf(TAX), 2 ether);
        vm.prank(TAX);
        token.transfer(bob, 2 ether);
        assertEq(token.balanceOf(bob), 2 ether);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_RepeatedBuysKeepDebitingGrossUntilManagerIsEmpty() public {
        token.transfer(MANAGER, 300 ether);
        for (uint256 i; i < 3; ++i) {
            vm.prank(MANAGER);
            token.transfer(alice, 100 ether);
        }
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(alice), 294 ether);
        assertEq(token.balanceOf(TAX), 6 ether);
        vm.expectRevert();
        vm.prank(MANAGER);
        token.transfer(alice, 1);
    }

    // ---------------------------------------------------------------- fixed parameters

    function test_FixedAddressesAreBakedIntoRuntimeCodeNotStorage() public view {
        bytes memory runtime = address(token).code;
        assertTrue(_contains(runtime, abi.encodePacked(TAX)), "tax wallet literal missing from runtime");
        assertTrue(_contains(runtime, abi.encodePacked(MANAGER)), "pool manager literal missing from runtime");
        // OpenZeppelin ERC20 uses slots 0..4 (balances, allowances, totalSupply, name, symbol). No slot holds
        // an address-shaped value that a setter could rewrite: the parameters are compile-time constants.
        for (uint256 slot; slot < 16; ++slot) {
            bytes32 word = vm.load(address(token), bytes32(slot));
            assertTrue(word != bytes32(uint256(uint160(TAX))), "tax wallet must not live in storage");
            assertTrue(word != bytes32(uint256(uint160(MANAGER))), "pool manager must not live in storage");
        }
    }

    function test_ParameterGettersAreCallerIndependentAndStatic() public {
        address[3] memory callers = [address(this), MANAGER, makeAddr("stranger")];
        for (uint256 i; i < callers.length; ++i) {
            vm.startPrank(callers[i]);
            (bool ok, bytes memory ret) = address(token).staticcall(abi.encodeWithSignature("TAX_WALLET()"));
            assertTrue(ok);
            assertEq(abi.decode(ret, (address)), TAX);
            (ok, ret) = address(token).staticcall(abi.encodeWithSignature("POOL_MANAGER()"));
            assertTrue(ok);
            assertEq(abi.decode(ret, (address)), MANAGER);
            (ok, ret) = address(token).staticcall(abi.encodeWithSignature("BUY_TAX_BPS()"));
            assertTrue(ok);
            assertEq(abi.decode(ret, (uint256)), 200);
            vm.stopPrank();
        }
        assertEq(token.BUY_TAX_BPS() * 100 / token.BPS_DENOMINATOR(), 2, "rate is exactly two percent");
    }

    /// @dev Mirrors the launch floor: every privileged name is tried from the deployer and a stranger,
    /// with an address and a boolean payload, and afterwards the holder still holds and can still move.
    function test_PrivilegedNamesCannotMoveOrFreezeAHolderOrChangeParameters() public {
        address holder = makeAddr("holder");
        token.transfer(holder, SUPPLY / 1000);
        uint256 held = token.balanceOf(holder);
        string[22] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "issue(uint256)",
            "setTaxWallet(address)",
            "setTaxRate(uint256)",
            "setBuyTax(uint256)",
            "setPoolManager(address)",
            "excludeFromFee(address)",
            "setExempt(address,bool)",
            "rescueTokens(address,uint256)",
            "withdraw()",
            "setFeeTo(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], holder, true);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(makeAddr("stranger"));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        (bool moved,) =
            address(token).call(abi.encodeWithSelector(token.transferFrom.selector, holder, address(this), 1));
        assertFalse(moved, "deployer must not spend a holder's balance without approval");
        assertEq(token.balanceOf(holder), held);
        assertEq(token.TAX_WALLET(), TAX);
        assertEq(token.POOL_MANAGER(), MANAGER);
        assertEq(token.BUY_TAX_BPS(), 200);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(bob, held));
        assertEq(token.balanceOf(bob), held);
    }

    function test_NoPayableEntryPointAndNoFallback() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok, "plain value transfer must be rejected");
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "unknown selector must revert");
        (ok,) = address(token).call{value: 1}(abi.encodeWithSelector(token.transfer.selector, alice, 1));
        assertFalse(ok, "transfer is not payable");
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------- helpers

    function _transferLogs(Vm.Log[] memory all, address emitter) private pure returns (Vm.Log[] memory out) {
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (all[i].emitter == emitter && all[i].topics[0] == TRANSFER_SIG) ++n;
        }
        out = new Vm.Log[](n);
        uint256 j;
        for (uint256 i; i < all.length; ++i) {
            if (all[i].emitter == emitter && all[i].topics[0] == TRANSFER_SIG) out[j++] = all[i];
        }
    }

    function _contains(bytes memory haystack, bytes memory needle) private pure returns (bool) {
        if (needle.length > haystack.length) return false;
        for (uint256 i; i + needle.length <= haystack.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < needle.length; ++j) {
                if (haystack[i + j] != needle[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }
}
