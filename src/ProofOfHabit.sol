// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ProofOfHabit is ReentrancyGuard {
    ////////////
    // Errors //
    ////////////

    error ProofOfHabit__TimeNotPassed();
    error ProofOfHabit__CallerNotProposer();
    error ProofOfHabit__CallerNotLossAddress();
    error ProofOfHabit__UserCheckedInToday();
    error ProofOfHabit__ProposalCompleted();
    error ProofOfHabit__NotEnoughLockup();
    error ProofOfHabit__NotEnoughHabitDays();
    error ProofOfHabit__NotEnoughCheckIns();
    error ProofOfHabit__CheckInPeriodNotOver();
    error ProofOfHabit__EnoughCheckedInDays();
    error ProofOfHabit__HabitAlreadyCompletedOrFailed();

    //////////////////////////////////////
    // Immutable and constant variables //
    //////////////////////////////////////

    uint256 private constant MIN_LOCKUP = 0.01 ether;
    uint256 private constant MIN_HABIT_DAYS = 3;

    /////////////
    // Structs //
    /////////////

    struct Habit {
        uint256 id;
        string title;
        uint256 expiry;
        uint256 howManyDays;
        address proposer;
        uint256 amount;
        address lossAddress;
        bool completed;
        bool failed;
        bool successful;
        uint256 checkedInDays;
        uint256 lastCheckIn;
    }

    ////////////////////////
    // Storage variables //
    ///////////////////////

    mapping(address => Habit[]) public userHabits;

    ////////////
    // Events //
    ////////////

    event HabitCreated(uint256 indexed id, address indexed proposer, string title);
    event FundsReturned(uint256 indexed id, address indexed proposer);
    event CheckedIn(uint256 indexed id, address indexed proposer, uint256 indexed checkedInDays);
    event LossAddressClaimed(uint256 indexed id, address indexed proposer, address indexed lossAddress);

    /**
     * Creating a habit
     * @param title the name of the habit the user wants to pursue
     * @param howManyDays the amount of days the user wants to pursue the habit over
     * @param lossAddress the address the user's ETH is transferred to should they fail their habit
     * @dev function revert conditions:
     * - if the user sends less than 0.01 ETH
     * - if the user attempts to input a timeframe of less than 3 days
     *
     * @dev control flow of creating a habit:
     *
     * *** 1.) Habit id instantiation *** an id is instantiated by accessing the userHabits mapping value at the msg.sender's address.
     *
     * *** 2.) Habit struct instantiation ***
     *  the user inputs the name of their habit, how many days they would like to pursue it over and the address their ETH should be transferred to should they fail.
     * - expiry: the current timestamp plus the days they pass in. This is the amount of time that will have to pass for their habit to be considered completed.
     * - checkedInDays: the amount of times the user has checked in. This will eventually have to be equal or greater than the expiry
     * - lastCheckIn: used to ensure that the user can check in only once every 24 hours
     *
     * *** 3.) Storage updates ***
     *  The userHabits mapping is updated at the msg.sender's address (the new habit is pushed into the value array). The index of the habit and its id will always be equal, making lookup possible
     */
    function makeHabit(string memory title, uint256 howManyDays, address lossAddress) public payable {
        if (msg.value < MIN_LOCKUP) {
            revert ProofOfHabit__NotEnoughLockup();
        }

        if (howManyDays < MIN_HABIT_DAYS) {
            revert ProofOfHabit__NotEnoughHabitDays();
        }

        uint256 id = userHabits[msg.sender].length;

        Habit memory habit = Habit({
            id: id,
            title: title,
            expiry: block.timestamp + (howManyDays * 1 days),
            howManyDays: howManyDays,
            proposer: msg.sender,
            amount: msg.value,
            lossAddress: lossAddress,
            completed: false,
            failed: false,
            successful: false,
            checkedInDays: 0,
            lastCheckIn: block.timestamp - 1 days
        });

        userHabits[msg.sender].push(habit);
        emit HabitCreated(id, msg.sender, title);
    }

    /**
     * When a user checks in for their habit
     * @param id the id of the habit the client passes in. This will equal the index of the habit in the user habit mapping
     * @dev function revert conditions
     * - the caller of the function is not the owner of the proposal
     * - Less than one day has elapsed between the current block and the last check in
     *
     * @dev control flow for a user checking in
     *
     * *** 1.) the habit's checkedIn days is incremented ***
     * *** 2.) the last checkin is set to the current block timestamp ***
     * *** 3.) an event is emitted with the habit id, msg.sender and the new amount of checked in days ***
     */
    function userCheckIn(uint256 id) external {
        Habit storage habit = userHabits[msg.sender][id];

        if (msg.sender != habit.proposer) {
            revert ProofOfHabit__CallerNotProposer();
        }

        if (block.timestamp < habit.lastCheckIn + 1 days) {
            revert ProofOfHabit__UserCheckedInToday();
        }

        if (habit.successful || habit.failed) {
            revert ProofOfHabit__HabitAlreadyCompletedOrFailed();
        }

        habit.checkedInDays++;
        habit.lastCheckIn = block.timestamp;

        if (habit.checkedInDays >= habit.howManyDays) {
            habit.successful = true;
        }
        
        emit CheckedIn(id, msg.sender, habit.checkedInDays);
    }

    /**
     * Reclaiming ETH when a user completes a habit
     * @param id the id of the habit the client passes in. This will equal the index of the habit in the user habit mapping
     * @dev function revert conditions:
     * - the timestamp of the current block is not yet at the computed expiry time
     * - the caller of the function is not the owner of the proposal
     * - the habit has already been completed
     * - the amount of checked in days is less than the expiry casted to days
     *
     * @dev control flow of returning a user's funds
     *
     * *** 1.) if the habit passes validations, it is marked as complete and successful
     */
    function habitSuccessReturnFunds(uint256 id) external {
        Habit storage habit = userHabits[msg.sender][id];

        if (block.timestamp < habit.expiry) {
            revert ProofOfHabit__TimeNotPassed();
        }

        if (msg.sender != habit.proposer) {
            revert ProofOfHabit__CallerNotProposer();
        }

        if (habit.completed) {
            revert ProofOfHabit__ProposalCompleted();
        }

        if (habit.checkedInDays < habit.howManyDays) {
            revert ProofOfHabit__NotEnoughCheckIns();
        }

        habit.completed = true;

        (bool s,) = msg.sender.call{value: habit.amount}("");
        require(s);
        emit FundsReturned(id, msg.sender);
    }

    /**
     * When a loss address can claim a user's ETH
     * @param user the address of the user who originally created the habit.
     * @param id the id of the habit the client passes in. This will equal the index of the habit in the user habit mapping
     * @dev function revert conditions
     * - the one calling the function isnt the specified loss address
     * - Less than one day has elapsed between the current block and the last check in
     * - if the habit has been previously completed.
     * - if the user has enough checked in days
     *
     * @dev control flow for a user's ETH being transferred to a loss address
     *
     * *** 1.) the habit struct's `completed` and `failed` variables are set to true ***
     * *** 2.) the ETH associated with the habit that was deposited by the user is transferred to the calling loss address ***
     * *** 3.) an event is emitted with the habit id, the user's address whose habit has failed, and the calling loss address ***
     */
    function handleExpiry(address user, uint256 id) public {
        Habit storage habit = userHabits[user][id];

        if (msg.sender != habit.lossAddress) {
            revert ProofOfHabit__CallerNotLossAddress();
        }

        if (block.timestamp - habit.lastCheckIn < 1 days) {
            revert ProofOfHabit__CheckInPeriodNotOver();
        }

        if (habit.completed) {
            revert ProofOfHabit__ProposalCompleted();
        }

        if (habit.checkedInDays >= habit.howManyDays) {
            revert ProofOfHabit__EnoughCheckedInDays();
        }

        habit.failed = true;
        habit.completed = true;
        (bool s,) = habit.lossAddress.call{value: habit.amount}("");
        require(s);
        emit LossAddressClaimed(id, user, msg.sender);
    }

    //////////////////////////////
    // View and pure functions //
    /////////////////////////////

    function getExpiry(uint256 id) public view returns (uint256) {
        return userHabits[msg.sender][id].expiry;
    }

    function getHabit(uint256 id) public view returns (Habit memory) {
        return userHabits[msg.sender][id];
    }

    function checkExpiry(uint256 id) public view returns (bool) {
        Habit memory habit = userHabits[msg.sender][id];
        return (block.timestamp >= habit.expiry);
    }

    function getUserHabits() external view returns (Habit[] memory) {
        return userHabits[msg.sender];
    }

    function getMinLockUp() external pure returns (uint256) {
        return MIN_LOCKUP;
    }

    function getMinHabitDays() external pure returns (uint256) {
        return MIN_HABIT_DAYS;
    }

    //////////////////////////
    // Receive and Payable //
    ////////////////////////

    receive() external payable {
        revert("Do not send Ether directly");
    }

    fallback() external {
        revert("Function not supported");
    }
}
