// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.1;

/******************* Imports **********************/
import "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/access/Ownable.sol";

/// @title A voting smart contract
/// @author M.Armaghan Raza
/// @notice This smart contract serves as a voting pool where users can vote against or in favor of a query.
contract Voting is Ownable, ReentrancyGuard {

    /******************* State Variables **********************/
    /// @notice This struct stores information regarding voter and their balance and voting decision.
    struct Voter {
        address _address;
        uint256 isInFavor;
        uint256 balance;
    }

    /// @notice An array to store and voters
    Voter[] private voters;

    /// @notice Onwer's address.
    address private _owner;

    /// @notice Stores voting start timestamp.
    uint256 private votingStartTime = 0;

    /// @notice Stores voting end timestamp.
    uint256 private votingEndTime = 0;

    /// @notice Stores total count of votes in favor of query.
    uint256 private votesInFavor = 0;

    /// @notice Stores total count of votes against the query.
    uint256 private votesAgainst = 0;

    constructor () {
        _owner = msg.sender;
    }

    /******************* Events **********************/
    event VotingStarted (address by, uint256 time);
    event VotingEnded (address by, uint256 totalVotes ,uint256 time);
    event VoteCasted (address voter, uint256 decision, uint256 time);
    event VotingReset (address by, uint256 time);
    event GetVoters (Voter[] voters);
    event GetTotalVotes (address viewer, uint256 votes, uint256 time);
    event GetTotalVoters (address viewer, uint256 voters, uint256 time);
    event GetVotesInFavor (uint256 votesInFavor);
    event GetVotesAgainst (uint256 votesAgainst);
    
    /******************* Modifiers **********************/
    modifier validateVoter () {
        // Prevent owner from voting himself 
        require (msg.sender != _owner, "Owner cannot cast votes!");
        
        bool isVoterValid = true;

        for (uint256 i = 0; i < voters.length; i++) {
            if (voters[i]._address == msg.sender) {
                isVoterValid = false;
                break;
            }
        }

        require(isVoterValid, "A user can only vote once!");
        _;
    }

    modifier votingStarted () {
        require (votingStartTime != 0, "Voting has not started yet!");
        _;
    }

    modifier votingEnded () {
        require(votingEndTime != 0 && votingStartTime <= block.timestamp 
        && block.timestamp >= votingEndTime, "Voting has not ended yet!");
        _;
    }

    modifier validateVoting () {
        require (block.timestamp <= votingEndTime, "Voting has ended!");
        _;
    }

    /******************* Admin Methods **********************/
    function startVoting () public onlyOwner {
        require(votingStartTime == 0, "Voting has already started");
        votingStartTime = block.timestamp;
        emit VotingStarted(msg.sender, block.timestamp);
    }

    function endVoting () public onlyOwner votingStarted {
        votingEndTime = block.timestamp;
        calculateResults();
        emit VotingEnded(msg.sender, votesInFavor + votesAgainst, block.timestamp);
    }

    function reset () public onlyOwner votingEnded {
        votingStartTime = 0;
        votingEndTime = 0;
        delete voters;
        emit VotingReset(msg.sender, block.timestamp);
    }

    function showVotersWithResults () public onlyOwner votingEnded returns (Voter[] memory) {
        emit GetVoters(voters);
        return voters;
    }

    /******************* Private Methods **********************/
    function calculateResults () private {
        for (uint256 i = 0; i < voters.length; i++) {
            if (voters[i].isInFavor == 1) {
                votesInFavor += voters[i].balance;
            } else {
                votesAgainst += voters[i].balance;
            }
        }
    }

    /******************* Public Methods **********************/
    function vote (uint256 _vote) public votingStarted validateVoter validateVoting {
        // Validating input
        require (_vote >= 0 && _vote <= 1,
        "Please enter either 0 for No or 1 for Yes ");
        voters.push(Voter(msg.sender, _vote, (msg.sender).balance));
        emit VoteCasted(msg.sender, _vote, block.timestamp);
    }

    function totalVoters () public votingEnded returns (uint256) {
        emit GetTotalVoters(msg.sender, voters.length, block.timestamp);
        return voters.length;
    }

    function getTotalVotes () public votingEnded returns (uint256) {
        uint256 totalVotes = votesInFavor + votesAgainst;
        emit GetTotalVotes(msg.sender, totalVotes, block.timestamp);
        return totalVotes;
    }

    function voteInFavor () public votingEnded returns (uint256) {
        emit GetVotesInFavor(votesInFavor);
        return votesInFavor;
    }

    function voteAgainst () public votingEnded returns (uint256) {
        emit GetVotesAgainst(votesAgainst);
        return votesAgainst;
    }

    function getVotingResults () public view returns (string memory) {
        if (votesInFavor > votesAgainst) {
            return "Majority is in Favor, Candidate WON!!!";
        } else if (votesInFavor < votesAgainst) {
            return "Majority is in Favor, Candidate LOST!!!";
        } else {
            return "Equal worth of votes on both sides, It's a DRAW!!!";
        }
    }
}
