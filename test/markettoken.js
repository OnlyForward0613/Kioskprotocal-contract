// Set owner

const MarketToken = artifacts.require("MarketToken.sol");
const Buy = artifacts.require("Buy.sol");
const Promise = require("bluebird");
const chai = require("chai"),
    expect = chai.expect,
    should = chai.should();

contract("MarketToken", accounts => {
    let token;
    let buy;
    const initialSupply = 50000000 * Math.pow(10, 18); // 50 million tokens.
    const alice = accounts[0];
    const bob = accounts[1];

    before(async () => {
        token = await MarketToken.deployed();
        buy = await Buy.deployed();
    });

    it("should have the correct total supply", async () => {
        const totalSupply = await token.totalSupply();
        expect(totalSupply.toNumber()).to.equal(initialSupply);
    });

    it("should let a user transfer tokens", async () => {
        const aliceBalance = await token.balanceOf(alice);
        expect(aliceBalance.toNumber()).to.equal(initialSupply);

        const bobBalance = await token.balanceOf(bob);
        expect(bobBalance.toNumber()).to.equal(0);

        const amount = 20000 * Math.pow(10, 18); // Transfer 20,000 tokens
        await token.transfer(bob, amount, { from: alice });

        const newBalance = await token.balanceOf(bob);
        expect(newBalance.toNumber()).to.equal(amount);
    });

    it("should throw if an account calls transferFromBuy", async () => {
        try {
            await token.transferFromBuy(alice, bob, 50000, { from: alice });
        } catch (error) {
            assert.include(
                error.message,
                "invalid opcode",
                "Trying to call transferFromBuy should throw an error."
            );
        }
    });

    it("should throw if an unauthorized account tries to set the buy contract address", async () => {
        const owner = await token.owner();
        expect(owner).to.equal(alice);

        const newBuy = "0x1111111111111111111111111111111111111111";

        try {
            await token.setBuy(newBuy, { from: bob });
        } catch (error) {
            assert.include(
                error.message,
                "invalid opcode",
                "Trying to set the buy contract from an unauthorized account should throw an error."
            );
        }
    });

    it("should let the owner set the buy contract address", async () => {
        const buyAddr = await token.buy();
        expect(buyAddr).to.equal(buy.address);

        const newBuy = "0x1111111111111111111111111111111111111111";
        await token.setBuy(newBuy, { from: alice });

        const newBuyAddr = await token.buy();
        expect(newBuyAddr).to.equal(newBuy);
    });

    it("should throw if an unauthorized account tries to set the owner", async () => {
        const newOwner = "0x1111111111111111111111111111111111111111";

        try {
            await token.setOwner(newOwner, { from: bob });
        } catch (error) {
            assert.include(
                error.message,
                "invalid opcode",
                "Trying to set the owner from an unauthorized account should throw an error."
            );
        }
    });

    it("should let the owner set a new owner", async () => {
        const newOwner = "0x1111111111111111111111111111111111111111";
        await token.setOwner(newOwner, { from: alice });
        const owner = await token.owner();
        expect(owner).to.equal(newOwner);
    });
});