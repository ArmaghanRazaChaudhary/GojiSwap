const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

const E = (n) => ethers.parseEther(String(n));
const MONTH = 30 * 24 * 60 * 60;

async function deploy() {
  const [owner, alice] = await ethers.getSigners();
  const token = await (await ethers.getContractFactory("MockERC20")).deploy("Goji", "GOJI");
  const locker = await (await ethers.getContractFactory("ERC20Locker")).deploy();
  await locker.addSupportedToken(token);
  await token.mint(alice, E(100));
  await token.connect(alice).approve(locker, ethers.MaxUint256);
  return { locker, token, owner, alice };
}

describe("ERC20Locker", () => {
  it("locks for the chosen number of months", async () => {
    const { locker, token, alice } = await loadFixture(deploy);
    await locker.connect(alice).lock(token, E(10), 3);
    const [amount, unlockAt] = await locker.locks(alice, token);
    expect(amount).to.equal(E(10));
    expect(unlockAt).to.equal((await time.latest()) + 3 * MONTH);
  });

  it("refuses to unlock early and allows it after expiry", async () => {
    const { locker, token, alice } = await loadFixture(deploy);
    await locker.connect(alice).lock(token, E(10), 6);
    await expect(locker.connect(alice).unlockAll(token)).to.be.revertedWithCustomError(locker, "StillLocked");

    await time.increase(6 * MONTH);
    await expect(locker.connect(alice).unlock(token, E(4))).to.changeTokenBalance(token, alice, E(4));
    expect((await locker.locks(alice, token))[0]).to.equal(E(6));
  });

  // Regression: the 2022 unlockAll deleted the record before emitting,
  // so the Unlocked event always reported 0.
  it("unlockAll emits the real amount and clears the lock", async () => {
    const { locker, token, alice } = await loadFixture(deploy);
    await locker.connect(alice).lock(token, E(10), 3);
    await time.increase(3 * MONTH);
    await expect(locker.connect(alice).unlockAll(token))
      .to.emit(locker, "Unlocked").withArgs(alice.address, await token.getAddress(), E(10));
    expect((await locker.locks(alice, token))[0]).to.equal(0);
  });

  // Regression: the 2022 version checked the user's ETH balance instead of the token
  // and required balance > amount, so locking your whole balance failed.
  it("can lock the entire token balance with zero ETH involved", async () => {
    const { locker, token, alice } = await loadFixture(deploy);
    await expect(locker.connect(alice).lock(token, E(100), 12)).to.changeTokenBalance(token, alice, -E(100));
  });

  it("rejects bad input", async () => {
    const { locker, token, alice } = await loadFixture(deploy);
    await expect(locker.connect(alice).lock(token, E(1), 4)).to.be.revertedWithCustomError(locker, "InvalidDuration");
    await expect(locker.connect(alice).lock(token, 0, 3)).to.be.revertedWithCustomError(locker, "ZeroAmount");
    await expect(locker.connect(alice).lock(alice, E(1), 3)).to.be.revertedWithCustomError(locker, "NotSupported");
    await locker.connect(alice).lock(token, E(1), 3);
    await expect(locker.connect(alice).lock(token, E(1), 3)).to.be.revertedWithCustomError(locker, "AlreadyLocked");
    await expect(locker.connect(alice).unlockAll(alice)).to.be.revertedWithCustomError(locker, "NoLock");
    await expect(locker.addSupportedToken(alice)).to.be.revertedWithCustomError(locker, "NotAContract");
  });

  it("disabling a token blocks new locks but never withdrawals", async () => {
    const { locker, token, alice } = await loadFixture(deploy);
    await locker.connect(alice).lock(token, E(10), 3);
    await locker.setTokenEnabled(token, false);
    await time.increase(3 * MONTH);
    await expect(locker.connect(alice).unlockAll(token)).to.changeTokenBalance(token, alice, E(10));
    await expect(locker.connect(alice).lock(token, E(1), 3)).to.be.revertedWithCustomError(locker, "NotSupported");
  });
});
