// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {SPEPEToken} from "../src/SPEPEToken.sol";

contract SPEPETokenTest is Test {
    SPEPEToken internal token;
    address internal constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address internal constant TAX = 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");
    uint256 internal constant SUPPLY = 1e27;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new SPEPEToken();
    }

    function test_EntireSupplyAndFixedLaunchParameters() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(TAX), 0);
        assertEq(token.name(), "Swarm PEPEPHEREUM");
        assertEq(token.symbol(), "SPEPE");
        assertEq(token.decimals(), 18);
        assertEq(token.POOL_MANAGER(), MANAGER);
        assertEq(token.TAX_WALLET(), TAX);
        assertEq(token.BUY_TAX_BPS(), 200);
        assertEq(token.BPS_DENOMINATOR(), 10_000);
    }

    function test_FactoryDistributionAndClaimArriveWhole() public {
        address distributor = makeAddr("distributor");
        token.transfer(distributor, SUPPLY / 10);
        token.transfer(MANAGER, SUPPLY * 9 / 10);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(MANAGER), SUPPLY * 9 / 10);
        vm.prank(distributor);
        token.transfer(alice, SUPPLY / 10);
        assertEq(token.balanceOf(alice), SUPPLY / 10);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_BuyEmitsTaxAndNetTransfers() public {
        token.transfer(MANAGER, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(MANAGER, TAX, 2 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(MANAGER, alice, 98 ether);
        vm.prank(MANAGER);
        assertTrue(token.transfer(alice, 100 ether));
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(alice), 98 ether);
        assertEq(token.balanceOf(TAX), 2 ether);
    }

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_BuySellAndWalletConserveSupply(uint256 gross) public {
        gross = bound(gross, 0, SUPPLY);
        token.transfer(MANAGER, gross);
        vm.prank(MANAGER);
        token.transfer(alice, gross);
        uint256 net = token.balanceOf(alice);
        uint256 tax = token.balanceOf(TAX);
        assertEq(net + tax, gross);
        assertEq(tax, gross * 2 / 100);
        assertEq(token.balanceOf(MANAGER), 0);
        vm.prank(alice);
        token.transfer(bob, net);
        assertEq(token.balanceOf(bob), net);
        vm.prank(bob);
        token.transfer(MANAGER, net);
        assertEq(token.balanceOf(MANAGER), net);
        assertEq(token.balanceOf(TAX), tax);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(MANAGER) + tax, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 2000
    function testFuzz_DelegatedBuyChargesGrossAllowance(uint256 gross, bool infinite) public {
        gross = bound(gross, 0, SUPPLY);
        token.transfer(MANAGER, gross);
        vm.prank(MANAGER);
        token.approve(spender, infinite ? type(uint256).max : gross);
        vm.prank(spender);
        token.transferFrom(MANAGER, alice, gross);
        assertEq(token.balanceOf(alice) + token.balanceOf(TAX), gross);
        assertEq(token.balanceOf(TAX), gross / 50);
        assertEq(token.allowance(MANAGER, spender), infinite ? type(uint256).max : 0);
    }

    function test_CallerDoesNotDetermineTax() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_DelegatedSellArrivesWhole() public {
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.prank(spender);
        token.transferFrom(alice, MANAGER, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_RoundingThresholdAndZero() public {
        token.transfer(MANAGER, 200);
        vm.startPrank(MANAGER);
        token.transfer(alice, 0);
        token.transfer(alice, 49);
        assertEq(token.balanceOf(TAX), 0);
        token.transfer(alice, 50);
        assertEq(token.balanceOf(TAX), 1);
        token.transfer(alice, 101);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 197);
        assertEq(token.balanceOf(TAX), 3);
        assertEq(token.balanceOf(MANAGER), 0);
    }

    function test_RecipientTaxWalletGetsWholeGrossWithoutRecursion() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.transfer(TAX, 100 ether);
        assertEq(token.balanceOf(TAX), 100 ether);
        assertEq(token.balanceOf(MANAGER), 0);
        vm.prank(TAX);
        token.transfer(MANAGER, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_SelfTransfersIncludingManagerNeverCharge() public {
        token.transfer(MANAGER, 100 ether);
        token.transfer(alice, 100 ether);
        vm.prank(MANAGER);
        token.transfer(MANAGER, 100 ether);
        vm.prank(alice);
        token.transfer(alice, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_FailedSecondLegRollsBackTaxAndAllowance() public {
        token.transfer(MANAGER, 99 ether);
        vm.prank(MANAGER);
        token.approve(spender, 100 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, MANAGER, 97 ether, 98 ether)
        );
        vm.prank(spender);
        token.transferFrom(MANAGER, alice, 100 ether);
        assertEq(token.allowance(MANAGER, spender), 100 ether);
        assertEq(token.balanceOf(MANAGER), 99 ether);
        assertEq(token.balanceOf(TAX), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_InsufficientAllowanceDoesNotMoveFunds() public {
        token.transfer(MANAGER, 100 ether);
        vm.prank(MANAGER);
        token.approve(spender, 98 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 98 ether, 100 ether)
        );
        vm.prank(spender);
        token.transferFrom(MANAGER, alice, 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_ZeroAddressCannotBurnOrReceiveTaxedBuy() public {
        token.transfer(MANAGER, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(MANAGER);
        token.transfer(address(0), 100 ether);
        assertEq(token.balanceOf(MANAGER), 100 ether);
        assertEq(token.balanceOf(TAX), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumInputRevertsWithoutOverflowOrPartialTax() public {
        token.transfer(MANAGER, SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, MANAGER, SUPPLY, type(uint256).max / 50
            )
        );
        vm.prank(MANAGER);
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(MANAGER), SUPPLY);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_NoAdminMintBurnOrFreezeEntryPoints() public {
        string[22] memory signatures = [
            "owner()",
            "admin()",
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "setOwner(address)",
            "setTaxWallet(address)",
            "setTaxRate(uint256)",
            "setPoolManager(address)",
            "setFee(uint256)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "setMinter(address)"
        ];
        token.transfer(alice, 100 ether);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, 1 ether);
            (bool deployerOK,) = address(token).call(data);
            assertFalse(deployerOK, signatures[i]);
            vm.prank(bob);
            (bool strangerOK,) = address(token).call(data);
            assertFalse(strangerOK, signatures[i]);
        }
        vm.expectRevert();
        token.transferFrom(alice, address(this), 1);
        vm.prank(alice);
        token.transfer(bob, 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeContainsNoForbiddenInstructions() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
