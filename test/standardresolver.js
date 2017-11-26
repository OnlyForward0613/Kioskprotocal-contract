const StandardResolver = artifacts.require("StandardResolver.sol");
const DINRegistry = artifacts.require("DINRegistry.sol");
const chai = require("chai"),
    expect = chai.expect;

contract("StandardResolver", accounts => {
    let resolver;
    let registry;
    const bob = accounts[1]; // DIN owner and merchant
    const productURL = "https://kiosk-shopify.herokuapp.com/products/";

    const DIN = 1000000001;

    before(async () => {
        resolver = await StandardResolver.deployed();
        registry = await DINRegistry.deployed();
    });

    it("should have the correct owner", async () => {
        const owner = await resolver.owner();
        expect(owner).to.equal(bob);
    });

    it("should have the correct product URL", async () => {
        const url = await resolver.productURL(DIN);
        expect(url).to.equal(productURL);
    });

    it("should have the correct merchant", async () => {
        const merchant = await resolver.merchant(DIN);
        expect(merchant).to.equal(bob);
    });

});