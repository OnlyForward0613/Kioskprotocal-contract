pragma solidity ^0.4.11;

import "./MarketToken.sol";
import "./DINRegistry.sol";
import "./Resolver.sol";

contract Checkout {
    MarketToken public marketToken;
    DINRegistry public registry;

    // The next order ID.
    uint256 public orderIndex = 0;

    // Prevents Solidity "stack too deep" error.
    struct Order {
        uint256 DIN;
        uint256 quantity;
        uint256 totalPrice;
        uint256 priceValidUntil;
        uint256 affiliateReward;
        address affiliate;
        uint256 loyaltyReward;
        address loyaltyToken;
    }

    // Logs Solidity errors
    event LogError(string error);

    // Logs new orders
    event NewOrder(
        uint256 indexed orderID,
        bytes32 nonceHash,
        address indexed buyer,
        address indexed merchant,
        uint256 DIN,
        uint256 quantity,
        uint256 totalPrice,
        uint256 timestamp
    );

    /** @dev Constructor.
      * @param _token The Market Token contract address.
      * @param _registry The DIN Registry contract address.
      */
    function Checkout(MarketToken _token, DINRegistry _registry) public {
        marketToken = _token;
        registry = _registry;
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
        Order memory order = Order({
            DIN: orderValues[0],
            quantity: orderValues[1],
            totalPrice: orderValues[2],
            priceValidUntil: orderValues[3],
            affiliateReward: orderValues[4],
            affiliate: orderAddresses[0],
            loyaltyReward: orderValues[5],
            loyaltyToken: orderAddresses[1]
        });

        if (block.timestamp > order.priceValidUntil) {
            LogError("Offer expired");
            msg.sender.transfer(msg.value);
            return 0;
        }

        uint256 unitPrice = order.totalPrice / order.quantity;

        // Calculate the hash of the parameters provided by the buyer.
        bytes32 hash = keccak256(
            order.DIN,
            unitPrice,
            order.priceValidUntil,
            order.affiliateReward, 
            order.loyaltyReward,
            order.loyaltyToken
        );

        // Get the resolver address from the DIN Registry.
        address resolverAddr = registry.resolver(order.DIN);

        if (resolverAddr == address(0x0)) {
            LogError("Invalid resolver");
            msg.sender.transfer(msg.value);
            return 0;
        }

        // Untrusted call
        address merchant = Resolver(resolverAddr).merchant(order.DIN);

        if (merchant == address(0x0)) {
            LogError("Invalid merchant");
            msg.sender.transfer(msg.value);
            return 0;
        }

        // Get the DIN owner address from the DIN registry.
        address owner = registry.owner(order.DIN);

        // Verify that the DIN owner has signed the parameters provided by the buyer.
        bool isValid = isValidSignature(owner, hash, v, r, s);

        if (isValid == false) {
            LogError("Invalid signature");
            msg.sender.transfer(msg.value);
            return 0;
        }

        if (msg.value != order.totalPrice) {
            LogError("Invalid price");
            msg.sender.transfer(msg.value);
            return 0;
        }        

        // Transfer Ether (ETH) from buyer to merchant.
        merchant.transfer(msg.value);

        if (order.affiliate == msg.sender) {
            LogError("Invalid affiliate");
            msg.sender.transfer(msg.value);
            return 0;
        }

        if (order.affiliateReward > 0) {
            // Transfer affiliate fee from DIN owner to affiliate.
            marketToken.transferFromCheckout(owner, order.affiliate, order.affiliateReward);
        }

        // Increment the order index.
        orderIndex++;

        NewOrder(
            orderIndex,     // Order ID
            nonceHash,
            msg.sender,     // Buyer
            merchant,
            order.DIN,
            order.quantity,
            order.totalPrice,
            block.timestamp
        );

        return orderIndex;
    }

    /**
      * @dev Verifies that an order signature is valid.
      * @param signer address of signer.
      * @param hash Signed Keccak-256 hash.
      * @param v ECDSA signature parameter v.
      * @param r ECDSA signature parameters r.
      * @param s ECDSA signature parameters s.
      * @return valid Validity of order signature.
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