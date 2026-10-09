// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @dev Test-only pair currency, placed at IMD's configured address in the offline suite.
contract PairFixture is ERC20 {
    constructor() ERC20("Offline IMD fixture", "IMD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Test-only unlock caller. Holds its own currencies, seeds and swaps with the actual v4 core.
contract PoolHarness is IUnlockCallback {
    IPoolManager public immutable manager;
    address public immutable controller;

    constructor(IPoolManager manager_) {
        manager = manager_;
        controller = msg.sender;
    }

    modifier onlyController() {
        require(msg.sender == controller, "test controller only");
        _;
    }

    function seed(PoolKey memory key, int24 lower, int24 upper, int256 liquidity)
        external
        onlyController
        returns (BalanceDelta)
    {
        return abi.decode(manager.unlock(abi.encode(uint8(0), key, lower, upper, liquidity)), (BalanceDelta));
    }

    function swap(PoolKey memory key, bool zeroForOne, int256 amount) external onlyController returns (BalanceDelta) {
        return abi.decode(manager.unlock(abi.encode(uint8(1), key, zeroForOne, amount)), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        uint8 action = abi.decode(data, (uint8));
        PoolKey memory key;
        BalanceDelta delta;
        if (action == 0) {
            int24 lower;
            int24 upper;
            int256 liquidity;
            (, key, lower, upper, liquidity) = abi.decode(data, (uint8, PoolKey, int24, int24, int256));
            (delta,) = manager.modifyLiquidity(key, ModifyLiquidityParams(lower, upper, liquidity, bytes32(0)), "");
        } else {
            bool zeroForOne;
            int256 amount;
            (, key, zeroForOne, amount) = abi.decode(data, (uint8, PoolKey, bool, int256));
            delta = manager.swap(
                key,
                SwapParams(zeroForOne, amount, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
                ""
            );
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 delta) private {
        if (delta < 0) {
            uint256 owed = uint256(-int256(delta));
            manager.sync(currency);
            require(ERC20(Currency.unwrap(currency)).transfer(address(manager), owed), "transfer failed");
            require(manager.settle() == owed, "short settlement");
        } else if (delta > 0) {
            manager.take(currency, address(this), uint128(delta));
        }
    }
}
