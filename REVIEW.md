# Local review and validation

This is a separate local implementation review, not an independent third-party audit. The network's independent verifier must rerun its own checks.

## Findings and disposition

- **Prior attempt compiled nothing:** addressed with a root Foundry configuration, `src/SPEPEToken.sol`, vendored imports and runnable unit, fuzz, invariant and v4 integration suites. The build now compiles Solidity 0.8.26 and runs real tests.
- **Address literal casing:** the initial compiler pass rejected the PoolManager and pair literals' checksum capitalization. Correct EIP-55 casing was applied without changing their address bytes; compilation now succeeds.
- **Supply and launch distribution:** reviewed constructor and mint call graph. Only the constructor calls `_mint`, for exactly `1e27` to its caller. The factory and claimant transfers arrive whole, and there is no additional supply or token-side swarm distribution.
- **Fee direction and settlement:** reviewed `_update` and exercised actual v4 `sync`, `settle`, `take`, `modifyLiquidity` and `swap`. Seeds and sells arrive whole; buys debit the gross manager amount and split it between buyer and tax wallet. Recipient precedence leaves manager self-transfers untaxed.
- **Rounding, aliases and rollback:** fuzz and example tests cover zero, 49/50-unit threshold, entire supply, maximum invalid integer input, tax-wallet recipient, manager self-transfer, delegated buys/sells, spender-independent tax, exact and unlimited approvals, insufficient allowance, and failure after the fee leg. Reverts do not leave partial fees or allowance deductions.
- **Privileged surfaces:** reviewed and checked the complete ABI. It contains only standard ERC-20 methods and five fixed constant getters. Deployer and stranger probes for owner/admin/mint/burn/pause/freeze/upgrade methods fail. A PUSH-aware scan of deployed token bytecode rejects DELEGATECALL, CALLCODE and SELFDESTRUCT.
- **Integration limitation, documented:** every outbound manager transfer is taxed, including liquidity withdrawals. Exact-output quotes are gross; recipient balance changes are net. Offline tests explicitly demonstrate both behaviors.
- **Art selection:** all five approaches are saved at 1024 × 1024, and option 2 is copied unchanged to the selected path. The actual 32 px circle inspection favors its broad shapes. The lettermark and badge remain requested alternatives, not the primary icon.

## Validation

The initial completed suite passed 21 tests, with one optional fork test skipped, 1,000 cases per fuzz test, and 16,384 invariant calls with zero reverts. It was rerun with a separate fuzz seed. Inline fuzz settings were raised to 2,000 so that the verifier retains that coverage without command-line flags. The final default and `0xc0ffee` seed runs both passed 21 tests with zero failures, one skipped fork test, 2,000 cases per fuzz test and 16,384 invariant calls with zero reverts. Build, formatting and deployment simulation also passed. Final command output is saved under `artifacts/checks/`.

The required build, test, formatter and local deployment simulation commands are in README.md. Image structure checks succeeded for all five options and the selected logo, each exactly 1024 × 1024. The manifest was checked against the brief's exact key sets and values, and the ABI was checked against the intended public function set. The supplied `.imd/reads` contains no manifest schema file, so no claim of schema-validator execution is made.

## Independent work still owed

The optional Robinhood mainnet fork was not executed because no operator-provided fork environment was supplied. This is reported as skipped, never as a passing live-chain test. The pinned protected factory harness was read and its supply, distribution, settlement and privilege properties informed local coverage; its deployment-specific environment and factory support sources are provided by the independent verifier, so that exact harness was not claimed as locally executed. No live transaction was broadcast.
