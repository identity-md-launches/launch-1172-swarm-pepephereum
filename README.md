# Swarm PEPEPHEREUM (SPEPE)

This repository includes the Swarm PEPEPHEREUM website, its ready-to-publish static export, the five previously delivered logo options, and the existing offline Foundry project. The website uses the assignment's supplied mascot image; a creator-selected `logo` in the live feed takes precedence. The earlier logo choices remain in [logos/README.md](logos/README.md).

## Website: install and preview

The site is plain HTML, CSS and JavaScript in [`site/`](site/index.html). It needs **no dependency installation, bundler or build step** to run. Fonts, panel artwork and the default logo are local assets. Serve the folder over HTTP so JavaScript modules load:

```sh
python3 -m http.server 4173 --directory site
```

Open `http://localhost:4173/`. A local preview has no launch feed, so the contract correctly shows `launching…`, market values show em dashes, and Buy/Chart/Copy are unavailable. Navigation, token details and the public launchpad link work. No wallet connection, forms, trackers or credentials are used.

## Rebuild and publish

[`dist/`](dist/index.html) is the complete production export. Recreate it with Node.js 22 or newer; this is an allowlisted file copy, not a compilation step:

```sh
node site-tools/build.mjs
node site-tools/server.mjs 4174
```

The second command previews the export at `http://127.0.0.1:4174/preview/`, testing static hosting under a subpath. Stop it with Ctrl+C. All runtime asset paths are relative. Source edits must be followed by the export command; keep `site/`, `site-tools/package.json`, `site-tools/package-lock.json`, and the full `dist/` in the submission.

Publish **the contents of `dist/`** as the static document root for `https://swarmpepephereum.si-md.xyz`. The publisher serves this export directly and needs no npm packages or server-side application. The hosting platform supplies `/simd-coin.json` at the origin root, even when the page is previewed under a subpath. No deployed SPEPE contract address is embedded in the site. No DNS, production hosting or blockchain deployment was changed during this assignment.

The feed uses `name`, `symbol`, `token`, `chainName`, `coinUrl`, `chartUrl`, `status`, optional `logo`, and `market.{marketCap,priceUsd,volume24h}`. A valid token address enables copying. Buy and Chart each use their own valid feed URL and require the token to exist. HTTPS and same-origin HTTP preview URLs are accepted; executable schemes are rejected. Missing links never redirect to a guessed coin. A supplied logo takes precedence, with the bundled mascot as a fallback if it fails to load.

The page fetches once on load and every 30 seconds while visible, with an 8-second timeout, a manual Refresh action, and a refresh when connectivity returns. Failed updates preserve the last good data and explicitly mark it with its last update time. Missing values remain `—`; a real zero displays `$0.00`. Positive prices below one millionth of a dollar use scientific notation so they cannot round to zero. Contract addresses remain fully selectable. Clipboard failures explain how to copy manually. Without JavaScript, all information sections, anchor links and the rules disclosure remain usable.

## Website checks

Node.js 24.21.0 was used. The following installs **development checks only**, using the committed lockfile. Packages, npm cache and downloaded Chromium stay under the already-ignored `test/scratch/`; they are not shipped. No ignore files or existing dependency configuration were changed.

```sh
node site-tools/check.mjs install
node site-tools/build.mjs
node site-tools/check.mjs typecheck
node site-tools/check.mjs test
node site-tools/check.mjs review
forge build
forge test
```

The production copy and strict JavaScript typecheck passed. The Playwright interaction suite passed **10/10 tests**, covering live/pending/error states, exact trading destinations, actual browser clipboard use and denial, logo replacement and fallback, data validation, navigation, native disclosure, virtual-clock polling/timeout, keyboard navigation, no-JavaScript behavior, reflow from 320–1440 px and 200% text enlargement. There were no unexpected runtime or asset errors. An unavailable local `/simd-coin.json` intentionally produces a 404 and the tested recovery state.

The six-domain design review, fixes, actual contrast measurements, screenshots and limits are in [docs/site-validation.md](docs/site-validation.md). [DESIGN.md](DESIGN.md) documents the final design system. Axe reported no WCAG A/AA violations at 1440, 390 and 320 px, but could not determine contrast through decorative pseudo-elements; the flat text/background pairs were measured separately. No native screen-reader, physical-device, Safari/Firefox or native browser zoom session was performed. The production feed and trading execution were not tested live.

The required Foundry checks passed: **21 tests passed, 0 failed, 1 optional fork test skipped**. See the existing token verification details below. The live-state fork remains outstanding.

The check runner recreates `test/scratch/` after cleanup. `check.mjs review` overwrites the two compact WebP screenshots and measured contrast record in `docs/site-review/`. Raw logs and detailed automation results stay in scratch; review conclusions are retained in the documentation.

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

Foundry 1.8.x and cached Solidity 0.8.26 are required. Every Solidity import is an ordinary file under `lib/`; there are no submodules or install steps. Compiler configuration pins Cancun, optimization with 200 runs, metadata bytecode hash `none`, no FFI, and no filesystem permissions.

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
