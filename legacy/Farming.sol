pragma solidity ^0.4.22;

/******************* Imports **********************/
import "./erc20interface.sol";
import "./safemath.sol";
import "./Ownable.sol";

/// @title A farming smart contract
/// @author M.Armaghan Raza
/// @notice This smart contract serves as a farming pool where users can farm against and get rewards.
/// @dev All function calls are currently implemented without side effects.
// @custom:experimental This contract is experimental.
contract Farming is Ownable {
    using SafeMath for uint;
    
    uint BIGNUMBER = 10**18;
    uint DECIMAL = 10**3;

    /******************* State Variables **********************/
    /// @notice This struct stores information regarding farming info details.
    struct farmingInfo {
        uint amount;
    }

    /// @notice This struct stores information regarding farming info details.
    struct rewardInfo {
        address _rewardTokenAddress;
    }    
    
    
    //allowed token addresses
    mapping (address => bool) public allowedTokens;
    
    // @notice tokenAddr to user to farm amount.
    mapping (address => mapping(address => farmingInfo)) public FarmMap;

    // @notice mapping for tokenAddress for Reward.
    mapping (address => rewardInfo) public rewardAddrMap;
    
    // @notice tokenAddr to user to remaining claimable amount per farm.
    mapping (address => mapping(address => uint)) public userCummRewardPerFarm;

    // @notice tokenAddr to cummulative per token reward since the beginning or time.
    mapping (address => uint) public tokenCummRewardPerFarm;

    // @notice tokenAddr to total token claimed.
    mapping (address => uint) public tokenTotalFarmed;
    
    // @notice Stores farm tokenAddress.
    address public StakeTokenAddr;
    
    constructor(address _tokenAddr) public{
        StakeTokenAddr= _tokenAddr;
    }

    /******************* Events **********************/
    event farmed(
        address _token,
        address sender,
        uint256 _amount
    );

    event claimed(
        address _token,
        address sender,
        uint256 _amount,
        address receiver
    );

    event unfarmed(
        address _token,
        address sender,
        uint256 _amount
    );

    /******************* Modifiers **********************/
    // @notice modifieer to validate TokenAddress.    
    modifier isValidToken(address _tokenAddr){
        require(allowedTokens[_tokenAddr]);
        _;
    }

    
    /******************* Admin Methods **********************/

    /// @notice Admin method to add LP Address Farming
    /// @param _tokenAddr LP address
    function addToken( address _tokenAddr) onlyOwner external {
        allowedTokens[_tokenAddr] = true;
    }
    
    /// @notice Admin method to remove LP Address Farming
    /// @param _tokenAddr LP address
    function removeToken( address _tokenAddr) onlyOwner external {
        allowedTokens[_tokenAddr] = false;
    }

    /// @notice Admin method to set rewardTokenAddress against the Lp Address Farming
    /// @param _tokenAddr LP address
    /// @param _rewardAddress rewardTokenAddress
    function rewardAddress(address _tokenAddr, address _rewardAddress) isValidToken(_tokenAddr)  external onlyOwner {
        rewardAddrMap[_tokenAddr]._rewardTokenAddress = _rewardAddress;
    }

    /// @notice Admin method to withdraw the escrowed amount from the contract
    /// @param _token Address of token to be enabled
    function emergencyWithdraw (address _tokenAddr, uint256 _amount) public onlyOwner {
       ERC20(_tokenAddr).transfer(msg.sender,_amount)
    }

    /// @notice Admin method to set pay out dividends to farmers, update how much per token each farmer can claim
    /// @param _reward the aggregate amount to be send to all farmers
    /// @param _tokenAddr the token that this dividend gets paied out in
    function distribute(uint _reward,address _tokenAddr) isValidToken(_tokenAddr) external onlyOwner returns (bool){
        require(tokenTotalFarmed[_tokenAddr] != 0);
        uint reward = _reward.mul(BIGNUMBER); //simulate floating point operations
        uint rewardAddedPerToken = reward.div(tokenTotalFarmed[_tokenAddr]);
        tokenCummRewardPerFarm[_tokenAddr] = tokenCummRewardPerFarm[_tokenAddr].add(rewardAddedPerToken);
        return true;
    }
    
    // /**
    // * production version
    // * @dev pay out dividends to farmers, update how much per token each farmer can claim
    // * @param _reward the aggregate amount to be send to all farmers
    // */
    
    // function distribute(uint _reward) isValidToken(msg.sender) external returns (bool){
    //     require(tokenTotalFarmed[msg.sender] != 0);
    //     uint reward = _reward.mul(BIGNUMBER);
    //     tokenCummRewardPerFarm[msg.sender] += reward/tokenTotalFarmed[msg.sender];
    //     return true;
    // } 

    /******************* Public Methods **********************/
    /// @notice This method to harvest a specific amount against LP Token
    /// @param  _amount the amount to be farmed
    /// @param _tokenAddr the token the user wish to harvest on
    function harvest(uint _amount, address _tokenAddr) isValidToken(_tokenAddr) external returns (bool){
        require(_amount != 0);
        require(ERC20(_tokenAddr).transferFrom(msg.sender,this,_amount));
        
        if (FarmMap[_tokenAddr][msg.sender].amount ==0){
            FarmMap[_tokenAddr][msg.sender].amount = _amount;
            userCummRewardPerFarm[_tokenAddr][msg.sender] = tokenCummRewardPerFarm[_tokenAddr];
        }else{
            claim(_tokenAddr, msg.sender);
            FarmMap[_tokenAddr][msg.sender].amount = FarmMap[_tokenAddr][msg.sender].amount.add( _amount);
        }
        tokenTotalFarmed[_tokenAddr] = tokenTotalFarmed[_tokenAddr].add(_amount);
        emit farmed(_tokenAddr, msg.sender, _amount);
        return true;
    }
    
    /// @notice This method to claim dividends for a particular token that user has farmed in
    /// @param  _tokenAddr the token that the claim is made on
    /// @param _receiver the address which the claim is paid to
    function claim(address _tokenAddr, address _receiver) isValidToken(_tokenAddr)  public returns (uint) {
        address token = rewardAddrMap[_tokenAddr]._rewardTokenAddress;
        uint stakedAmount = FarmMap[_tokenAddr][msg.sender].amount;
        //the amount per token for this user for this claim
        uint amountOwedPerToken = tokenCummRewardPerFarm[_tokenAddr].sub(userCummRewardPerFarm[_tokenAddr][msg.sender]);
        uint claimableAmount = stakedAmount.mul(amountOwedPerToken); //total amoun that can be claimed by this user
        claimableAmount = claimableAmount.mul(DECIMAL); //simulate floating point operations
        claimableAmount = claimableAmount.div(BIGNUMBER); //simulate floating point operations
        userCummRewardPerFarm[_tokenAddr][msg.sender]=tokenCummRewardPerFarm[_tokenAddr];
        if (_receiver == address(0)){
            require(ERC20(token).transfer(msg.sender,claimableAmount));
        } else {
           require(ERC20(token).transfer(_receiver,claimableAmount));
        }
        emit claimed(_tokenAddr, msg.sender, claimableAmount, _receiver);
        return claimableAmount;

    }

    /// @notice This method to public function to check the claim amount
    /// @param  _tokenAddr the token that the claim is made on
    /// @param _receiver the address which the claim is paid to
    function claimReward(address _tokenAddr, address _receiver) isValidToken(_tokenAddr)  public view returns (uint, uint, uint) {
        uint stakedAmount = FarmMap[_tokenAddr][_receiver].amount;
        //the amount per token for this user for this claim
        uint amountOwedPerToken = tokenCummRewardPerFarm[_tokenAddr].sub(userCummRewardPerFarm[_tokenAddr][msg.sender]);
        uint claimableAmount = stakedAmount.mul(amountOwedPerToken); //total amoun that can be claimed by this user
        // claimableAmount = claimableAmount.mul(DECIMAL); //simulate floating point operations
        // claimableAmount = claimableAmount.div(BIGNUMBER); //simulate floating point operations
        return (stakedAmount, amountOwedPerToken, claimableAmount);
    }

    /// @notice This method to unharvest a specific amount against LP Token
    /// @param  _amount the amount to be unfarmed
    /// @param _tokenAddr the token the user wish to harvest on
    function Unharvest(uint _amount, address _tokenAddr) isValidToken(_tokenAddr)  external returns(bool){
        require(FarmMap[_tokenAddr][msg.sender].amount >0 );
        claim(_tokenAddr, msg.sender);
        require(ERC20(_tokenAddr).transfer(msg.sender,_amount));
        tokenTotalFarmed[_tokenAddr] = tokenTotalFarmed[_tokenAddr].sub(_amount);
        emit unfarmed(_tokenAddr, msg.sender, _amount);
        return true;
    }
}
