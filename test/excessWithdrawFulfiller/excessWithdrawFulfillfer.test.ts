import { ethers } from "hardhat";
import chai from "chai";
import chaiAsPromised from "chai-as-promised";
import { solidity } from "ethereum-waffle";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Event } from "ethers";

import {
  LiteVault__factory,
  LiteVault,
  IERC20Upgradeable,
  IERC20Upgradeable__factory,
  ExcessWithdrawHandler,
  ExcessWithdrawFulfiller,
  ExcessWithdrawHandler__factory,
  ExcessWithdrawFulfiller__factory,
} from "../../typechain-types";

chai.use(chaiAsPromised);
chai.use(solidity);
const { expect } = chai;
const hre = require("hardhat");

const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";
const usdcAddress = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdcWhale = "0xd6216fc19db775df9774a6e33526131da7d19a2c";

describe("ExcessWithdrawFulfiller", () => {
  const defaultDepositAmount = toUsdcBigNumber(5000);

  const minimumThresholdPercentage = 10000000; // 10%
  const withdrawFeePercentage = 10000; // 0.01%
  const withdrawFeeAbsoluteMin = toUsdcBigNumber(20); // usdc has 6 decimals -> 20 USDC.
  const mainnetExchangePrice = toUsdcBigNumber(2);
  const penaltyFeePercentage = 2000000; // 2%

  let vault: LiteVault;
  let withdrawHandler: ExcessWithdrawHandler;
  let withdrawFulfiller: ExcessWithdrawFulfiller;
  let owner: SignerWithAddress;
  let usdc: IERC20Upgradeable;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let bridge: SignerWithAddress;
  let authorizedFulfiller: SignerWithAddress;

  before(async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    user1 = signers[1];
    user2 = signers[2];
    authorizedFulfiller = signers[3];
    bridge = signers[4];

    usdc = IERC20Upgradeable__factory.connect(usdcAddress, owner);

    // send some usdc to users
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [usdcWhale],
    });
    await usdc
      .connect(await ethers.getSigner(usdcWhale))
      .transfer(user1.address, toUsdcBigNumber(500000), {
        gasLimit: 500000,
      });
    expect(
      (await usdc.balanceOf(user1.address)).gte(toUsdcBigNumber(500000))
    ).to.equal(true);

    await usdc
      .connect(await ethers.getSigner(usdcWhale))
      .transfer(user2.address, toUsdcBigNumber(500000), {
        gasLimit: 500000,
      });
    expect(
      (await usdc.balanceOf(user2.address)).gte(toUsdcBigNumber(500000))
    ).to.equal(true);
  });

  beforeEach(async () => {
    // deploy vault
    const vaultFactory = (await ethers.getContractFactory(
      "LiteVault",
      owner
    )) as LiteVault__factory;
    vault = await vaultFactory.deploy();
    await vault.deployed();

    expect(await vault.owner()).to.eq(ADDRESS_ZERO);
    expect(await vault.asset()).to.eq(ADDRESS_ZERO);

    // deploy excessWithdrawHandler
    const withdrawHandlerFactory = (await ethers.getContractFactory(
      "ExcessWithdrawHandler",
      owner
    )) as ExcessWithdrawHandler__factory;
    withdrawHandler = await withdrawHandlerFactory.deploy(
      vault.address,
      penaltyFeePercentage
    );
    await withdrawHandler.deployed();

    expect(await withdrawHandler.owner()).to.eq(owner.address);
    expect(await withdrawHandler.vault()).to.eq(vault.address);
    expect(await withdrawHandler.penaltyFeePercentage()).to.eq(
      penaltyFeePercentage
    );

    // initialize vault
    await vault.initialize(
      owner.address,
      usdc.address,
      minimumThresholdPercentage,
      withdrawFeePercentage,
      withdrawFeeAbsoluteMin,
      bridge.address,
      mainnetExchangePrice
    );

    // deploy excessWithdrawFulfiller
    const withdrawFulfillerFactory = (await ethers.getContractFactory(
      "ExcessWithdrawFulfiller",
      owner
    )) as ExcessWithdrawFulfiller__factory;
    withdrawFulfiller = await withdrawFulfillerFactory.deploy(
      vault.address,
      withdrawHandler.address
    );
    await withdrawFulfiller.deployed();

    expect(await withdrawFulfiller.withdrawHandler()).to.eq(
      withdrawHandler.address
    );
    expect(await withdrawFulfiller.vault()).to.eq(vault.address);
  });

  context(
    "when initialized, users deposited, authorizedFulfiller allowed, toMainnet executed",
    async () => {
      beforeEach(async () => {
        // deposit assets from users
        await usdc.connect(user1).approve(vault.address, defaultDepositAmount);
        await vault.connect(user1).deposit(defaultDepositAmount, user1.address);

        await usdc.connect(user2).approve(vault.address, defaultDepositAmount);
        await vault.connect(user2).deposit(defaultDepositAmount, user2.address);

        // authorized rebalancer / fulfiller
        await vault
          .connect(owner)
          .setRebalancer(authorizedFulfiller.address, true);

        await withdrawHandler
          .connect(owner)
          .setFulfiller(authorizedFulfiller.address, true);

        // ExcessWithdrawFulfiller must be authorized rebalancer / fulfiller too
        await vault
          .connect(owner)
          .setRebalancer(withdrawFulfiller.address, true);

        await withdrawHandler
          .connect(owner)
          .setFulfiller(withdrawFulfiller.address, true);

        // use toMainnet before so that investedAssets in vault is increased and bridge has funds
        await vault
          .connect(authorizedFulfiller)
          .toMainnet(toUsdcBigNumber(7000));
      });

      describe("fulfillExcessWithdraw", async () => {
        const subject = async (
          assets: BigNumber,
          sender: SignerWithAddress
        ) => {
          // approve assets from bridge to vault
          await usdc.connect(bridge).approve(vault.address, assets);

          // queue excessWithdrawRequest
          await vault.connect(user1).approve(withdrawHandler.address, assets);

          await withdrawHandler
            .connect(user1)
            .queueExcessWithdraw(
              assets,
              user1.address,
              penaltyFeePercentage + 1
            );

          // get shares to burn
          const withdrawHandlerShares = await vault.balanceOf(
            withdrawHandler.address
          );
          expect(withdrawHandlerShares.gt(0)).to.equal(true);

          // get actual queued amount after penalty fee as the bot would use
          const queuedAmount = await withdrawHandler.totalQueuedAmount();

          return withdrawFulfiller
            .connect(sender)
            .fulfillExcessWithdraw(queuedAmount, withdrawHandlerShares);
        };

        it("should fulfillExcessWithdraw", async () => {
          expect(await usdc.balanceOf(withdrawHandler.address)).to.equal(0);

          await subject(toUsdcBigNumber(3000), authorizedFulfiller);

          // check that withdrawHandler has received assets as expected
          // 3000 -2% penalty fee minus minimum withdrawal Fee
          // = 2940 -20 = 2920
          const expectedAmount = toUsdcBigNumber(2920);
          expect(
            (await usdc.balanceOf(withdrawHandler.address)).eq(expectedAmount)
          ).to.equal(true);
        });

        it("should emit ExcessWithdrawFulfilled", async () => {
          const result = await subject(
            toUsdcBigNumber(3000),
            authorizedFulfiller
          );
          const events = (await result.wait())?.events as Event[];

          expect(events?.length).to.be.greaterThanOrEqual(1);
          expect(events[events.length - 1].event).to.equal(
            "ExcessWithdrawFulfilled"
          );

          expect(
            events[events.length - 1]?.args?.amountMoved.eq(
              toUsdcBigNumber(2940)
            )
            // amountMoved: 3000 -2% penalty fee minus minimum withdrawal Fee = 2940
          ).to.equal(true);

          expect(
            events[events.length - 1]?.args?.sharesBurned.eq(
              toUsdcBigNumber(3000)
            )
          ).to.equal(true);
        });

        it("should revert if not rebalancer", async () => {
          await withdrawHandler
            .connect(owner)
            .setFulfiller(user1.address, true);

          await expect(
            subject(toUsdcBigNumber(3000), user1)
          ).to.be.revertedWith("ExcessWithdrawFulfiller__Unauthorized");
        });

        it("should revert if not fulfiller", async () => {
          await vault.connect(owner).setRebalancer(user1.address, true);

          await expect(
            subject(toUsdcBigNumber(3000), user1)
          ).to.be.revertedWith("ExcessWithdrawFulfiller__Unauthorized");
        });
      });
    }
  );

  function toUsdcBigNumber(amount: number) {
    return BigNumber.from(amount * 1e6);
  }
});
