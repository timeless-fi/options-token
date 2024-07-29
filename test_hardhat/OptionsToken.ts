import {expect} from "chai";
import {ethers, upgrades} from "hardhat";
import {AddressZero} from "@ethersproject/constants";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("OptionsToken", function() {
  it('upgrades seamlessly', async () => {
    const OptionsToken = await ethers.getContractFactory("OptionsToken");
    const OptionsTokenV2 = await ethers.getContractFactory("OptionsTokenV2");

    const signerAddress = await (await ethers.getSigners())[0].getAddress();

    const instance = await upgrades.deployProxy(OptionsToken, ["TEST", "TEST", signerAddress]);
    const newImpl = await upgrades.prepareUpgrade(instance, OptionsTokenV2);
    await instance.initiateUpgradeCooldown(newImpl);
    await time.increase(60 * 60 * 48);
    await instance.upgradeTo(newImpl);

    const instanceV2 = OptionsTokenV2.attach(await instance.getAddress());

    const value = await (instanceV2 as any).newVar();
    expect(value.toString()).to.equal('123456');

    await instance.mint(signerAddress, 1000);
    expect(await instance.balanceOf(signerAddress)).to.equal(1000);
  });

  it('prevents upgrading before the given timelock', async () => {
    const OptionsToken = await ethers.getContractFactory("OptionsToken");
    const OptionsTokenV2 = await ethers.getContractFactory("OptionsTokenV2");

    const instance = await upgrades.deployProxy(OptionsToken, ["TEST", "TEST", AddressZero]);
    const newImpl = await upgrades.prepareUpgrade(instance, OptionsTokenV2);
    await instance.initiateUpgradeCooldown(newImpl);
    await time.increase(60 * 60 * 48 - 1);

    await expect(instance.upgradeTo(newImpl)).to.be.revertedWith('Upgrade cooldown not initiated or still ongoing');
  });

  it('requires correct contract to be set before an upgrade', async () => {
    const OptionsToken = await ethers.getContractFactory("OptionsToken");
    const OptionsTokenV2 = await ethers.getContractFactory("OptionsTokenV2");

    const instance = await upgrades.deployProxy(OptionsToken, ["TEST", "TEST", AddressZero]);
    const newImpl = await upgrades.prepareUpgrade(instance, OptionsTokenV2);
    await instance.initiateUpgradeCooldown(AddressZero);
    await time.increase(60 * 60 * 48);

    await expect(instance.upgradeTo(newImpl)).to.be.revertedWith('Incorrect implementation');
  });
});
