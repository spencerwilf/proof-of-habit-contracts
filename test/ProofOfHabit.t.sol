// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployProofOfHabit} from "../script/DeployProofOfHabit.s.sol";
import {ProofOfHabit} from "../src/ProofOfHabit.sol";

contract ProofOfHabitTest is Test {
    ProofOfHabit public proofOfHabit;

    uint256 private constant MINIMUM_DAYS_FOR_HABIT = 3;
    string private constant HABIT_NAME = "Get in shape";
    uint256 private constant HABIT_DURATION = 5;
    address private constant USER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address constant LOSS_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 private constant TEST_TIMESTAMP = 1697305959;

    modifier prankAndFundUser() {
        vm.prank(USER);
        vm.deal(USER, 0.01 ether);
        _;
    }

    modifier accountForChainId() {
        if (block.chainid != 11155111) {
            vm.warp(TEST_TIMESTAMP);
        }
        _;
    }

    modifier successfulHabit() {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        for (uint256 i = 0; i < HABIT_DURATION - 1; i++) {
            vm.warp(block.timestamp + 1 days);
            proofOfHabit.userCheckIn(0);
        }
        _;
    }

    function setUp() public returns (ProofOfHabit) {
        DeployProofOfHabit deployProofOfHabit = new DeployProofOfHabit();
        proofOfHabit = deployProofOfHabit.run();
        return proofOfHabit;
    }

    function testMinLockup() public {
        assertEq(0.01 ether, proofOfHabit.getMinLockUp());
    }

    function testMinDays() public {
        assertEq(MINIMUM_DAYS_FOR_HABIT, proofOfHabit.getMinHabitDays());
    }

    function testHabitCreation() public accountForChainId {
        assert(proofOfHabit.getUserHabits().length == 0);
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assert(proofOfHabit.getUserHabits().length == 1);
    }

    function testRevertsIfNotEnoughValueLocked() public {
        vm.expectRevert();
        proofOfHabit.makeHabit{value: 0.009 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
    }

    function testRevertsIfDurationIsntLongEnough() public {
        vm.expectRevert();
        proofOfHabit.makeHabit{value: 0.001 ether}(HABIT_NAME, 2, LOSS_ADDRESS);
    }

    function testHabitCreatesWithCorrectBalance() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(address(proofOfHabit).balance, 0.01 ether);
    }

    function testHabitCreatesWithCorrectTitle() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(keccak256(bytes(proofOfHabit.getUserHabits()[0].title)), keccak256(bytes(HABIT_NAME)));
    }

    function testHabitCreatesWithCorrectProposer() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(proofOfHabit.getUserHabits()[0].proposer, address(this));
    }

    function testHabitCreatesWithCorrectLossAddress() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(proofOfHabit.getUserHabits()[0].lossAddress, LOSS_ADDRESS);
    }

    function testHabitCreatesWithCorrectInProgressStatus() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(proofOfHabit.getUserHabits()[0].completed, false);
        assertEq(proofOfHabit.getUserHabits()[0].failed, false);
        assertEq(proofOfHabit.getUserHabits()[0].successful, false);
    }

    function testHabitCreatesWithCorrectCheckedInDays() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(proofOfHabit.getUserHabits()[0].checkedInDays, 1);
    }

    function testHabitCreatesWithCorrectLastCheckIn() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(proofOfHabit.getUserHabits()[0].lastCheckIn, block.timestamp);
    }

    function testUserCanCheckIn() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        vm.warp(block.timestamp + 25 hours);
        proofOfHabit.userCheckIn(0);
        assertEq(proofOfHabit.getUserHabits()[0].checkedInDays, 2);
        assertEq(proofOfHabit.getUserHabits()[0].lastCheckIn, block.timestamp);
    }

    function testUserCantCheckInWithinADayOfPreviouslyCheckingIn() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        vm.expectRevert(ProofOfHabit.ProofOfHabit__UserCheckedInToday.selector);
        proofOfHabit.userCheckIn(0);
    }

    function testUsersEthTransfersToLossAddressIfMoreThanADayHasElapsed() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        for (uint256 i = 0; i < HABIT_DURATION - 2; i++) {
            vm.warp(block.timestamp + 1 days);
            proofOfHabit.userCheckIn(0);
        }
        vm.warp(block.timestamp + 2 days);
        proofOfHabit.userCheckIn(0);
        assertEq(proofOfHabit.getUserHabits()[0].lossAddress.balance, proofOfHabit.getUserHabits()[0].amount);
    }

    function testUserCantCheckInForACompletedHabit() public accountForChainId successfulHabit {
        vm.expectRevert(ProofOfHabit.ProofOfHabit__HabitAlreadyCompletedOrFailed.selector);
        proofOfHabit.userCheckIn(0);
    }

    function testHabitSuccessFlipsToTrueAfterEnoughCheckIns() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        assertEq(proofOfHabit.getUserHabits()[0].successful, false);
        for (uint256 i = 0; i < HABIT_DURATION - 1; i++) {
            vm.warp(block.timestamp + 1 days);
            proofOfHabit.userCheckIn(0);
        }
        assertEq(proofOfHabit.getUserHabits()[0].successful, true);
    }

    function testUserCanWithdrawEthAfterSuccessfulHabit() public accountForChainId {
        vm.deal(USER, 0.01 ether);
        vm.startPrank(USER);
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        for (uint256 i = 0; i < HABIT_DURATION - 1; i++) {
            vm.warp(block.timestamp + 1 days);
            proofOfHabit.userCheckIn(0);
        }
        vm.warp(block.timestamp + (HABIT_DURATION * 1 days));
        assertEq(proofOfHabit.getUserHabits()[0].amount, 0.01 ether);
        proofOfHabit.habitSuccessReturnFunds(0);
        assertEq(USER.balance, 0.01 ether);
        assertEq(proofOfHabit.getUserHabits()[0].completed, true);
        vm.stopPrank();
    }

    function testUserCantRetrieveETHForCompletedHabit() public accountForChainId successfulHabit {
        proofOfHabit.habitSuccessReturnFunds(0);
        vm.expectRevert(ProofOfHabit.ProofOfHabit__ProposalCompleted.selector);
        proofOfHabit.habitSuccessReturnFunds(0);
    }

    function testUserCantWithdrawWithoutEnoughCheckIns() public accountForChainId {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        for (uint256 i = 0; i < HABIT_DURATION - 2; i++) {
            // Adjusted loop condition to -2 as checkedInDays starts at 1
            vm.warp(block.timestamp + 1 days);
            proofOfHabit.userCheckIn(0);
        }
        vm.warp(block.timestamp + (HABIT_DURATION * 1 days)); // This line simulates the total habit duration passing
        vm.expectRevert(ProofOfHabit.ProofOfHabit__NotEnoughCheckIns.selector);
        proofOfHabit.habitSuccessReturnFunds(0); // This line should revert due to not enough check-ins
    }

    function testLossAddressCanWithdrawUsersFunds() public {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        for (uint256 i = 0; i < HABIT_DURATION - 2; i++) {
            vm.warp(block.timestamp + 1 days);
            proofOfHabit.userCheckIn(0);
        }
        vm.warp(block.timestamp + 2 days);
        vm.prank(LOSS_ADDRESS);
        proofOfHabit.lossAddressClaim(address(this), 0);
        assertEq(LOSS_ADDRESS.balance, 0.01 ether);
    }

    function testOnlyLossAddressCanWithdrawUserFunds() public {
        proofOfHabit.makeHabit{value: 0.01 ether}(HABIT_NAME, HABIT_DURATION, LOSS_ADDRESS);
        for (uint256 i = 0; i < HABIT_DURATION - 2; i++) {
            vm.warp(block.timestamp + 1 days);
            proofOfHabit.userCheckIn(0);
        }
        vm.warp(block.timestamp + 2 days);
        vm.prank(USER);
        vm.expectRevert(ProofOfHabit.ProofOfHabit__CallerNotLossAddress.selector);
        proofOfHabit.lossAddressClaim(address(this), 0);
    }

    fallback() external payable {}
    receive() external payable {}
}
