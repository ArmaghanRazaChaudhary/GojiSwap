// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title Voting
/// @author M. Armaghan Raza
/// @notice Yes/no vote weighted by governance-token balance. Weights come from a snapshot
///         taken when voting starts, so tokens bought or moved during the vote don't count.
contract Voting is Ownable {
    enum State {
        Idle,
        Open,
        Ended
    }

    enum Outcome {
        Passed,
        Rejected,
        Tie
    }

    /// @notice Token whose delegated voting power is used as vote weight (e.g. an OZ ERC20Votes token).
    IVotes public immutable votingToken;

    State public state;
    uint256 public round; // increments on every start, so each round has a fresh "has voted" set
    uint256 public snapshot; // block whose voting power is used for this round
    uint256 public votesFor;
    uint256 public votesAgainst;
    uint256 public voterCount;

    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event VotingStarted(uint256 indexed round, uint256 snapshot);
    event VoteCast(uint256 indexed round, address indexed voter, bool support, uint256 weight);
    event VotingEnded(uint256 indexed round, uint256 votesFor, uint256 votesAgainst);
    event VotingReset(uint256 indexed round);

    error WrongState(State expected, State actual);
    error AlreadyVoted();
    error NoVotingPower();
    error OwnerCannotVote();

    constructor(IVotes token) Ownable(msg.sender) {
        votingToken = token;
    }

    modifier inState(State expected) {
        if (state != expected) revert WrongState(expected, state);
        _;
    }

    /******************* Admin **********************/

    function startVoting() external onlyOwner inState(State.Idle) {
        round += 1;
        snapshot = block.number - 1; // getPastVotes needs a block that is already final
        state = State.Open;
        emit VotingStarted(round, snapshot);
    }

    function endVoting() external onlyOwner inState(State.Open) {
        state = State.Ended;
        emit VotingEnded(round, votesFor, votesAgainst);
    }

    /// @notice Clear the finished round so a new one can start.
    function reset() external onlyOwner inState(State.Ended) {
        votesFor = 0;
        votesAgainst = 0;
        voterCount = 0;
        state = State.Idle;
        emit VotingReset(round);
    }

    /******************* Voters **********************/

    function vote(bool support) external inState(State.Open) {
        if (msg.sender == owner()) revert OwnerCannotVote();
        if (hasVoted[round][msg.sender]) revert AlreadyVoted();

        uint256 weight = votingToken.getPastVotes(msg.sender, snapshot);
        if (weight == 0) revert NoVotingPower();

        hasVoted[round][msg.sender] = true;
        voterCount += 1;
        if (support) votesFor += weight;
        else votesAgainst += weight;
        emit VoteCast(round, msg.sender, support, weight);
    }

    /******************* Views **********************/

    function result() external view inState(State.Ended) returns (Outcome) {
        if (votesFor > votesAgainst) return Outcome.Passed;
        if (votesFor < votesAgainst) return Outcome.Rejected;
        return Outcome.Tie;
    }

    function totalVotes() external view returns (uint256) {
        return votesFor + votesAgainst;
    }
}
