import hre from "hardhat";
import {ethers} from "hardhat";


import {
    getChainId,
    deployContract,
    waitTx,
    deployments
} from "../common/utils"

async function main() {
    const { deployer } = await hre.getNamedAccounts();

    const chainId = await getChainId()
  
    if (hre.network.name === 'mainnet') {
        console.log('\n\n Deploying Contracts to mainnet. Hit ctrl + c to abort')
    } else if (hre.network.name === 'matic') {
        console.log('\n\n Deploying Contracts to polygon. Hit ctrl + c to abort')
    } else if (hre.network.name === 'hardhat') {
        console.log('\n\n Deploying Contracts to hardhat.')
    }

    const proxyAdmin = await ethers.getContractAt('LiteProxyAdmin', deployments[chainId].proxyAdmin)

    const liteVault = await deployContract('LiteVault')

    const liteVaultInitialiseArgs = [
        deployer,
        "0x7ceb23fd6bc0add59e62ac25578270cff1b9f619", // WETH
        ethers.BigNumber.from(10).pow(7), // 1e7,
        ethers.BigNumber.from(10).pow(5), // 1e5,
        ethers.BigNumber.from(10).pow(15), // 1e15,
        deployer,
        "1051522995784417194" // https://etherscan.io/block/15997605
    ]

    const liteVaultInitialiseCalldata = (await liteVault.populateTransaction.initialize(...liteVaultInitialiseArgs)).data || "0x"
    if (liteVaultInitialiseCalldata == "0x") throw Error("liteVaultInitialiseCalldata is 0x")
    const liteVaultProxyArgs = [
        liteVault.address,
        proxyAdmin.address,
        liteVaultInitialiseCalldata
    ]
    const liteVaultProxy = await deployContract('LiteVaultProxy', liteVaultProxyArgs)

    if (hre.network.name !== 'hardhat') {
      try {
        await hre.run('verify:verify', {
            address: liteVault.address,
            contract: "contracts/vault/Main.sol:LiteVault",
            constructorArguments: []
        })
      } catch (error) {
        console.log(error)
      }

      try {
        await hre.run('verify:verify', {
            address: liteVaultProxy.address,
            contract: "contracts/vaultProxy/Main.sol:LiteVaultProxy",
            constructorArguments: liteVaultProxyArgs
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
