// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IStrategy.sol";

contract Brewery is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    struct UserInfo {
        uint256 depositAmt;
        uint256 lastUpdate;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public userInfo;
    address[] public userList; 

    StratCandidate public stratCandidate;
    IStrategy public strategy;
    uint256 public approvalDelay;
    uint256 public rewardPerBlock = 300; // 300 / 1000 = 0.3 (~30% APR)
    uint256 public multiplier = 1000;
    uint256 public startBlock;
    uint256 public endBlock;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    event Deposit(address user, uint256 amount, uint256 shares);
    event Withdraw(address user, uint256 shares);

     function initialize(
        IStrategy _strategy,
        string memory _name,
        string memory _symbol,
        uint256 _approvalDelay,
        uint256 _multiplier,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _rewardPerBlock
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        __ReentrancyGuard_init();
        strategy = _strategy;
        approvalDelay = _approvalDelay;
        multiplier = _multiplier;
        startBlock = _startBlock;
        endBlock = _endBlock;
        rewardPerBlock = _rewardPerBlock;
    }

    function want() public view returns (IERC20Upgradeable) {
        return IERC20Upgradeable(strategy.want());
    }

    function balance() public view returns (uint) {
        return want().balanceOf(address(this)) + IStrategy(strategy).balanceOf();
    }

    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
    }

    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance() * 1e18 / totalSupply();
    }

    function depositAll() external {
        deposit(want().balanceOf(msg.sender));
    }

    function deposit(uint _amount) public nonReentrant {
        strategy.beforeDeposit();

        uint256 _pool = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);
        earn();
        uint256 _after = balance();
        _amount = _after - _pool; // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalSupply()) / _pool;
        }

        UserInfo storage user = userInfo[msg.sender];
        if(user.depositAmt > 0){
            user.rewardDebt = getUserRewards(msg.sender);
        }else{
            userList.push(msg.sender);
        }
        user.depositAmt = user.depositAmt + _amount;
        user.lastUpdate = block.number;

        _mint(msg.sender, shares);
        emit Deposit(msg.sender, _amount, shares);
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

    function earn() public {
        uint _bal = available();
        want().safeTransfer(address(strategy), _bal);
        strategy.deposit();
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public {
        uint256 r = (balance() * _shares) / totalSupply();
        _burn(msg.sender, _shares);

        uint b = want().balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r - b;
            strategy.withdraw(_withdraw);
            uint _after = want().balanceOf(address(this));
            uint _diff = _after - b;
            if (_diff < _withdraw) {
                r = b + _diff;
            }
        }

        UserInfo storage user = userInfo[msg.sender];
        if(user.depositAmt > 0){
            user.rewardDebt = getUserRewards(msg.sender);
        }

        if(user.depositAmt <= r) {
            user.depositAmt = 0;
            removeUser(msg.sender);
        }else{
            user.depositAmt = user.depositAmt - r;
        }
        user.lastUpdate = block.number;

        want().safeTransfer(msg.sender, r);

        emit Withdraw(msg.sender, _shares);
    }

    function proposeStrat(address _implementation) public onlyOwner {
        require(address(this) == IStrategy(_implementation).vault(), "Proposal not valid for this Vault");
        require(want() == IStrategy(_implementation).want(), "Different want");
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewStratCandidate(_implementation);
    }

    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime + approvalDelay < block.timestamp, "Delay has not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        strategy.retireStrat();
        strategy = IStrategy(stratCandidate.implementation);
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;

        earn();
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(msg.sender, amount);
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
