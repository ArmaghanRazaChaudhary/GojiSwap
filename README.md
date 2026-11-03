# GojiSwap

DeFi contracts and a swap front end I built for GojiSwap in 2021–22. In 2026 I reviewed my own code, fixed it, and covered every fix with tests.

**[Read the audit →](AUDIT.md)**: 13 findings, including 2 critical (a pool-drain bug and 1,000× reward overpayment).

## Contracts

| Contract | What it does |
|---|---|
| [`Staking`](contracts/Staking.sol) | Stake a token and earn rewards paid in the same token |
| [`Farming`](contracts/Farming.sol) | Deposit LP tokens and earn a separate reward token |
| [`RewardPool`](contracts/RewardPool.sol) | Shared base for both: reward-per-share accumulator, so payouts cost the same gas for 10 or 10,000 users |
| [`ERC20Locker`](contracts/Locker.sol) | Lock a token for 3, 6, 9 or 12 months |
| [`Voting`](contracts/Voting.sol) | Yes/no vote weighted by an ERC20Votes token, with a snapshot so tokens can't vote twice |

Solidity 0.8.24 · OpenZeppelin 5 · Hardhat · 27 tests

## Run the tests

```bash
npm install
npm test
```

## Layout

```
contracts/      fixed contracts (+ mocks/ for tests)
test/           Hardhat tests, including one regression test per audit finding
legacy/         the original 2022 contracts, unchanged
GojiSwap-main/  React swap UI (React 17, Redux, web3modal), 2021
AUDIT.md        findings and fixes
```

## Front end

`GojiSwap-main/` is the original 2021 React app with wallet connection through web3modal. Its dependencies are from 2021 and need an older Node (14/16) to run:

```bash
cd GojiSwap-main && npm install && npm start
```

## Author

M. Armaghan Raza · [GitHub](https://github.com/ArmaghanRazaChaudhary) · [LinkedIn](https://www.linkedin.com/in/armaghan-raza)
