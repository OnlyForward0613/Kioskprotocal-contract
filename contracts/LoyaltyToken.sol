pragma solidity ^0.4.11;

import "zeppelin-solidity/contracts/token/StandardToken.sol";
import "./LoyaltyTokenRegistry.sol";

/** @title Loyalty token that merchants can create and accept in place of Ether. */
contract LoyaltyToken is StandardToken {
    string public name;                         // Set the name for display purposes.
    string public symbol;                       // Set the symbol for display purposes.
    uint256 public decimals = 18;               // Amount of decimals for display purposes.
    address public registry;                    // The address of the registry used to create this contract.

    modifier only_checkout {
        require(LoyaltyTokenRegistry(registry).checkout() == msg.sender);
        _;
    }
    
    // Constructor
    function LoyaltyToken(
        string _name,
        string _symbol,
        address _owner,
        uint256 _totalSupply
    ) 
        public
    {
        name = _name;
        symbol = _symbol;
        registry = msg.sender;

        // Give the initial balance to the DIN owner.
        balances[_owner] = _totalSupply;
        totalSupply = _totalSupply;            
    }

    function transferFromCheckout(
        address _from,
        address _to,
        uint256 _value
    )
        public
        only_checkout
        returns (bool) 
    {
        // Allow the Checkout contract to spend a user's balance.
        balances[_to] = balances[_to].add(_value);
        balances[_from] = balances[_from].sub(_value);
        Transfer(_from, _to, _value);
        return true;
    }

}