// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {SPEPEToken} from "../src/SPEPEToken.sol";

/// @dev Test-only CREATE2 deployer. Does not implement the production factory or pool settlement.
contract SPEPESmokeFactory {
    address private immutable controller = msg.sender;

    function deploy(bytes32 salt) external returns (SPEPEToken) {
        require(msg.sender == controller, "test controller only");
        return new SPEPEToken{salt: salt}();
    }

    function move(SPEPEToken token, address to, uint256 amount) external {
        require(msg.sender == controller, "test controller only");
        require(token.transfer(to, amount), "transfer failed");
    }
}

/// @notice Fast deployment, launch-transfer and failure checks; no RPC or environment required.
contract SPEPELaunchSmokeTest is Test {
    uint256 private constant SUPPLY = 1e27;
    address private constant MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address private constant TAX = 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193;

    SPEPESmokeFactory private factory;
    SPEPEToken private token;
    address private requester = makeAddr("launch requester");
    address private distributor = makeAddr("launch distributor");
    address private buyer = makeAddr("launch buyer");
    address private holder = makeAddr("launch holder");

    function setUp() public {
        factory = new SPEPESmokeFactory();
        // The transaction origin must receive no supply when a factory creates the token.
        vm.prank(address(this), requester);
        token = factory.deploy(keccak256("SPEPE launch smoke"));
    }

    function test_Create2MintsEntireSupplyToImmediateDeployer() public view {
        assertEq(token.name(), "Swarm PEPEPHEREUM");
        assertEq(token.symbol(), "SPEPE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(requester), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(MANAGER), 0);
        assertEq(token.balanceOf(TAX), 0);
    }

    function test_LaunchTransfersPreserveSwarmAndOnlyTaxBuy() public {
        factory.move(token, distributor, SUPPLY / 10);
        factory.move(token, MANAGER, SUPPLY * 9 / 10);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(MANAGER), SUPPLY * 9 / 10);
        assertEq(token.balanceOf(TAX), 0);

        vm.prank(distributor);
        assertTrue(token.transfer(holder, SUPPLY / 10));
        assertEq(token.balanceOf(holder), SUPPLY / 10);
        assertEq(token.balanceOf(distributor), 0);

        vm.prank(MANAGER);
        assertTrue(token.transfer(buyer, 100 ether));
        assertEq(token.balanceOf(buyer), 98 ether);
        assertEq(token.balanceOf(TAX), 2 ether);

        vm.prank(buyer);
        assertTrue(token.transfer(holder, 98 ether));
        assertEq(token.balanceOf(holder), SUPPLY / 10 + 98 ether);
        assertEq(token.balanceOf(buyer), 0);

        vm.prank(holder);
        assertTrue(token.transfer(MANAGER, 98 ether));
        assertEq(token.balanceOf(holder), SUPPLY / 10);
        assertEq(token.balanceOf(MANAGER), SUPPLY * 9 / 10 - 2 ether);
        assertEq(token.balanceOf(TAX), 2 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RequesterCannotSpendFactorySupplyWithoutApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, requester, 0, 1 ether));
        vm.prank(requester);
        token.transferFrom(address(factory), requester, 1 ether);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(requester), 0);
        assertEq(token.allowance(address(factory), requester), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
