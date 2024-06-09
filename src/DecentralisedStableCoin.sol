// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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

pragma solidity 0.8.19;

import { ERC20Burnable, ERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";


contract DecentralisedStableCoin is ERC20Burnable, Ownable{

    /*
    * @title DecentralizedStableCoin
    * @author Ikpong Joseph
    * Collateral: Exogenous
    * Minting (Stability Mechanism): Decentralized (Algorithmic)
    * Value (Relative Stability): Anchored (Pegged to USD) $1 = 1 DSC
    * Collateral Type: Crypto
    *
    * This will be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the
    DSCEngine smart contract logic.
    */

    // We're using the ERC20Burnable contract because of its burn function.
    // DecentralisedStableCoin will not explicitly inherit ERC20 since ERC20Burnable does.
    // We also import Ownable since we want the DSCEngine to own this DSC token contract.

    ////////////
    // Errors
    ///////////

    error DecentralisedStableCoin__AmountMustBeMoreThanZero();
    error DecentralisedStableCoin__BurnAmountExceedsBalance();
    error DecentralisedStableCoin__NotZeroAddress();

    ////////////
    // Functions
    ///////////

    ////////////
    //Constructor
    ///////////

    constructor() ERC20("DecentralisedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralisedStableCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralisedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
        // "super" means to use burn() from parent class, ERC20Burnable 
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralisedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}