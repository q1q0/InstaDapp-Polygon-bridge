import { HardhatRuntimeEnvironment } from "hardhat/types";
import { task } from "hardhat/config";
import { toUtf8Bytes } from "@ethersproject/strings";

task("deploy-vault", "Deploy LiteVault and LiteVaultProxy")
  .addPositionalParam("proxyadmin")
  .setAction(async (taskArgs, hre) => {
    return await deploy(hre, taskArgs.proxyadmin);
  });

const deploy = async (hre: HardhatRuntimeEnvironment, proxyAdmin: string) => {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  console.log("\n Deploying LiteVault \n ---------------------");

  const vault = await deploy("LiteVault", {
    from: deployer,
    args: [],
    log: true,
    gasLimit: 16000000,
  });

  console.log("Deployed LiteVault to", vault.address);

  const vaultProxy = await deploy("LiteVaultProxy", {
    from: deployer,
    args: [vault.address, proxyAdmin, toUtf8Bytes("")],
    log: true,
    gasLimit: 16000000,
  });

  console.log(
    "Deployed LiteVaultProxy to",
    vaultProxy.address,
    "for proxyAdmin",
    proxyAdmin
  );
  console.log("\n --------------------- \n Done!\n");
};
