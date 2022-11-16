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
  ExcessWithdrawHandler__factory,
} from "../../typechain-types";

chai.use(chaiAsPromised);
chai.use(solidity);
const { expect } = chai;
const hre = require("hardhat");

const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";
const usdcAddress = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";
const usdcWhale = "0xd6216fc19db775df9774a6e33526131da7d19a2c";

describe("ExcessWithdrawHandler", () => {
  const defaultDepositAmount = toUsdcBigNumber(1000);

  const minimumThresholdPercentage = 10000000; // 10%
  const withdrawFeePercentage = 10000; // 0.01%
  const withdrawFeeAbsoluteMin = toUsdcBigNumber(20); // usdc has 6 decimals -> 20 USDC.
  const mainnetExchangePrice = toUsdcBigNumber(2);
  const penaltyFeePercentage = 2000000; // 2%

  let vault: LiteVault;
  let withdrawHandler: ExcessWithdrawHandler;
  let owner: SignerWithAddress;
  let usdc: IERC20Upgradeable;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let feeSetter: SignerWithAddress;
  let fulfiller: SignerWithAddress;
  let bridge: SignerWithAddress;

  before(async () => {
    const signers = await ethers.getSigners();
    owner = signers[0];
    user1 = signers[1];
    user2 = signers[2];
    feeSetter = signers[3];
    fulfiller = signers[4];
    bridge = signers[5];

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
  });

  describe("admin actions", async () => {
    describe("setFeeSetter", async () => {
      const subject = async (
        addressToSet: string,
        value: boolean,
        sender: SignerWithAddress
      ) => {
        return withdrawHandler
          .connect(sender)
          .setFeeSetter(addressToSet, value);
      };

      it("should setFeeSetter flag true", async () => {
        expect(await withdrawHandler.allowedFeeSetters(user1.address)).to.equal(
          false
        );

        await subject(user1.address, true, owner);

        expect(await withdrawHandler.allowedFeeSetters(user1.address)).to.equal(
          true
        );
      });

      it("should setFeeSetter flag false", async () => {
        await subject(user1.address, true, owner);

        expect(await withdrawHandler.allowedFeeSetters(user1.address)).to.equal(
          true
        );

        await subject(user1.address, false, owner);

        expect(await withdrawHandler.allowedFeeSetters(user1.address)).to.equal(
          false
        );
      });

      it("should revert if not owner", async () => {
        await expect(subject(user1.address, true, user1)).to.be.revertedWith(
          "Ownable: caller is not the owner"
        );
      });
    });

    describe("setFulfiller", async () => {
      const subject = async (
        addressToSet: string,
        value: boolean,
        sender: SignerWithAddress
      ) => {
        return withdrawHandler
          .connect(sender)
          .setFulfiller(addressToSet, value);
      };

      it("should setFulfiller flag true", async () => {
        expect(await withdrawHandler.allowedFulfillers(user1.address)).to.equal(
          false
        );

        await subject(user1.address, true, owner);

        expect(await withdrawHandler.allowedFulfillers(user1.address)).to.equal(
          true
        );
      });

      it("should setFulfiller flag false", async () => {
        await subject(user1.address, true, owner);

        expect(await withdrawHandler.allowedFulfillers(user1.address)).to.equal(
          true
        );

        await subject(user1.address, false, owner);

        expect(await withdrawHandler.allowedFulfillers(user1.address)).to.equal(
          false
        );
      });

      it("should revert if not owner", async () => {
        await expect(subject(user1.address, true, user1)).to.be.revertedWith(
          "Ownable: caller is not the owner"
        );
      });
    });
  });

  describe("fee setter actions", async () => {
    beforeEach(async () => {
      await withdrawHandler
        .connect(owner)
        .setFeeSetter(feeSetter.address, true);
    });

    describe("setPenaltyFee", async () => {
      const subject = async (value: number, sender: SignerWithAddress) => {
        return withdrawHandler.connect(sender).setPenaltyFee(value);
      };

      it("should setPenaltyFee", async () => {
        expect(await withdrawHandler.penaltyFeePercentage()).to.equal(
          penaltyFeePercentage
        );

        await subject(6000000, feeSetter); // set to 6%

        expect(await withdrawHandler.penaltyFeePercentage()).to.equal(6000000);
      });

      it("should revert if not allowed feeSetter", async () => {
        await expect(subject(6000000, user1)).to.be.revertedWith(
          "ExcessWithdrawHandler__Unauthorized"
        );
      });

      it("should revert if not valid percentage amount", async () => {
        // setting > 100% e.g. 110% should not be possible
        await expect(subject(110000000, feeSetter)).to.be.revertedWith(
          "ExcessWithdrawHandler__InvalidParams"
        );
      });
    });
  });

  context("when vault initialized & default deposit for users", async () => {
    beforeEach(async () => {
      await usdc.connect(user1).approve(vault.address, defaultDepositAmount);
      await vault.connect(user1).deposit(defaultDepositAmount, user1.address);

      await usdc.connect(user2).approve(vault.address, defaultDepositAmount);
      await vault.connect(user2).deposit(defaultDepositAmount, user2.address);

      await vault
        .connect(user1)
        .approve(withdrawHandler.address, defaultDepositAmount);
      await vault
        .connect(user2)
        .approve(withdrawHandler.address, defaultDepositAmount);
    });

    describe("fulfiller actions", async () => {
      beforeEach(async () => {
        await withdrawHandler
          .connect(owner)
          .setFulfiller(fulfiller.address, true);
      });

      describe("fromVault", async () => {
        const queueExcessWithdraw = async () => {
          return withdrawHandler
            .connect(user1)
            .queueExcessWithdraw(
              defaultDepositAmount,
              user2.address,
              penaltyFeePercentage + 1
            );
        };

        const subject = async (value: BigNumber, sender: SignerWithAddress) => {
          const sharesToBurn = await vault.balanceOf(withdrawHandler.address);
          return withdrawHandler.connect(sender).fromVault(value, sharesToBurn);
        };

        it("should fromVault", async () => {
          // first queue some amount to lock shares in withdrawHandler
          await queueExcessWithdraw();

          expect(
            (await usdc.balanceOf(withdrawHandler.address)).eq(0)
          ).to.equal(true);

          await subject(toUsdcBigNumber(980), fulfiller);

          expect(
            (await usdc.balanceOf(withdrawHandler.address)).eq(
              toUsdcBigNumber(980).sub(withdrawFeeAbsoluteMin)
            )
          ).to.equal(true);
        });

        it("should reduce totalQueuedAmount", async () => {
          // first queue some amount to lock shares in withdrawHandler
          await queueExcessWithdraw();

          expect(
            (await withdrawHandler.totalQueuedAmount()).eq(toUsdcBigNumber(980))
          ).to.equal(true);

          await subject(toUsdcBigNumber(980), fulfiller);

          expect((await withdrawHandler.totalQueuedAmount()).eq(0)).to.equal(
            true
          );
        });

        it("should emit FromVault", async () => {
          // first queue some amount to lock shares in withdrawHandler
          await queueExcessWithdraw();

          const withdrawHandlerShares = await vault.balanceOf(
            withdrawHandler.address
          );

          const result = await subject(toUsdcBigNumber(980), fulfiller);

          const events = (await result.wait())?.events as Event[];

          expect(events?.length).to.be.greaterThanOrEqual(1);
          expect(events[events.length - 1]?.event).to.equal("FromVault");
          expect(
            events[events.length - 1]?.args?.amountMoved.eq(
              toUsdcBigNumber(980)
            )
          ).to.equal(true);
          expect(
            events[events.length - 1]?.args?.sharesBurned.eq(
              withdrawHandlerShares
            )
          ).to.equal(true);
        });

        it("should revert if not allowed fulfiller", async () => {
          await expect(
            subject(toUsdcBigNumber(1000), user1)
          ).to.be.revertedWith("ExcessWithdrawHandler__Unauthorized");
        });
      });
    });

    describe("queueExcessWithdraw", async () => {
      const subject = async () => {
        return withdrawHandler
          .connect(user1)
          .queueExcessWithdraw(
            defaultDepositAmount,
            user2.address,
            penaltyFeePercentage + 1
          );
      };

      it("should queueExcessWithdraw", async () => {
        const initialQueuedAmount = await withdrawHandler.totalQueuedAmount();
        await subject();
        expect(
          initialQueuedAmount.lt(await withdrawHandler.totalQueuedAmount())
        ).to.equal(true);
        expect(
          (await vault.balanceOf(withdrawHandler.address)).eq(
            defaultDepositAmount
          )
        ).to.eq(true);
      });

      it("should increase totalQueuedAmount correctly", async () => {
        const initialQueuedAmount = await withdrawHandler.totalQueuedAmount();
        await subject();

        // expected = default deposit amount (withdraw amount) minus the penalty fee
        const expectedQueuedAmount = defaultDepositAmount.sub(
          defaultDepositAmount.mul(penaltyFeePercentage).div(1e8)
        );

        expect(
          (await withdrawHandler.totalQueuedAmount())
            .sub(initialQueuedAmount)
            .eq(expectedQueuedAmount)
        ).to.equal(true);
      });

      it("should queue requested amount for receiver", async () => {
        const initialUserWithdrawAmount =
          await withdrawHandler.queuedWithdrawAmounts(user2.address);

        expect(initialUserWithdrawAmount).to.equal(0);

        await subject();

        // expected = default deposit amount (withdraw amount) minus the penalty fee
        const expectedQueuedAmount = defaultDepositAmount.sub(
          defaultDepositAmount.mul(penaltyFeePercentage).div(1e8)
        );
        expect(
          (await withdrawHandler.queuedWithdrawAmounts(user2.address)).eq(
            expectedQueuedAmount
          )
        ).to.equal(true);
      });

      it("should emit ExcessWithdrawRequested", async () => {
        const result = await subject();
        const events = (await result.wait())?.events as Event[];
        expect(events?.length).to.be.greaterThanOrEqual(1);
        expect(events[events.length - 1]?.event).to.equal(
          "ExcessWithdrawRequested"
        );
        expect(events[events.length - 1]?.args?.owner).to.equal(user1.address);
        expect(events[events.length - 1]?.args?.receiver).to.equal(
          user2.address
        );
        expect(
          events[events.length - 1]?.args?.assets.eq(defaultDepositAmount)
        ).to.equal(true);
      });

      it("should instantly execute withdraw if funds in contract cover requested amount", async () => {
        // fill up withdrawHandler with funds
        await usdc
          .connect(await ethers.getSigner(usdcWhale))
          .transfer(withdrawHandler.address, toUsdcBigNumber(5000), {
            gasLimit: 500000,
          });

        const receiverInitialBalance = await usdc.balanceOf(user2.address);
        const initialQueuedAmount = await withdrawHandler.totalQueuedAmount();

        await subject();

        expect(
          initialQueuedAmount.lt(await withdrawHandler.totalQueuedAmount())
        ).to.equal(true);
        expect(
          (await vault.balanceOf(withdrawHandler.address)).eq(
            defaultDepositAmount
          )
        ).to.eq(true);

        const receiverAfterBalance = await usdc.balanceOf(user2.address);
        expect(
          receiverAfterBalance
            .sub(receiverInitialBalance)
            .eq(toUsdcBigNumber(980)) // defaultDepositAmount - penaltyFee
        ).to.equal(true);
      });

      it("should emit ExcessWithdrawExecuted if instantly execute withdraw", async () => {
        // fill up withdrawHandler with funds
        await usdc
          .connect(await ethers.getSigner(usdcWhale))
          .transfer(withdrawHandler.address, toUsdcBigNumber(5000), {
            gasLimit: 500000,
          });

        const result = await subject();

        const events = (await result.wait())?.events as Event[];
        expect(events?.length).to.be.greaterThanOrEqual(1);
        expect(events[events.length - 1]?.event).to.equal(
          "ExcessWithdrawExecuted"
        );
        expect(events[events.length - 1]?.args?.receiver).to.equal(
          user2.address
        );
        expect(
          events[events.length - 1]?.args?.assets.eq(toUsdcBigNumber(980)) // defaultDepositAmount - penaltyFee
        ).to.equal(true);
      });

      it("should revert if assets = 0", async () => {
        await expect(
          withdrawHandler
            .connect(user1)
            .queueExcessWithdraw(0, user1.address, penaltyFeePercentage + 1)
        ).to.be.revertedWith("ExcessWithdrawHandler__InvalidParams");
      });

      it("should revert if receiver = 0x000...", async () => {
        await expect(
          withdrawHandler
            .connect(user1)
            .queueExcessWithdraw(
              defaultDepositAmount,
              ADDRESS_ZERO,
              penaltyFeePercentage + 1
            )
        ).to.be.revertedWith("ExcessWithdrawHandler__InvalidParams");
      });

      it("should revert if maxPenaltyFee is too small", async () => {
        await expect(
          withdrawHandler
            .connect(user1)
            .queueExcessWithdraw(
              defaultDepositAmount,
              user1.address,
              penaltyFeePercentage - 1
            )
        ).to.be.revertedWith("ExcessWithdrawHandler__InvalidParams");
      });
    });

    describe("queueExcessRedeem", async () => {
      const subject = async () => {
        const shares = await vault.balanceOf(user1.address);
        return withdrawHandler
          .connect(user1)
          .queueExcessRedeem(shares, user2.address, penaltyFeePercentage + 1);
      };

      it("should queueExcessRedeem", async () => {
        const initialQueuedAmount = await withdrawHandler.totalQueuedAmount();
        await subject();
        expect(
          initialQueuedAmount.lt(await withdrawHandler.totalQueuedAmount())
        ).to.equal(true);
        expect(
          (await vault.balanceOf(withdrawHandler.address)).eq(
            defaultDepositAmount
          )
        ).to.eq(true);
      });

      it("should increase totalQueuedAmount correctly", async () => {
        const initialQueuedAmount = await withdrawHandler.totalQueuedAmount();
        await subject();

        // expected = default deposit amount (withdraw amount) minus the penalty fee
        const expectedQueuedAmount = defaultDepositAmount.sub(
          defaultDepositAmount.mul(penaltyFeePercentage).div(1e8)
        );

        expect(
          (await withdrawHandler.totalQueuedAmount())
            .sub(initialQueuedAmount)
            .eq(expectedQueuedAmount)
        ).to.equal(true);
      });

      it("should queue requested amount for receiver", async () => {
        const initialUserWithdrawAmount =
          await withdrawHandler.queuedWithdrawAmounts(user2.address);

        expect(initialUserWithdrawAmount).to.equal(0);

        await subject();

        // expected = default deposit amount (withdraw amount) minus the penalty fee
        const expectedQueuedAmount = defaultDepositAmount.sub(
          defaultDepositAmount.mul(penaltyFeePercentage).div(1e8)
        );
        expect(
          (await withdrawHandler.queuedWithdrawAmounts(user2.address)).eq(
            expectedQueuedAmount
          )
        ).to.equal(true);
      });

      it("should emit ExcessWithdrawRequested", async () => {
        const result = await subject();
        const events = (await result.wait())?.events as Event[];
        expect(events?.length).to.be.greaterThanOrEqual(1);
        expect(events[events.length - 1]?.event).to.equal(
          "ExcessWithdrawRequested"
        );
        expect(events[events.length - 1]?.args?.owner).to.equal(user1.address);
        expect(events[events.length - 1]?.args?.receiver).to.equal(
          user2.address
        );
        expect(
          events[events.length - 1]?.args?.assets.eq(defaultDepositAmount)
        ).to.equal(true);
      });

      it("should instantly execute redeem if funds in contract cover requested amount", async () => {
        // fill up withdrawHandler with funds
        await usdc
          .connect(await ethers.getSigner(usdcWhale))
          .transfer(withdrawHandler.address, toUsdcBigNumber(5000), {
            gasLimit: 500000,
          });

        const receiverInitialBalance = await usdc.balanceOf(user2.address);
        const initialQueuedAmount = await withdrawHandler.totalQueuedAmount();

        await subject();

        expect(
          initialQueuedAmount.lt(await withdrawHandler.totalQueuedAmount())
        ).to.equal(true);
        expect(
          (await vault.balanceOf(withdrawHandler.address)).eq(
            defaultDepositAmount
          )
        ).to.eq(true);

        const receiverAfterBalance = await usdc.balanceOf(user2.address);
        expect(
          receiverAfterBalance
            .sub(receiverInitialBalance)
            .eq(toUsdcBigNumber(980)) // defaultDepositAmount - penaltyFee
        ).to.equal(true);
      });

      it("should emit ExcessWithdrawExecuted if instantly execute withdraw", async () => {
        // fill up withdrawHandler with funds
        await usdc
          .connect(await ethers.getSigner(usdcWhale))
          .transfer(withdrawHandler.address, toUsdcBigNumber(5000), {
            gasLimit: 500000,
          });

        const result = await subject();

        const events = (await result.wait())?.events as Event[];
        expect(events?.length).to.be.greaterThanOrEqual(1);
        expect(events[events.length - 1]?.event).to.equal(
          "ExcessWithdrawExecuted"
        );
        expect(events[events.length - 1]?.args?.receiver).to.equal(
          user2.address
        );
        expect(
          events[events.length - 1]?.args?.assets.eq(toUsdcBigNumber(980)) // defaultDepositAmount - penaltyFee
        ).to.equal(true);
      });

      it("should revert if shares = 0", async () => {
        await expect(
          withdrawHandler
            .connect(user1)
            .queueExcessRedeem(0, user1.address, penaltyFeePercentage + 1)
        ).to.be.revertedWith("ExcessWithdrawHandler__InvalidParams");
      });

      it("should revert if receiver = 0x000...", async () => {
        await expect(
          withdrawHandler
            .connect(user1)
            .queueExcessRedeem(
              defaultDepositAmount,
              ADDRESS_ZERO,
              penaltyFeePercentage + 1
            )
        ).to.be.revertedWith("ExcessWithdrawHandler__InvalidParams");
      });

      it("should revert if maxPenaltyFee is too small", async () => {
        await expect(
          withdrawHandler
            .connect(user1)
            .queueExcessRedeem(
              defaultDepositAmount,
              user1.address,
              penaltyFeePercentage - 1
            )
        ).to.be.revertedWith("ExcessWithdrawHandler__InvalidParams");
      });
    });

    describe("executeExcessWithdraw", async () => {
      const queueExcessWithdraw = async () => {
        await withdrawHandler
          .connect(user1)
          .queueExcessWithdraw(
            defaultDepositAmount,
            user2.address,
            penaltyFeePercentage + 1
          );

        // fill up withdrawHandler with funds
        await usdc
          .connect(await ethers.getSigner(usdcWhale))
          .transfer(withdrawHandler.address, toUsdcBigNumber(5000), {
            gasLimit: 500000,
          });
      };
      const subject = async () => {
        return withdrawHandler
          .connect(user1)
          .executeExcessWithdraw(user2.address);
      };

      it("should not do anything if user has no queued withdraw amounts", async () => {
        expect(
          await withdrawHandler.queuedWithdrawAmounts(user2.address)
        ).to.equal(0);

        const result = await subject();
        const events = (await result.wait())?.events as Event[];
        expect(events.length).to.equal(0);
      });

      it("should executeExcessWithdraw", async () => {
        const initialUserBalance = await usdc.balanceOf(user2.address);

        await queueExcessWithdraw();

        expect(
          (await withdrawHandler.queuedWithdrawAmounts(user2.address)).eq(
            toUsdcBigNumber(980) // default deposit amount - 2% penalty fee
          )
        ).to.equal(true);

        await subject();

        expect(
          await withdrawHandler.queuedWithdrawAmounts(user2.address)
        ).to.equal(0);

        expect(
          (await usdc.balanceOf(user2.address))
            .sub(initialUserBalance)
            .eq(toUsdcBigNumber(980)) // default deposit amount - 2% penalty fee
        ).to.equal(true);
      });

      it("should emit ExcessWithdrawExecuted", async () => {
        await queueExcessWithdraw();
        const result = await subject();
        const events = (await result.wait())?.events as Event[];
        expect(events?.length).to.be.greaterThanOrEqual(1);
        expect(events[events.length - 1]?.event).to.equal(
          "ExcessWithdrawExecuted"
        );
        expect(events[events.length - 1]?.args?.receiver).to.equal(
          user2.address
        );
        expect(
          events[events.length - 1]?.args?.assets.eq(toUsdcBigNumber(980))
        ).to.equal(true);
      });
    });
  });

  function toUsdcBigNumber(amount: number) {
    return BigNumber.from(amount * 1e6);
  }
});
