// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol"; // forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit
import {VRFV2PlusClient} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from
    "../lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/AutomationCompatible.sol";

// error Raffle__SendMoreToEnterRaffle();
error Raffle__TransferFailed();
// error Raffle__RaffleNotOpen();
// error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

/**
 * @title A smample Raffle contract
 * @author Elene Urushadze
 * @notice This contract is for creating a sample raffle
 * @dev implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /* Enums */
    enum RaffleState {
        OPEN, // 0 as an uint
        CALCULATING // 1 as an uint

    }

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // how many seconds each lottery run. duration of the lottery in seconds
    address payable[] private s_players; // whoever wins, needs to pay money for participating
    uint256 private s_lastTimeStamp;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events - any time you update storage, you gotta emit an event */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN; // same as: s_raffleState = RaffleState(0);
    }

    // Functions - checks(requires), effects, interactions, pattern

    function enterRaffle() external payable {
        // enter raffle  & buy lottery ticket

        // checks (requires/conditionals)
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        // effect
        s_players.push(payable(msg.sender)); // we need payable keyword in order to have an address receive eth
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev this is the function that the chainlink nodes will call to see if the lottery is ready to have a winner picked
     * the following should be true in order to upkeep needed to be true
     * 1. time interval has passed between raffle runs
     * 2. the lottery is open
     * 3. the contract has eth (has player)
     * 4. implicitily your subscription has link
     * @param  - ignored
     * @return upkeepNeeded - true if its time to restart lottery
     * @return - ignored
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        /// block.timestamp - current approximate time (depending on blockchain) of block
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayer = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayer;
        return (upkeepNeeded, hex""); // hex'' is same as 0x0
    }

    // get a random number
    // use random number to pick a player
    // be automatically called - smart contracts cant automate themselves
    function performUpkeep() external {
        // raffle should pick a winner and rewards people
        // check to see if enough time has passed

        // checks (requires/conditionals)
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        // effect
        s_raffleState = RaffleState.CALCULATING; // since this is calculating, people will not be able to enter the raffle
        // get our random number (interactions part of the function)
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash, // max gas
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS, // how many confirmations node should wait before responding
            callbackGasLimit: i_callbackGasLimit, // how much gas to use for the callback request / max gas to spend
            numWords: NUM_WORDS, // number of random numbers
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256, /* requestId*/ uint256[] calldata randomWords) internal override {
        // effect - internal contract state changes
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); // this will wipe out everything in that s_players array and reset it to a brand new blank array
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(s_recentWinner);
        // interactions - external contract interactions
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // getter functions

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
