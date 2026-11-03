const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const E = (n) => ethers.parseEther(String(n));

async function deploy() {
  const [owner, alice, bob] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("MockERC20");
  const lp = await Token.deploy("GOJI-ETH LP", "LP");
  const reward = await Token.deploy("Goji", "GOJI");
  const farming = await (await ethers.getContractFactory("Farming")).deploy();
  await farming.addPool(lp, reward);

  await reward.mint(owner, E(1000));
  await reward.approve(farming, ethers.MaxUint256);
  for (const s of [alice, bob]) {
    await lp.mint(s, E(1000));
    await lp.connect(s).approve(farming, ethers.MaxUint256);
  }
  return { farming, lp, reward, owner, alice, bob };
}

describe("Farming", () => {
  it("pays rewards in the reward token, not the LP token", async () => {
    const { farming, lp, reward, alice, bob } = await loadFixture(deploy);
    await farming.connect(alice).deposit(lp, E(100));
    await farming.connect(bob).deposit(lp, E(100));
    await farming.distribute(lp, E(50));

    await expect(farming.connect(alice).claim(lp, ethers.ZeroAddress))
      .to.changeTokenBalance(reward, alice, E(25));
    expect(await lp.balanceOf(farming)).to.equal(E(200));
  });

  it("returns the full LP deposit on withdraw", async () => {
    const { farming, lp, alice } = await loadFixture(deploy);
    await farming.connect(alice).deposit(lp, E(100));
    await expect(farming.connect(alice).withdraw(lp, E(100))).to.changeTokenBalance(lp, alice, E(100));
  });

  // Regression: the 2022 claimReward() view mixed the receiver's stake with msg.sender's
  // reward checkpoint and skipped the scaling, so it showed numbers 1e18 too large.
  it("pendingReward matches what claim actually pays", async () => {
    const { farming, lp, reward, alice, bob } = await loadFixture(deploy);
    await farming.connect(alice).deposit(lp, E(30));
    await farming.connect(bob).deposit(lp, E(70));
    await farming.distribute(lp, E(10));

    const shown = await farming.connect(bob).pendingReward(lp, alice);
    await expect(farming.connect(alice).claim(lp, ethers.ZeroAddress)).to.changeTokenBalance(reward, alice, shown);
    expect(shown).to.equal(E(3));
  });

  it("owner can't sweep LP deposits or unclaimed rewards", async () => {
    const { farming, lp, reward, alice } = await loadFixture(deploy);
    await farming.connect(alice).deposit(lp, E(100));
    await farming.distribute(lp, E(10));
    expect(await farming.excessOf(lp)).to.equal(0);
    expect(await farming.excessOf(reward)).to.equal(0);
    await expect(farming.withdrawExcess(lp, 1)).to.be.revertedWithCustomError(farming, "ExceedsExcess");
  });
});
