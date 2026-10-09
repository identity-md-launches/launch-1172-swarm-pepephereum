# Swarm PEPEPHEREUM (SPEPE)

This repository includes the five requested AI-drawn logo options, the selected wallet logo, and a complete offline Foundry project for the specified fixed-supply token. The logo choices are described in [logos/README.md](logos/README.md); generation and small-size inspection are recorded in [artifacts/README.md](artifacts/README.md).

## Token behavior

`src/SPEPEToken.sol` implements the standard ERC-20 interface using the vendored OpenZeppelin ERC20. Its argument-free constructor mints exactly 1,000,000,000 SPEPE with 18 decimals (`1e27` minor units) to `msg.sender`. No later mint or burn entry point exists. The token has no owner, admin, pause, blacklist, upgrade or configurable fees.

| Transfer | Result |
| --- | --- |
| From PoolManager to another address | `floor(amount / 50)` to the fixed tax wallet; the recipient gets the remaining amount |
| To PoolManager, including manager self-transfers | Full amount, no tax |
| Wallet to wallet, factory distribution, distributor claims | Full amount, no tax |

The PoolManager constant is `0x8366a39cc670b4001a1121b8f6a443a643e40951`. The tax wallet constant is `0x3d6a89C8751a45DD577a4C1F3b34E71C58236193`. Both are fixed in code. `transferFrom` consumes the gross allowance and applies the same sender/destination rule, irrespective of the spender. Infinite approvals retain the standard ERC-20 behavior. Zero-address transfers revert. Failed transfers roll back both tax and allowance changes.

This address-based rule also taxes liquidity withdrawals and other SPEPE transfers out of PoolManager. Exact-output pool quotes describe gross output; users and routers receive 98% after integer rounding. Compatible integrations must measure net balance changes. There is no minimum fee: transfers below 50 minor units round to zero tax. Transfers to the tax wallet from PoolManager credit it with both the fee and the net receipt, totaling the gross amount.

The token makes no external calls during transfers. Its public interface is the nine usual ERC-20 methods and the constant getters `INITIAL_SUPPLY`, `POOL_MANAGER`, `TAX_WALLET`, `BUY_TAX_BPS`, and `BPS_DENOMINATOR`. The ABI is [docs/abi/SPEPEToken.json](docs/abi/SPEPEToken.json).

## Launch

The target is Robinhood Chain, chain id 4663. The constructor's caller is the production launch factory. The factory handles the swarm's 10% via its Merkle distributor and seeds 90% into the IMD pool. The token reserves, subtracts or distributes none of this supply itself.

`launch.json` uses `kind: custom_token`, the exact requested economics, paired IMD address `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`, fee 12500, tick spacing 60 and the requested provenance price string. The opening capitalization is 1,000 IMD; the factory derives the actual price using the deployed currency order. The specified remainder recipient is `0x000000000000000000000000000000000000dead`. No additional application contracts are deployed.

## Offline verification

Foundry 1.8.3 and cached Solidity 0.8.26 are required. Every Solidity import is an ordinary file under `lib/`; there are no submodules or install steps. Compiler configuration pins Cancun, optimization with 200 runs, metadata bytecode hash `none`, no FFI, and no filesystem permissions.

```sh
forge build --offline
forge test --offline
forge fmt --check
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
```

Plain `forge build` and `forge test` also run offline because the configuration sets `offline = true`. Tests include transfer edge cases, forbidden runtime opcode checks, 2,000-run fuzz tests, 256 invariant sequences of 64 calls, and actual local Uniswap v4 core single-sided seed/buy/sell/withdrawal tests at the fixed PoolManager address. The pair currency is a local fixture in those tests.

The optional `testFork_RobinhoodV4SeedBuyAndSell` skips when `ROBINHOOD_FORK_URL` is unset. A network operator can provide that variable through their own environment and set `ROBINHOOD_FORK_BLOCK` to a pinned block, then run `forge test --match-contract SPEPEForkTest`. No endpoint or credential is stored here. This fork test uses the live manager and IMD contracts, with a newly deployed local SPEPE and local test funding; it sends no live transactions. **A live-state fork run remains outstanding.** The offline suite covers the settlement behavior with vendored v4 core.

`script/Deploy.s.sol` is a local simulation and operator review aid; production uses the network's factory. It reads only `EXPECTED_CHAIN_ID`, accepts chain 31337 or 4663, and contains one token deployment between broadcast markers. The safe operator simulation command above does not broadcast. A reviewed production deployment is performed solely by the network deployer; no keys, signer configuration or broadcasting command is included.

See [REVIEW.md](REVIEW.md) for checked properties and remaining external verification, and [lib/README.md](lib/README.md) for dependency provenance.
