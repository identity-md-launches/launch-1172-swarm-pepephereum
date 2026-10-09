# Vendored source dependencies

All imports resolve to ordinary repository files. These are selected source copies from the machine's preinstalled vendor mirrors, with licenses preserved, not git submodules or network dependencies. No package-manager installation is needed.

| Directory | Source selection | Version recorded by mirror | License |
| --- | --- | --- | --- |
| `openzeppelin-contracts` | ERC20 and its five direct/transitive source dependencies | package 5.7.0; ERC20 header last updated 5.5.0 | MIT |
| `forge-std` | `src/` test/script utilities | 1.16.2 | MIT / Apache-2.0 |
| `v4-core` | production `src/`, excluding upstream `src/test/` | 1.0.2 | Per-file SPDX, including BUSL-1.1 and MIT; texts in `licenses/` |
| `solmate` | `src/auth/Owned.sol`, required by test PoolManager | no package version copied | AGPL-3.0-only, as declared in the source |

Only OpenZeppelin's ERC20 subset is inherited by the deployed SPEPE token. v4-core, Solmate and forge-std support local testing and deployment simulation. Upstream package metadata is informational; its development dependencies are not used. `source-sha256.json` pins every vendored file's bytes for review.
