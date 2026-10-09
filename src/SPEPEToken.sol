// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply SPEPE. Only outbound PoolManager transfers pay the creator tax.
/// @dev The launch factory, as constructor caller, receives the entire supply. It handles distribution.
contract SPEPEToken is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant BUY_TAX_BPS = 200;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    address public constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address public constant TAX_WALLET = 0x3d6a89C8751a45DD577a4C1F3b34E71C58236193;

    constructor() ERC20("Swarm PEPEPHEREUM", "SPEPE") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /// @dev Destination precedence keeps all transfers TO the manager untaxed, including self-transfers.
    /// The fee rounds down to whole minor units. Two internal updates debit the gross amount;
    /// neither performs an external call or recursively applies a fee.
    function _update(address from, address to, uint256 value) internal override {
        if (from == POOL_MANAGER && to != POOL_MANAGER) {
            // Division first is exact for this fixed 2% rate and safe even for oversized invalid inputs.
            uint256 tax = value / (BPS_DENOMINATOR / BUY_TAX_BPS);
            if (tax != 0) super._update(from, TAX_WALLET, tax);
            super._update(from, to, value - tax);
        } else {
            super._update(from, to, value);
        }
    }
}
