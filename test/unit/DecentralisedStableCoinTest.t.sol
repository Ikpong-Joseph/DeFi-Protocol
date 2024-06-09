// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DecentralisedStableCoin} from "src/DecentralisedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";



contract DecentralisedStableCoinTest is StdCheats, Test{

    DecentralisedStableCoin public dsc;
    DSCEngine public dscEngine;


    address USER = makeAddr("user");
    uint256 public constant AMOUNT_DSC_TO_MINT = 100e18; 

    modifier onlyOwner() {
        require(msg.sender == address(dscEngine));
        _;
    }
    //////////
    // setUp
    //////////

    // DecentralisedStableCoin transfers ownership of itself to msg.sender
    // In this case address(this) = dsc.owner()
    // That is DecentralisedStableCoinTest owns DecentralisedStableCoin due to this setup


    function setUp() public {
        dsc = new DecentralisedStableCoin();
    }
        
    ///////////////
    // Mint Tests
    //////////////

    function testMintSuccessful() external {
        // Mint 100 DSC
        address to = USER; // Example recipient address

        // Call the mint function.
        // Expect it to not revert.
        dsc.mint(to, AMOUNT_DSC_TO_MINT);
        uint256 userDscBalanceAfterMint = dsc.balanceOf(to);

        // Verify that the recipient's balance has increased by the minted amount.
        assertEq(userDscBalanceAfterMint, AMOUNT_DSC_TO_MINT, "Recipient's balance should have increased by the minted amount");
    }

    function testCantMintDscToZeroAddress() external {
        // Mint 100 DSC
        address to = address(0); // Example recipient address

        // Call the mint function.
        // No need to vm.prank(dsc.owner()) since this contract owns DSC
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__NotZeroAddress.selector);
        dsc.mint(to, AMOUNT_DSC_TO_MINT);
    }

    function testCantMintZeroDsc() public {
        uint256 zeroDscToMint = 0;
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__AmountMustBeMoreThanZero.selector);
        
        dsc.mint(address(this), zeroDscToMint);
        
    }

    function testOnlyOwnerCanCallMint() external {
        vm.prank(USER);
        vm.expectRevert();
        dsc.mint(USER, AMOUNT_DSC_TO_MINT);
        
        
    }

    ///////////////
    // Burn Tests
    //////////////

    function testBurnSuccessful() external {
        // This works when address from = address(this)
        // ****** Why not when address from = USER? ******
        // Kept giving the error of "DecentralizedStableCoin__BurnAmountExceedsBalance()"
        // Even though console.log(dsc.balanceOf(from)) showed USER had minted DSC balance.
        
        uint256 amountToBurn = 50e18; // Burn 50 DSC
        address from = address(this); // Example sender address

        // Set the initial balance.
        vm.startPrank(address(dsc.owner()));
        dsc.mint(from, AMOUNT_DSC_TO_MINT);
        console.log(dsc.balanceOf(from));
        // vm.prank(USER);

        // Call the burn function.
        
        dsc.burn(amountToBurn);
        vm.stopPrank();

        uint256 dscBalanceAfterBurning = dsc.balanceOf(from);

        // Verify that the sender's balance has decreased by the burned amount.
        assertEq(dscBalanceAfterBurning, AMOUNT_DSC_TO_MINT - amountToBurn, "Sender's balance should have decreased by the burned amount");
    }

    function testCantBurnMoreDscThanYouHave() public {
        uint256 excessDscToBurn = 101e18;
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), AMOUNT_DSC_TO_MINT);
        vm.expectRevert();
        dsc.burn(excessDscToBurn);
        vm.stopPrank();
    }

    function testCantBurnZeroDsc() public {
        uint256 zeroDscToBurn = 0;
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), AMOUNT_DSC_TO_MINT);
        vm.expectRevert(DecentralisedStableCoin.DecentralisedStableCoin__AmountMustBeMoreThanZero.selector);
        dsc.burn(zeroDscToBurn);
        vm.stopPrank();
    }

    function testOnlyOwnerCanCallBurn() external {
        uint256 dscToBurn = 5e18;

        console.log("DSCTest is at ", address(this));
        console.log("The dsc.owner is ", address(dsc.owner()));
        vm.prank(address(this));
        dsc.mint(USER, AMOUNT_DSC_TO_MINT);
        vm.prank(USER);
        vm.expectRevert();
        dsc.burn(dscToBurn);
        
    }
    

    // function testTransferSuccessful() external {
    //     uint256 amountToTransfer = 50 * 1e18; // Transfer 50 DSC
    //     address from = address(0x123); // Example sender address
    //     address to = address(0x456); // Example recipient address

    //     // Set the initial balance for the sender.
    //     dsc._mint(from, amountToTransfer);

    //     // Call the transfer function.
    //     // Expect it to not revert.
    //     dsc.transfer(to, amountToTransfer);

    //     // Verify that the recipient's balance has increased by the transferred amount.
    //     assertEq(dsc.balanceOf(to), amountToTransfer, "Recipient's balance should have increased by the transferred amount");
    // }
}