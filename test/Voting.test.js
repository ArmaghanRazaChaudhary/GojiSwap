const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, mine } = require("@nomicfoundation/hardhat-network-helpers");

const E = (n) => ethers.parseEther(String(n));
const Outcome = { Passed: 0, Rejected: 1, Tie: 2 };

async function deploy() {
  const [owner, alice, bob, carol] = await ethers.getSigners();
  const gov = await (await ethers.getContractFactory("MockVotesToken")).deploy();
  for (const [s, n] of [[alice, 60], [bob, 30], [carol, 10]]) {
    await gov.mint(s, E(n));
    await gov.connect(s).delegate(s); // ERC20Votes counts power only once delegated
  }
  await mine(1);
  const voting = await (await ethers.getContractFactory("Voting")).deploy(gov);
  return { voting, gov, owner, alice, bob, carol };
}

describe("Voting", () => {
  // Regression: in the 2022 version endTime was 0 while voting was open,
  // so `block.timestamp <= votingEndTime` failed and nobody could ever vote.
  it("accepts votes while open and weighs them by token balance", async () => {
    const { voting, alice, bob, carol } = await loadFixture(deploy);
    await voting.startVoting();
    await voting.connect(alice).vote(false);
    await voting.connect(bob).vote(true);
    await voting.connect(carol).vote(true);
    await voting.endVoting();

    expect(await voting.votesFor()).to.equal(E(40));
    expect(await voting.votesAgainst()).to.equal(E(60));
    expect(await voting.result()).to.equal(Outcome.Rejected);
  });

  // Regression: the 2022 version used the voter's live ETH balance, so the same ETH
  // could vote again from a second wallet.
  it("tokens moved after the snapshot can't vote twice", async () => {
    const { voting, gov, alice, bob } = await loadFixture(deploy);
    await voting.startVoting();
    await voting.connect(alice).vote(true);
    await gov.connect(alice).transfer(bob, E(60));
    await voting.connect(bob).vote(true);
    await voting.endVoting();
    expect(await voting.votesFor()).to.equal(E(90)); // 60 + 30, not 60 + 90
  });

  it("one vote per address per round", async () => {
    const { voting, alice } = await loadFixture(deploy);
    await voting.startVoting();
    await voting.connect(alice).vote(true);
    await expect(voting.connect(alice).vote(true)).to.be.revertedWithCustomError(voting, "AlreadyVoted");
  });

  it("blocks the owner and wallets with no voting power", async () => {
    const { voting, owner } = await loadFixture(deploy);
    const [, , , , dave] = await ethers.getSigners();
    await voting.startVoting();
    await expect(voting.connect(owner).vote(true)).to.be.revertedWithCustomError(voting, "OwnerCannotVote");
    await expect(voting.connect(dave).vote(true)).to.be.revertedWithCustomError(voting, "NoVotingPower");
  });

  // Regression: the 2022 reset() left the old tallies in place.
  it("reset clears tallies and lets everyone vote in the next round", async () => {
    const { voting, alice, bob } = await loadFixture(deploy);
    await voting.startVoting();
    await voting.connect(alice).vote(true);
    await voting.endVoting();
    await voting.reset();

    expect(await voting.totalVotes()).to.equal(0);
    await voting.startVoting();
    await voting.connect(alice).vote(false);
    await voting.connect(bob).vote(true);
    await voting.endVoting();
    expect(await voting.votesAgainst()).to.equal(E(60));
    expect(await voting.votesFor()).to.equal(E(30));
  });

  it("reports a tie and enforces the round order", async () => {
    const { voting, gov, alice, bob, carol } = await loadFixture(deploy);
    await expect(voting.connect(alice).vote(true)).to.be.revertedWithCustomError(voting, "WrongState");
    await expect(voting.result()).to.be.revertedWithCustomError(voting, "WrongState");
    await gov.connect(bob).transfer(carol, E(20)); // bob 10, carol 30
    await mine(1);
    await voting.startVoting();
    await voting.connect(bob).vote(true);
    await voting.connect(carol).vote(true);
    await voting.endVoting();
    expect(await voting.result()).to.equal(Outcome.Passed);
    await voting.reset();
    await voting.startVoting();
    await voting.endVoting();
    expect(await voting.result()).to.equal(Outcome.Tie);
  });
});
