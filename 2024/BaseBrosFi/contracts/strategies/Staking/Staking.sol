// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";

contract Staking is Ownable {
    IERC20 public wantToken;
    uint256 public rewardPerBlock = 300; // 300 / 1000 = 0.3 (~30% APR)
    uint256 public multiplier = 1000;
    uint256 public startBlock;
    uint256 public endBlock;

    struct UserInfo {
        uint256 depositAmt;
        uint256 lastUpdate;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public userInfo;
    address[] public userList; 

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor() Ownable (msg.sender) {
    }

    function initialize(
        IERC20 _wantToken,
        uint256 _multiplier,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) external onlyOwner {
        require(address(wantToken) == address(0), "Already initialized");
        require(_multiplier > 0, "Multiplier must be > 0");
        wantToken = _wantToken;
        multiplier = _multiplier;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    function depositAll() external {
        uint256 balance = wantToken.balanceOf(msg.sender);
        require(balance > 0, "No tokens to deposit");
        deposit(balance);
    }

    function deposit(uint256 _amount) public {
        require(block.number >= startBlock && block.number <= endBlock, "Not within staking period");
        require(_amount > 0, "Amount must be > 0");

        wantToken.transferFrom(msg.sender, address(this), _amount);

        UserInfo storage user = userInfo[msg.sender];
        if(user.depositAmt > 0){
            user.rewardDebt = getUserRewards(msg.sender);
        }else{
            userList.push(msg.sender);
        }
        user.depositAmt = user.depositAmt + _amount;
        user.lastUpdate = block.number;

        emit Deposited(msg.sender, _amount);
    }

    function withdrawAll() external {
        UserInfo storage user = userInfo[msg.sender];
        withdraw(user.depositAmt);
    }

    function withdraw(uint256 _amount) public {
        require(_amount > 0, "Amount must be > 0");
        UserInfo storage user = userInfo[msg.sender];
        require(user.depositAmt >= _amount, "Insufficient balance");

        if (user.depositAmt > 0) {
            user.rewardDebt = getUserRewards(msg.sender);
        }

        user.depositAmt -= _amount;
        if(user.depositAmt == 0){
            removeUser(msg.sender);
        }
        user.lastUpdate = block.number;

        wantToken.transfer(msg.sender, _amount);

        emit Withdrawn(msg.sender, _amount);
    }

    function getUserRewards(address _userAddress) public view returns (uint256) {
        UserInfo storage user = userInfo[_userAddress];

        if(user.depositAmt == 0 && user.lastUpdate == 0){
            return 0;
        }

        uint256 elapsed = 0;
        if(block.number <= endBlock){
            elapsed = block.number - user.lastUpdate;
        }else{
            elapsed = endBlock - user.lastUpdate;
        }
        uint256 rewards = user.rewardDebt + (user.depositAmt * rewardPerBlock * elapsed);
        return rewards;
    }

    function removeUser(address _user) internal {
        uint256 index = userList.length;
        for (uint256 i = 0; i < userList.length; i++) {
            if (userList[i] == _user) {
                index = i;
                break;
            }
        }
        if (index < userList.length) {
            userList[index] = userList[userList.length - 1];
            userList.pop();
        }
    }

    function setRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        for (uint256 i = 0; i < userList.length; i++) {
            address userAddr = userList[i];
            UserInfo storage user = userInfo[userAddr];
            if (user.depositAmt > 0) {
                user.rewardDebt = getUserRewards(msg.sender);
                user.lastUpdate = block.number;
            }
        }

        rewardPerBlock = _rewardPerBlock;
    }

    function setRewardBlocks(uint256 _startBlock, uint256 _endBlock) external onlyOwner {
        require(_endBlock > block.number, "End block must be in the future");
        startBlock = _startBlock;
        endBlock = _endBlock;
    }
}
