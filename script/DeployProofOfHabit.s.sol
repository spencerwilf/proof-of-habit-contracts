// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {ProofOfHabit} from "../src/ProofOfHabit.sol";

contract DeployProofOfHabit is Script {
    function run() external returns (ProofOfHabit) {
        ProofOfHabit proofOfHabit;
        vm.startBroadcast();
        proofOfHabit = new ProofOfHabit();
        vm.stopBroadcast();
        return proofOfHabit;
    }
}
