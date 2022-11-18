import hre from "hardhat";
import {ethers} from "hardhat";


import {
    getChainId,
    deployContract,
    waitTx,
} from "../common/utils"

async function main() {
    const { deployer } = await hre.getNamedAccounts();
  
    if (hre.network.name === 'mainnet') {
        console.log('\n\n Deploying Contracts to mainnet. Hit ctrl + c to abort')
    } else if (hre.network.name === 'matic') {
        console.log('\n\n Deploying Contracts to polygon. Hit ctrl + c to abort')
    } else if (hre.network.name === 'hardhat') {
        console.log('\n\n Deploying Contracts to hardhat.')
    }

    const proxyAdmin = await deployContract('LiteProxyAdmin', [deployer])

    if (hre.network.name !== 'hardhat') {
      try {
        await hre.run('verify:verify', {
            address: proxyAdmin.address,
            contract: "contracts/proxyAdmin.sol:LiteProxyAdmin",
            constructorArguments: [deployer]
        })
      } catch (error) {
        console.log(error)
      }
    } else {
        console.log("Contracts deployed.")
    }
}


// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
