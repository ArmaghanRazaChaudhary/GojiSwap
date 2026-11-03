# Review of the 2022 GojiSwap contracts

I wrote these contracts in 2021–22. In 2026 I reviewed them the way I would review a client's code before mainnet. The originals are kept unchanged in [`legacy/`](legacy/). The fixed versions are in [`contracts/`](contracts/), and every fix below has a regression test in [`test/`](test/).

## Summary

| # | Contract | Severity | Issue |
|---|---|---|---|
| 1 | Staking, Farming | Critical | `unstake` / `Unharvest` never reduce the caller's own stake, so anyone with a stake can drain the pool |
| 2 | Staking, Farming | Critical | `claim` multiplies by `DECIMAL` (1,000), so rewards are overpaid 1,000× |
| 3 | Staking, Farming | High | `distribute` credits rewards without receiving any tokens, so claims are paid from other users' deposits |
| 4 | Staking, Farming | High | `emergencyWithdraw` lets the owner take user deposits |
| 5 | Voting | High | Voting is impossible: `votingEndTime` is 0 while open, so `block.timestamp <= votingEndTime` always fails |
| 6 | Voting | High | Vote weight is the voter's live ETH balance, so the same ETH can vote again from another wallet |
| 7 | Locker | Medium | Lock checks the user's ETH balance instead of the token, and `>` blocks locking a full balance |
| 8 | Locker | Medium | `lock` is `payable`, so any ETH sent with it is stuck forever |
| 9 | Staking, Farming, Locker | Medium | ERC20 `transfer` / `transferFrom` return values unchecked (USDT-style tokens fail silently) |
| 10 | Farming | Low | `claimReward` view mixes the receiver's stake with the caller's checkpoint and skips scaling |
| 11 | Voting | Low | `reset` leaves old tallies; duplicate-voter check loops over every voter (gas DoS) |
| 12 | Locker | Low | `unlockAll` emits `Unlocked` after deleting the record, so the event always says 0 |
| 13 | Staking, Farming | Info | Did not compile: Solidity 0.4, a missing `;`, and imports of files not in the repo |

## Details and fixes

**1. Unstake drain (Critical).**
`unstake(_amount)` checks `stake > 0`, then transfers `_amount` and lowers `tokenTotalStaked`, but never lowers `StakeMap[token][msg.sender]`. Stake 1 wei, and you can withdraw the whole pool in repeated calls.
*Fix:* `withdraw` requires `amount <= user.amount` and subtracts it first.
*Test:* `Staking › cannot withdraw more than your own stake`.

**2. 1,000× reward overpayment (Critical).**
`claimable = stake * owedPerToken * DECIMAL / BIGNUMBER`, where `owedPerToken` is already scaled by `BIGNUMBER`. The extra `* 1000` pays 1,000 times the reward.
*Fix:* a single `PRECISION` (1e18) for the reward-per-share accumulator, with no other scaling.
*Test:* `Staking › splits rewards in proportion to stake` checks exact amounts.

**3. Unbacked rewards (High).**
`distribute(_reward)` only bumps the accumulator. No tokens come in, so claims are paid from depositors' principal.
*Fix:* `distribute` pulls the reward with `safeTransferFrom` and tracks it in `reservedRewards`.
*Test:* `Staking › every distributed reward is backed by tokens`.

**4. Owner can take deposits (High).**
`emergencyWithdraw(token, amount)` has no limit.
*Fix:* replaced by `withdrawExcess`, which can only move tokens above `deposits + reservedRewards`, for example tokens sent by mistake.
*Test:* `Staking › owner can only recover excess, never deposits or rewards`.

**5. Voting never opens (High).**
`vote` uses `validateVoting`: `require(block.timestamp <= votingEndTime)`. `votingEndTime` stays 0 until the owner ends the vote, so every vote reverts.
*Fix:* an explicit `Idle → Open → Ended` state machine.
*Test:* `Voting › accepts votes while open…`.

**6. Double voting with ETH balance (High).**
Weight was `msg.sender.balance` read at vote time. Vote, send the ETH to a second wallet, and vote again.
*Fix:* weight comes from an `IVotes` (ERC20Votes) token at a snapshot block taken when voting starts.
*Test:* `Voting › tokens moved after the snapshot can't vote twice`.

**7–8. Locker balance check and payable (Medium).**
`require(address(msg.sender).balance >= _amount)` compares ETH with a token amount. `token.balanceOf(user) > _amount` stops you locking your whole balance. `payable` traps ETH.
*Fix:* removed. `safeTransferFrom` is the real check, and `lock` is no longer payable.
*Test:* `ERC20Locker › can lock the entire token balance…`.

**9. Unchecked transfers (Medium).**
*Fix:* OpenZeppelin `SafeERC20` everywhere. Deposits and rewards also credit the amount actually received, so fee-on-transfer tokens can't make the books overstate the balance.
*Test:* `Staking › credits only what arrives for fee-on-transfer tokens`.

**10–12. Smaller issues.**
- `pendingReward` now uses the same math as `claim`. Test: `Farming › pendingReward matches what claim actually pays`.
- `reset` clears the tallies, and voters are tracked per round in a mapping instead of a loop.
- `Unlocked` is emitted with the real amount.

## Other changes

- Solidity 0.8.24 and OpenZeppelin 5. Custom errors instead of revert strings.
- Staking and Farming share one audited base, `RewardPool`. Staking pays rewards in the staked token, Farming in a separate reward token.
- Disabling a pool or token blocks new deposits only. Users can always withdraw and claim.
- `ReentrancyGuard` on every function that moves tokens.

## Function name changes (2022 → now)

| 2022 | Now |
|---|---|
| `stake` / `harvest` | `deposit` |
| `unstake` / `Unharvest` | `withdraw` |
| `claimReward` (view) | `pendingReward` |
| `emergencyWithdraw` | `withdrawExcess` |
| `Voting.vote(uint 0/1)` | `vote(bool)` |
