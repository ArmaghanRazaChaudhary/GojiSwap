const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const E = (n) => ethers.parseEther(String(n));

async function deploy() {
  const [owner, alice, bob, carol] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("MockERC20");
  const goji = await Token.deploy("Goji", "GOJI");
  const staking = await (await ethers.getContractFactory("Staking")).deploy();
  await staking.addToken(goji);

  for (const s of [owner, alice, bob, carol]) {
    await goji.mint(s, E(1000));
    await goji.connect(s).approve(staking, ethers.MaxUint256);
  }
  return { staking, goji, owner, alice, bob, carol };
}

describe("Staking", () => {
  it("splits rewards in proportion to stake", async () => {
    const { staking, goji, alice, bob } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(100));
    await staking.connect(bob).deposit(goji, E(300));
    await staking.distribute(goji, E(40));

    expect(await staking.pendingReward(goji, alice)).to.equal(E(10));
    expect(await staking.pendingReward(goji, bob)).to.equal(E(30));

    await expect(staking.connect(alice).claim(goji, ethers.ZeroAddress))
      .to.changeTokenBalance(goji, alice, E(10));
  });

  it("a late staker gets nothing from earlier rewards", async () => {
    const { staking, goji, alice, bob } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(100));
    await staking.distribute(goji, E(50));
    await staking.connect(bob).deposit(goji, E(100));

    expect(await staking.pendingReward(goji, alice)).to.equal(E(50));
    expect(await staking.pendingReward(goji, bob)).to.equal(0);
  });

  it("keeps earned rewards when topping up a stake", async () => {
    const { staking, goji, alice } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(100));
    await staking.distribute(goji, E(20));
    await staking.connect(alice).deposit(goji, E(100));
    expect(await staking.pendingReward(goji, alice)).to.equal(E(20));
  });

  // Regression: the 2022 version never reduced the user's stake on unstake,
  // so one small stake could be used to drain everyone else's tokens.
  it("cannot withdraw more than your own stake", async () => {
    const { staking, goji, alice, bob } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(500));
    await staking.connect(bob).deposit(goji, E(1));

    await staking.connect(bob).withdraw(goji, E(1));
    await expect(staking.connect(bob).withdraw(goji, E(1)))
      .to.be.revertedWithCustomError(staking, "InsufficientDeposit");
    await expect(staking.connect(bob).withdraw(goji, E(500)))
      .to.be.revertedWithCustomError(staking, "InsufficientDeposit");
    expect(await goji.balanceOf(staking)).to.equal(E(500));
  });

  // Regression: the 2022 version credited rewards without pulling any tokens in,
  // so claims were paid out of other users' stakes.
  it("every distributed reward is backed by tokens", async () => {
    const { staking, goji, owner, alice } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(100));
    await expect(staking.distribute(goji, E(30))).to.changeTokenBalance(goji, owner, -E(30));
    expect(await staking.reservedRewards(goji)).to.equal(E(30));
  });

  // Regression: emergencyWithdraw let the owner take user deposits.
  it("owner can only recover excess, never deposits or rewards", async () => {
    const { staking, goji, owner, alice } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(100));
    await staking.distribute(goji, E(10));
    await goji.transfer(staking, E(5)); // sent by mistake

    expect(await staking.excessOf(goji)).to.equal(E(5));
    await expect(staking.withdrawExcess(goji, E(6)))
      .to.be.revertedWithCustomError(staking, "ExceedsExcess");
    await expect(staking.withdrawExcess(goji, E(5))).to.changeTokenBalance(goji, owner, E(5));
  });

  it("withdraw and claim still work after a pool is disabled", async () => {
    const { staking, goji, alice } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(100));
    await staking.distribute(goji, E(10));
    await staking.setPoolEnabled(goji, false);

    await expect(staking.connect(alice).deposit(goji, E(1)))
      .to.be.revertedWithCustomError(staking, "PoolDisabled");
    await staking.connect(alice).claim(goji, ethers.ZeroAddress);
    await expect(staking.connect(alice).withdraw(goji, E(100))).to.changeTokenBalance(goji, alice, E(100));
  });

  it("claims can be paid to another address", async () => {
    const { staking, goji, alice, carol } = await loadFixture(deploy);
    await staking.connect(alice).deposit(goji, E(100));
    await staking.distribute(goji, E(7));
    await expect(staking.connect(alice).claim(goji, carol)).to.changeTokenBalance(goji, carol, E(7));
  });

  it("only the owner can run admin functions", async () => {
    const { staking, goji, alice } = await loadFixture(deploy);
    await expect(staking.connect(alice).addToken(alice))
      .to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
    await expect(staking.connect(alice).distribute(goji, 1))
      .to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
    await expect(staking.connect(alice).withdrawExcess(goji, 0))
      .to.be.revertedWithCustomError(staking, "OwnableUnauthorizedAccount");
  });

  it("rejects bad input", async () => {
    const { staking, goji, alice } = await loadFixture(deploy);
    await expect(staking.distribute(goji, E(1))).to.be.revertedWithCustomError(staking, "NoDepositors");
    await expect(staking.connect(alice).deposit(goji, 0)).to.be.revertedWithCustomError(staking, "ZeroAmount");
    await expect(staking.connect(alice).deposit(alice, 1)).to.be.revertedWithCustomError(staking, "PoolNotFound");
    await expect(staking.addToken(goji)).to.be.revertedWithCustomError(staking, "PoolExists");
  });

  it("credits only what arrives for fee-on-transfer tokens", async () => {
    const { staking, alice } = await loadFixture(deploy);
    const fee = await (await ethers.getContractFactory("MockFeeToken")).deploy();
    await staking.addToken(fee);
    await fee.mint(alice, E(100));
    await fee.connect(alice).approve(staking, ethers.MaxUint256);

    await staking.connect(alice).deposit(fee, E(100));
    const [amount] = await staking.users(fee, alice);
    expect(amount).to.equal(E(99));
    await staking.connect(alice).withdraw(fee, E(99)); // would revert if we had credited 100
  });
});
