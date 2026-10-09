// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @dev Test-only unlock caller for the paths the plain PoolHarness does not drive: swaps whose
/// output is kept as ERC-6909 claims, later redemption of those claims, swaps whose output is taken
/// to a third party, and a take-and-repay flash loan. Only the test may drive it.
contract ClaimsHarness is IUnlockCallback {
    IPoolManager public immutable manager;
    address public immutable controller;

    uint8 private constant SWAP_TO_CLAIMS = 0;
    uint8 private constant REDEEM_CLAIMS = 1;
    uint8 private constant SWAP_TAKE_TO = 2;
    uint8 private constant FLASH = 3;

    constructor(IPoolManager manager_) {
        manager = manager_;
        controller = msg.sender;
    }

    modifier onlyController() {
        require(msg.sender == controller, "test controller only");
        _;
    }

    /// @notice Swap, paying the input with ERC-20 and keeping the output as ERC-6909 claims.
    function swapToClaims(PoolKey memory key, bool zeroForOne, int256 amount)
        external
        onlyController
        returns (BalanceDelta)
    {
        return abi.decode(manager.unlock(abi.encode(SWAP_TO_CLAIMS, key, zeroForOne, amount)), (BalanceDelta));
    }

    /// @notice Burn claims and take the underlying ERC-20 to `to`.
    function redeemClaims(Currency currency, uint256 amount, address to) external onlyController {
        manager.unlock(abi.encode(REDEEM_CLAIMS, currency, amount, to));
    }

    /// @notice Swap, paying the input with ERC-20 and taking the output straight to `to`.
    function swapTakeTo(PoolKey memory key, bool zeroForOne, int256 amount, address to)
        external
        onlyController
        returns (BalanceDelta)
    {
        return abi.decode(manager.unlock(abi.encode(SWAP_TAKE_TO, key, zeroForOne, amount, to)), (BalanceDelta));
    }

    /// @notice Take `amount` of `currency`, then repay exactly `amount` from this contract's balance.
    function flash(Currency currency, uint256 amount) external onlyController returns (uint256 received, uint256 paid) {
        return abi.decode(manager.unlock(abi.encode(FLASH, currency, amount)), (uint256, uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "manager only");
        uint8 action = abi.decode(data, (uint8));
        if (action == SWAP_TO_CLAIMS) {
            (, PoolKey memory key, bool zeroForOne, int256 amount) = abi.decode(data, (uint8, PoolKey, bool, int256));
            BalanceDelta delta = _swap(key, zeroForOne, amount);
            _payOrClaim(key.currency0, delta.amount0());
            _payOrClaim(key.currency1, delta.amount1());
            return abi.encode(delta);
        }
        if (action == REDEEM_CLAIMS) {
            (, Currency currency, uint256 amount, address to) = abi.decode(data, (uint8, Currency, uint256, address));
            manager.burn(address(this), currency.toId(), amount);
            manager.take(currency, to, amount);
            return "";
        }
        if (action == SWAP_TAKE_TO) {
            (, PoolKey memory key, bool zeroForOne, int256 amount, address to) =
                abi.decode(data, (uint8, PoolKey, bool, int256, address));
            BalanceDelta delta = _swap(key, zeroForOne, amount);
            _payOrTakeTo(key.currency0, delta.amount0(), to);
            _payOrTakeTo(key.currency1, delta.amount1(), to);
            return abi.encode(delta);
        }
        require(action == FLASH, "unknown action");
        (, Currency flashCurrency, uint256 flashAmount) = abi.decode(data, (uint8, Currency, uint256));
        return _flash(flashCurrency, flashAmount);
    }

    function _flash(Currency currency, uint256 amount) private returns (bytes memory) {
        ERC20 erc20 = ERC20(Currency.unwrap(currency));
        uint256 before = erc20.balanceOf(address(this));
        manager.take(currency, address(this), amount);
        uint256 received = erc20.balanceOf(address(this)) - before;
        manager.sync(currency);
        require(erc20.transfer(address(manager), amount), "repay failed");
        uint256 paid = manager.settle();
        return abi.encode(received, paid);
    }

    function _swap(PoolKey memory key, bool zeroForOne, int256 amount) private returns (BalanceDelta) {
        return manager.swap(
            key,
            SwapParams(zeroForOne, amount, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
            ""
        );
    }

    function _pay(Currency currency, uint256 owed) private {
        manager.sync(currency);
        require(ERC20(Currency.unwrap(currency)).transfer(address(manager), owed), "transfer failed");
        require(manager.settle() == owed, "short settlement");
    }

    function _payOrClaim(Currency currency, int128 delta) private {
        if (delta < 0) _pay(currency, uint256(-int256(delta)));
        else if (delta > 0) manager.mint(address(this), currency.toId(), uint256(int256(delta)));
    }

    function _payOrTakeTo(Currency currency, int128 delta, address to) private {
        if (delta < 0) _pay(currency, uint256(-int256(delta)));
        else if (delta > 0) manager.take(currency, to, uint256(int256(delta)));
    }
}
