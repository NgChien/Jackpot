const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SimToken", () => {
  let owner, alice, bob, carol;
  let SimToken;

  beforeEach(async () => {
    await ethers.provider.send("hardhat_reset", []);
    [owner, alice, bob, carol] = await ethers.getSigners();
    SimToken = await ethers.deployContract("CryptoSims", owner);
  });

  it("Deployment should assign the total supply of tokens to the owner", async () => {
    const ownerBalance = await SimToken.balanceOf(owner.address);
    expect(await SimToken.totalSupply()).to.equal(ownerBalance);
  });

  it("test transfer", async () => {
    await expect(
      SimToken.connect(owner).transfer(alice.address, 50)
    ).to.changeTokenBalances(SimToken, [owner, alice], [-50, 50]);
  });

  it("emit event", async () => {
    await expect(SimToken.connect(owner).transfer(bob.address, 50))
      .to.emit(SimToken, "Transfer")
      .withArgs(owner.address, bob.address, 50);
  });

  it("Should fail if sender doesn't have enough tokens", async () => {
    await expect(
      SimToken.connect(bob).transfer(alice.address, 50)
    ).to.revertedWith("ERC20: transfer amount exceeds balance");
  });
});
