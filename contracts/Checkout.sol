pragma solidity ^0.4.11;

import "./DINRegistry.sol";
import "./MarketToken.sol";
import "./Orders.sol";
import "./Resolver.sol";
import "./LoyaltyToken.sol";
import "./LoyaltyTokenRegistry.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";

contract Checkout {
    using SafeMath for uint256;

    DINRegistry public registry;
    Orders public orders;
    MarketToken public marketToken;
    LoyaltyTokenRegistry public loyaltyRegistry;

    uint16 constant EXTERNAL_QUERY_GAS_LIMIT = 4999;  // Changes to state require at least 5000 gas

    // Prevent Solidity "stack too deep" error.
    struct Order {
        uint256 DIN;
        uint256 quantity;
        uint256 totalPrice;
        uint256 priceValidUntil;
        uint256 affiliateReward;
        address affiliate;
        uint256 loyaltyReward;
        address loyaltyToken;
        address merchant;
        address owner;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // Log Solidity errors
    event LogError(string error);

    /** @dev Constructor.
      * @param _registry The DIN Registry contract address.
      * @param _orders The Orders contract address.
      * @param _token The Market Token contract address.
      * @param _loyaltyRegistry The Loyalty Token Registry contract address.
      */
    function Checkout(
        DINRegistry _registry,
        Orders _orders,
        MarketToken _token,
        LoyaltyTokenRegistry _loyaltyRegistry
    ) public {
        registry = _registry;
        orders = _orders;
        marketToken = _token;
        loyaltyRegistry = _loyaltyRegistry;
    }

    /** @dev Buy a product.
      * param orderValues:
        [0] DIN The Decentralized Identification Number (DIN) of the product to buy.
        [1] quantity The quantity to buy.
        [2] totalPrice Total price of the purchase, in wei.
        [3] priceValidUntil Expiration time (Unix timestamp).
        [4] affiliateReward Affiliate reward (optional), denominated in base units of Market Token (MARK).
        [5] loyaltyReward Loyalty reward (optional), denominated in loyaltyToken.
      * param orderAddresses:
        [0] affiliate Address of the affiliate. Use null address (0x0...) for no affiliate.
        [1] loyaltyToken Address of the Loyalty Token. Use null address for no loyalty reward.
      * @param nonceHash The hash of a nonce generated by a client. The nonce can be used as a proof of purchase.
      * @param v ECDSA signature parameter v.
      * @param r ECDSA signature parameter r.
      * @param s ECDSA signature parameter s.
      * @return orderID A unique ID for the order.
      */
    function buy(
        uint256[6] orderValues,
        address[2] orderAddresses,
        bytes32 nonceHash,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        payable
        public
        returns (uint256 orderID)
    {
        // Get the resolver address from the DIN Registry.
        address resolver = registry.resolver(orderValues[0]);

        if (resolver == address(0x0)) {
            LogError("Invalid resolver");
            msg.sender.transfer(msg.value);
            return 0;
        }

        // Untrusted external call. Limit gas to prevent changes to state on reentry.
        address merchant = Resolver(resolver).merchant.gas(EXTERNAL_QUERY_GAS_LIMIT)(orderValues[0]);

        Order memory order = Order({
            DIN: orderValues[0],
            quantity: orderValues[1],
            totalPrice: orderValues[2],
            priceValidUntil: orderValues[3],
            affiliateReward: orderValues[4],
            affiliate: orderAddresses[0],
            loyaltyReward: orderValues[5],
            loyaltyToken: orderAddresses[1],
            merchant: merchant,
            owner: registry.owner(orderValues[0]), // Get the DIN owner address from the DIN registry.
            v: v,
            r: r,
            s: s
        });

        bool isValid = isValidOrder(
            order.DIN,
            order.quantity,
            order.totalPrice,
            order.priceValidUntil,
            order.affiliateReward,
            order.affiliate,
            order.loyaltyReward,
            order.loyaltyToken,
            order.merchant,
            order.owner,
            order.v,
            order.r,
            order.s
        );

        if (isValid == false) {
            // Return Ether to buyer.
            msg.sender.transfer(msg.value);
            return 0;
        }

        // Transfer a mix of Ether and loyalty tokens (if applicable) from buyer to merchant.
        payMerchant(merchant, order.totalPrice, order.loyaltyToken);

        // Transfer affiliate reward from DIN owner to affiliate.
        if (order.affiliateReward > 0) {
            marketToken.transferFromCheckout(order.owner, order.affiliate, order.affiliateReward);
        }

        // Transfer loyalty reward from DIN owner to buyer.
        if (order.loyaltyReward > 0 && order.loyaltyToken != address(0x0)) {
            LoyaltyToken(order.loyaltyToken).transferFromCheckout(order.owner, msg.sender, order.loyaltyReward);
        }

        // Create a new order and return the unique order ID.
        return orders.createOrder(
            nonceHash,
            merchant,
            order.DIN,
            order.quantity,
            order.totalPrice
        );
    }

    /**
      * @dev Transfer a mix of Ether and loyalty token from buyer to merchant.
      * @param merchant The merchant address.
      * @param totalPrice The total price of the purchase, in wei.
      * @param loyaltyToken The address of the loyalty token specified by the DIN owner.
      */
    function payMerchant(address merchant, uint256 totalPrice, address loyaltyToken) private {
        // Transfer Ether from buyer to merchant.
        merchant.transfer(msg.value);

        // Calculate the remaining balance.
        uint256 loyaltyValue = totalPrice.sub(msg.value);

        // Transfer loyalty tokens from buyer to merchant if the total price was not paid in Ether.
        if (loyaltyValue > 0) {
            LoyaltyToken(loyaltyToken).transferFromCheckout(msg.sender, merchant, loyaltyValue);
        }
    }

    /**
      * @dev Verify that an order is valid.
      * @return valid Validity of the order.
      */
    function isValidOrder(
        uint256 DIN,
        uint256 quantity,
        uint256 totalPrice,
        uint256 priceValidUntil,
        uint256 affiliateReward,
        address affiliate,
        uint256 loyaltyReward,
        address loyaltyToken,
        address merchant,
        address owner,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) 
        public 
        constant 
        returns (bool) 
    {
        if (block.timestamp > priceValidUntil) {
            LogError("Offer expired");
            return false;
        }

        if (merchant == address(0x0)) {
            LogError("Invalid merchant");
            return false;
        }

        if (affiliateReward > 0 && affiliate == msg.sender) {
            LogError("Invalid affiliate");
            return false;
        }

        if (loyaltyReward > 0 && loyaltyToken != address(0x0) && loyaltyRegistry.whitelist(loyaltyToken) == false) {
            LogError("Invalid loyalty token");
            return false;
        }

        if (msg.value > totalPrice) {
            LogError("Invalid price");
            return false;
        }

        uint256 unitPrice = totalPrice / quantity;

        // Calculate the hash of the parameters provided by the buyer.
        bytes32 hash = keccak256(
            DIN,
            unitPrice,
            priceValidUntil,
            affiliateReward, 
            loyaltyReward,
            loyaltyToken
        );

        // Verify that the DIN owner has signed the provided inputs.
        if (isValidSignature(owner, hash, v, r, s) == false) {
            LogError("Invalid signature");
            return false;
        }

        return true;
    }

    /**
      * @dev Verify that an order signature is valid.
      * @param signer address of signer.
      * @param hash Signed Keccak-256 hash.
      * @param v ECDSA signature parameter v.
      * @param r ECDSA signature parameters r.
      * @param s ECDSA signature parameters s.
      * @return valid Validity of the order signature.
      */
    function isValidSignature(
        address signer,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        constant
        returns (bool valid)
    {
        return signer == ecrecover(
            keccak256("\x19Ethereum Signed Message:\n32", hash),
            v,
            r,
            s
        );
    }

}