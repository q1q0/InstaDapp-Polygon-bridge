import hre from "hardhat";
import {ethers} from "hardhat";
import { ContractTransaction } from "ethers";

const deployments: Record<string, Record<string, string>> = {
    "137": {
        proxyAdmin: "0xf406F6035D389C9a7FFF9078773C66697fd7Ffc8",
        liteVault: "0x454C319c7B698A0Fd05dfd7eC9e1823be6f7403E",
        liteVaultProxy: "0x2C956E3175F6c4Eea3B560900f1e1c6dd60765e5"
    }
}

const CONSTANTS = {
    nativeToken: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
}


const deployContract = async (contractName: string, constructorArgs: any = [], options: any = [], blockConfirmation?: number) => {
  const Contract = await ethers.getContractFactory(contractName)
  const contract = await Contract.deploy(...constructorArgs, ...options)
  await contract.deployed()
  await contract.deployTransaction.wait(blockConfirmation)
  
  console.log(`${contractName} deployed: `, contract.address)

  return contract;
}

const getChainId = async (): Promise<string> => {
    return  (hre.network.config.chainId || (await ethers.provider.getNetwork()).chainId).toString();
}

const waitTx = async (contractCall: Promise<ContractTransaction>, blockConfirmation?: number, log: boolean = false): Promise<string> =>{
    const tx = await contractCall
    await tx.wait(blockConfirmation)
    if (log) console.log("Transaction Confirmed: ", tx.hash)
    return tx.hash
}


export {
    deployContract,
    getChainId,
    waitTx,
    CONSTANTS,
    deployments,
}
