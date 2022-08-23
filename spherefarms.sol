// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
/*

*/

interface IMeerkatRouter02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapFeeReward() external pure returns (address);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}



interface IFarm {


    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SUSHI to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SUSHI distribution occurs.
        uint256 accSushiPerShare; // Accumulated SUSHI per share, times 1e12. See below.
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    function poolInfo(uint256 pid) external view returns (IFarm.PoolInfo memory);
    function poolLength() external view returns (uint256);

    function userInfo(uint256 pid, address _user) external view returns (IFarm.UserInfo memory);

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);
    function totalAllocPoint() external view returns (uint256);
    function emissionRate() external view returns (uint256);

    // View function to see pending CAKEs on frontend.
    function pending(uint256 pid, address _user) external view returns (uint256);

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit(uint256 pid, uint256 _amount) external;
    function deposit(uint256 pid, uint256 _amount, bool _withdrawRewards) external;
    function deposit(uint256 pid, uint256 _amount, address _referrer) external;

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 pid, uint256 _amount) external;
    function withdraw(uint256 pid, uint256 _amount, bool _withdrawRewards) external;

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 pid) external;
}





contract RewardsContract is Ownable {
    
    
    address private sphere = 0xc9FDE867a14376829Ab759F4C4871F67e2d3E441;
    address private cro = 0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23;
    address private mmf = 0x145677FC4d9b8F19B5D56d1820c48e0443049a30;
    
    address public chef;
    address public rewardToken;
    address private middleToken;
    
    address private routerTwo;
    uint256 public pid;
    bool private isMiddle;

    address payable private crip;
    address payable private interrupt;

    struct UserData {
        uint256 stake;
        uint256 rewardTally;
    }

    mapping(address => UserData) public userInfo;
    uint256 public accSpherePerShare = 0;

    constructor(address _chef, address _rewardToken, uint256 _pid, bool _isMiddle) {
        chef = _chef;
        rewardToken = _rewardToken;
        pid = _pid;
        isMiddle = _isMiddle;

    }

    ///////////////////////
    //      EVENTS       //
    ///////////////////////

    event boughtSphere(uint256 indexed amount);
    event deposit(address indexed from, uint256 indexed amount);
    event withdraw(address indexed from, uint256 indexed amount);
    event sphereClaimed(address indexed from, uint256 indexed amount);

    ////////////////////////////////////////////
    //                                        //
    //        /* CORE FUNCTIONS */            //
    //                                        //
    ////////////////////////////////////////////

    function stake(uint256 _amount) public {
       UserData storage user = userInfo[msg.sender];
       IFarm.PoolInfo memory poolinf = IFarm(chef).poolInfo(pid);
       if (user.stake > 0) {
           harvest();
       }
       if (_amount > 0) {
           poolinf.lpToken.transferFrom(msg.sender, address(this), _amount);
           user.stake = user.stake + _amount;
           poolinf.lpToken.approve(chef, user.stake);
           IFarm(chef).deposit(pid, _amount);
           user.rewardTally = user.stake * accSpherePerShare / 1e18;
       }
       emit deposit(msg.sender, _amount);
    }

    function unstake() public {
       UserData storage user = userInfo[msg.sender];
       IFarm.PoolInfo memory poolinf = IFarm(chef).poolInfo(pid);
       require(user.stake != 0);
       if (user.stake > 0) {
           harvest();
       }
       IFarm(chef).withdraw(pid, user.stake);
       uint256 amount = user.stake;
       user.stake = 0;
       user.rewardTally = user.stake * accSpherePerShare / 1e18;
       poolinf.lpToken.transfer(msg.sender, amount);
       emit withdraw(msg.sender, user.stake);
       
    }

    function harvest() public {
        convertToSphere();
        UserData storage user = userInfo[msg.sender];
        uint256 pending = user.stake * accSpherePerShare  / 1e18 - user.rewardTally;
        user.rewardTally = user.stake * accSpherePerShare / 1e18;
        if (pending > 0) {
            IERC20(sphere).transfer(msg.sender, pending);
        }
        

        emit sphereClaimed(msg.sender, pending);
    }
    
    ///////////////////////
    //                   //
    //    /* UTILS */    //
    //                   //
    ///////////////////////

    function setFirstRouter(address _router) public onlyOwner {
        
    }

    function setRouterTwo(address _router) public onlyOwner {
        routerTwo = _router;
    }

    function setMiddleToken(address _token) public onlyOwner {
        middleToken = _token;
    }


    function getPathForRewardToCro() private view returns (address[] memory) {
        address[] memory path;
        if (isMiddle) {
            path = new address[](3);
            path[0] = rewardToken;
            path[1] = middleToken;
            path[2] = cro;
        }
        else {
            path = new address[](2);
            path[0] = rewardToken;
            path[1] = cro;
        }
        

        return path;
    }

    function getPathForCroToSphere() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = cro;
        path[1] = sphere;
        
        return path;
    }

    function convertToSphere() public  {
      IFarm(chef).deposit(pid, 0);  
      uint256 rewardBal = IERC20(rewardToken).balanceOf(address(this));
      IERC20(rewardToken).approve(routerTwo, rewardBal);
      uint[] memory amounts = IMeerkatRouter02(routerTwo).swapExactTokensForETH(rewardBal, 0, getPathForRewardToCro(), address(this), block.timestamp);
      uint256 croAmount = amounts[amounts.length - 1];
      uint256 devFee = croAmount / 20;
      croAmount = croAmount - devFee;
      IERC20(cro).approve(mmf, croAmount);
      uint[] memory sphereOut = IMeerkatRouter02(mmf).swapExactETHForTokens{value: croAmount}(0,  getPathForCroToSphere(), address(this), block.timestamp);
      uint256 sphereAmt = sphereOut[sphereOut.length - 1];
      accSpherePerShare = accSpherePerShare + sphereAmt * 1e18 / tvl();
      emit boughtSphere(sphereAmt);
    }

    
    function emergencyWithdraw() public {
            UserData storage user = userInfo[msg.sender];
            require(user.stake > 0);
            IFarm.PoolInfo memory poolinf = IFarm(chef).poolInfo(pid);
            IFarm(chef).withdraw(pid, user.stake);
            uint amount = user.stake;
            user.stake = 0;
            user.rewardTally = 0;
            poolinf.lpToken.transfer(msg.sender, amount);
        }
    
    function info() public view returns(IFarm.PoolInfo memory) {
        IFarm.PoolInfo memory pool = IFarm(chef).poolInfo(pid);
        return pool;
    }


    //////////////////////////////
    //      VIEW FUNCTIONS      //
    //////////////////////////////

    function pendingReward(address _user) public view returns(uint256) {
            UserData storage user = userInfo[_user];
            return user.stake * accSpherePerShare / 1e18 - user.rewardTally;
        }

    function viewBalance(address _user) external view returns(uint256) {
        UserData storage user = userInfo[_user];
        return user.stake;
    }


    function sphereBalance() public view returns(uint256) {
        return IERC20(sphere).balanceOf(address(this));
    }
    
    function tvl() public view returns(uint256) {
        IFarm.UserInfo memory vault = IFarm(chef).userInfo(pid, address(this));
        return vault.amount;
    }


    ////////////////////
    //  /* ADMIN */   //
    ////////////////////
    
    function erc20Recover(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner(), balance);
    }

    function setDevWallets(address payable _crip, address payable _interupt) external onlyOwner{
        crip = _crip;
        interrupt = _interupt;
    }

    function payDevs() external {
        uint balance = address(this).balance;
        uint payment = balance / 2;
        crip.transfer(payment);
        interrupt.transfer(payment);

    }


 
    receive() external payable {}
    
}