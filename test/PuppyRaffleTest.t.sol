// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {DeployPuppyRaffle} from "../script/DeployPuppyRaffle.sol";
import {Base64} from "lib/base64/base64.sol";

contract PuppyRaffleTest is Test {
    DeployPuppyRaffle deployer;
    PuppyRaffle puppyRaffle;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    address feeAddress = address(99);
    uint256 duration = 1 days;

    event FeeAddressChanged(address newFeeAddress);

    function setUp() public {
        deployer = new DeployPuppyRaffle();
        puppyRaffle = deployer.run(entranceFee, feeAddress, duration);
    }

    //////////////////////
    /// EnterRaffle    ///
    /////////////////////

    function testCanEnterRaffle() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        assertEq(puppyRaffle.players(0), playerOne);
    }

    function testCantEnterWithoutPaying() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle(players);
    }

    function testCanEnterRaffleMany() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
        assertEq(puppyRaffle.players(0), playerOne);
        assertEq(puppyRaffle.players(1), playerTwo);
    }

    function testCantEnterWithoutPayingMultiple() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        vm.expectRevert("PuppyRaffle: Must send enough to enter raffle");
        puppyRaffle.enterRaffle{value: entranceFee}(players);
    }

    function testCantEnterWithDuplicatePlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 2}(players);
    }

    function testCantEnterWithDuplicatePlayersMany() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerOne;
        vm.expectRevert("PuppyRaffle: Duplicate player");
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);
    }

    //////////////////////
    /// Refund         ///
    /////////////////////
    modifier playerEntered(address player) {
        address[] memory players = new address[](1);
        players[0] = player;
        puppyRaffle.enterRaffle{value: entranceFee}(players);
        _;
    }

    function testCanGetRefund() public playerEntered(playerOne) {
        uint256 balanceBefore = address(playerOne).balance;
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(address(playerOne).balance, balanceBefore + entranceFee);
    }

    function testGettingRefundRemovesThemFromArray() public playerEntered(playerOne) {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);

        assertEq(puppyRaffle.players(indexOfPlayer), address(0));
    }

    function testOnlyPlayerCanRefundThemself() public playerEntered(playerOne) {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        vm.expectRevert("PuppyRaffle: Only the player can refund");
        vm.prank(playerTwo);
        puppyRaffle.refund(indexOfPlayer);
    }

    function testRevertIfPlayerAlreadyRefundedOrNotActive() public playerEntered(playerOne) {
        uint256 indexOfPlayer = puppyRaffle.getActivePlayerIndex(playerOne);
        vm.prank(playerOne);
        puppyRaffle.refund(indexOfPlayer);
        vm.expectRevert("PuppyRaffle: Player already refunded, or is not active");
        vm.prank(address(0));
        puppyRaffle.refund(indexOfPlayer);
    }

    //////////////////////
    /// getActivePlayerIndex         ///
    /////////////////////
    function testGetActivePlayerIndexManyPlayers() public playerEntered(playerOne) playerEntered(playerTwo){
        assertEq(puppyRaffle.getActivePlayerIndex(playerOne), 0);
        assertEq(puppyRaffle.getActivePlayerIndex(playerTwo), 1);
    }

    function testFuzzGetActivePlayerIndexNoPlayers(address addr) public {
        assertEq(puppyRaffle.getActivePlayerIndex(addr), 0);
    }

    //////////////////////
    /// selectWinner         ///
    /////////////////////
    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        puppyRaffle.enterRaffle{value: entranceFee * 4}(players);
        _;
    }

    function testCantSelectWinnerBeforeRaffleEnds() public playersEntered {
        vm.expectRevert("PuppyRaffle: Raffle not over");
        puppyRaffle.selectWinner();
    }

    function testCantSelectWinnerWithFewerThanFourPlayers() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        puppyRaffle.enterRaffle{value: entranceFee * 3}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("PuppyRaffle: Need at least 4 players");
        puppyRaffle.selectWinner();
    }

    function testSelectWinner() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.previousWinner(), playerFour);
    }

    function testSelectWinnerGetsPaid() public playersEntered {
        uint256 balanceBefore = address(playerFour).balance;

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPayout = ((entranceFee * 4) * 80 / 100);

        puppyRaffle.selectWinner();
        assertEq(address(playerFour).balance, balanceBefore + expectedPayout);
    }

    function testSelectWinnerGetsAPuppy() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.balanceOf(playerFour), 1);
    }

    function testPuppyUriIsRight() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        string memory expectedTokenUri =
            "data:application/json;base64,eyJuYW1lIjoiUHVwcHkgUmFmZmxlIiwgImRlc2NyaXB0aW9uIjoiQW4gYWRvcmFibGUgcHVwcHkhIiwgImF0dHJpYnV0ZXMiOiBbeyJ0cmFpdF90eXBlIjogInJhcml0eSIsICJ2YWx1ZSI6IGNvbW1vbn1dLCAiaW1hZ2UiOiJpcGZzOi8vUW1Tc1lSeDNMcERBYjFHWlFtN3paMUF1SFpqZmJQa0Q2SjdzOXI0MXh1MW1mOCJ9";

        puppyRaffle.selectWinner();
        assertEq(puppyRaffle.tokenURI(0), expectedTokenUri);
    }

    modifier manipulateRarity(uint256 seed) {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);
        vm.prevrandao(uint256(seed));
        // 63 high 62 med 61 low
        vm.prank(address(0));
        puppyRaffle.selectWinner();
        _;
    }

    function testSelectWinnerLegendaryRarityCanBeManipulated() public playersEntered manipulateRarity(63) {
        assertEq(puppyRaffle.previousWinner(), playerThree);
        assertEq(puppyRaffle.tokenIdToRarity(puppyRaffle.tokenOfOwnerByIndex(playerThree,0)),puppyRaffle.LEGENDARY_RARITY());
    }

    function testSelectWinnerRareRarityCanBeManipulated() public playersEntered manipulateRarity(62) {
        assertEq(puppyRaffle.previousWinner(), playerThree);
        assertEq(puppyRaffle.tokenIdToRarity(puppyRaffle.tokenOfOwnerByIndex(playerThree,0)),puppyRaffle.RARE_RARITY());
    }

    function testSelectWinnerCommonRarityCanBeManipulated() public playersEntered manipulateRarity(61) {
        assertEq(puppyRaffle.previousWinner(), playerFour);
        assertEq(puppyRaffle.tokenIdToRarity(puppyRaffle.tokenOfOwnerByIndex(playerFour,0)),puppyRaffle.COMMON_RARITY());
    }

    //////////////////////
    /// withdrawFees         ///
    /////////////////////
    function testCantWithdrawFeesIfPlayersActive() public playersEntered {
        vm.expectRevert("PuppyRaffle: There are currently players active!");
        puppyRaffle.withdrawFees();
    }

    function testWithdrawFees() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPrizeAmount = ((entranceFee * 4) * 20) / 100;

        puppyRaffle.selectWinner();
        puppyRaffle.withdrawFees();
        assertEq(address(feeAddress).balance, expectedPrizeAmount);
    }

    function testDeployScript() public {
        assertEq(puppyRaffle.entranceFee(), entranceFee);
        assertEq(puppyRaffle.feeAddress(), feeAddress);
        assertEq(puppyRaffle.raffleDuration(), duration);
    }

    function testOwnerCanChangeFeeAddress() public {
        address newFeeAddress = address(0xFEE);
        vm.prank(puppyRaffle.owner());
        vm.expectEmit();
        emit FeeAddressChanged(newFeeAddress);
        puppyRaffle.changeFeeAddress(newFeeAddress);
        assertEq(puppyRaffle.feeAddress(), newFeeAddress);
    }

    function testTokenURI() public  playersEntered manipulateRarity(63) {
        uint256 tokenId = puppyRaffle.tokenOfOwnerByIndex(playerThree,0);
        assertEq(puppyRaffle.previousWinner(), playerThree);
        uint256 rarity = puppyRaffle.tokenIdToRarity(tokenId);
        assertEq(rarity,puppyRaffle.LEGENDARY_RARITY());

        string memory imageURI = puppyRaffle.rarityToUri(rarity);
        string memory rareName = puppyRaffle.rarityToName(rarity);

        string memory expectedURI =  string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            puppyRaffle.name(),
                            '", "description":"An adorable puppy!", ',
                            '"attributes": [{"trait_type": "rarity", "value": ',
                            rareName,
                            '}], "image":"',
                            imageURI,
                            '"}'
                        )
                    )
                )
            )
        );

        string memory actualURI = puppyRaffle.tokenURI(tokenId);

        assertEq(expectedURI, actualURI);
    }

    function testRevertIfTokenDoesNotExist() public {
        vm.expectRevert("PuppyRaffle: URI query for nonexistent token");
        puppyRaffle.tokenURI(0);
    }

}
