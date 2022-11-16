import { HardhatRuntimeEnvironment } from "hardhat/types";
import { task, types } from "hardhat/config";

task(
  "deploy-periphery",
  "Deploy ExcessWithdrawHandler and ExcessWithdrawFulfiller"
)
  .addPositionalParam("vault", "the LiteVault's (proxy) address")
  .addOptionalParam(
    "fee",
    "the initial penalty fee percentage, defaults to 2000000 (2%)",
    2000000,
    types.int
  )
  .setAction(async (taskArgs, hre) => {
    return await deploy(hre, taskArgs.vault, taskArgs.fee);
  });

const deploy = async (
  hre: HardhatRuntimeEnvironment,
  vault: string,
  penaltyFeePercentage: number
) => {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  console.log("\n Deploying ExcessWithdrawHandler \n ---------------------");

  const withdrawHandler = await deploy("ExcessWithdrawHandler", {
    from: deployer,
    args: [vault, penaltyFeePercentage],
    log: true,
    gasLimit: 16000000,
  });

  console.log(
    "Deployed ExcessWithdrawHandler to",
    withdrawHandler.address,
    "with an initial penalty fee percentage of ",
    penaltyFeePercentage / 1e6 + "%"
  );

  const withdrawFulfiller = await deploy("ExcessWithdrawFulfiller", {
    from: deployer,
    args: [vault, withdrawHandler.address],
    log: true,
    gasLimit: 16000000,
  });

  console.log("Deployed ExcessWithdrawFulfiller to", withdrawFulfiller.address);

  console.log("\n --------------------- \n Done!\n");
};
