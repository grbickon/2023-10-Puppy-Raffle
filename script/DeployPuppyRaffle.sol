// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import {Script} from "forge-std/Script.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";

contract DeployPuppyRaffle is Script {
    function run(uint256 entranceFee, address feeAddress, uint256 raffleDuration) public returns (PuppyRaffle) {
        vm.broadcast();
        PuppyRaffle puppyRaffle = new PuppyRaffle(
            entranceFee,
            feeAddress,
            raffleDuration
        );
        return puppyRaffle;
    }
}
