# squeek (SQUEEK)

X: [@squeekchain](https://x.com/squeekchain) · Website: squeekchain.com

A plain, fixed-supply ERC-20 (`src/SqueekToken.sol`, contract `SqueekToken`).

| Parameter | Value |
|---|---|
| name / symbol | `squeek` / `SQUEEK` |
| decimals | 18 |
| totalSupply | 1,000,000,000 × 10^18 = `1000000000000000000000000000` minor units |
| constructor args | none |
| minted to | `msg.sender` (the launch factory), once, in the constructor |

## Assumptions and design
- No owner, no admin, no mint, no burn, no pause, no blacklist, no fees: the supply is fixed forever, and nobody can move or freeze a holder's balance. Transfers move exactly the amount requested, so the factory → distributor, pool seeding and swap flows arrive in full.
- An allowance of `type(uint256).max` is treated as unlimited and is not reduced.
- Transfers to the zero address and approvals of the zero address revert.
- No library calls, no DELEGATECALL/SELFDESTRUCT. No external dependencies other than `forge-std`, which is vendored in `lib/` for tests only.

## Deployment parameters
Built with solc 0.8.26, optimizer 200 runs, `bytecode_hash = "none"` (see `foundry.toml`). Launch on Ethereum (chain 1), paired with IMD, as described by the launch; the launch manifest is written by the separate manifest step.

## Operational responsibilities
- There are no privileged functions, so there is nothing to administer after launch and no "After launch" settings.
- Social/website links are informational only; they are not stored on chain.
- Tests are not an audit.

## Checks
```
forge build && forge test && forge fmt --check
```
