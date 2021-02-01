/**
 * PRIVATE_KEY={private_key} ts-node scripts/deploy_avalanche.ts "{network}"
 */
import { ethers, providers } from 'ethers'
import { waitForTx } from './utils/waitForTx'
import { 
    OwnedUpgradeabilityProxy, 
    AvalancheTrueUsd, 
    AvalancheTokenController,
    OwnedUpgradeabilityProxyFactory, 
    AvalancheTrueUsdFactory, 
    AvalancheTokenControllerFactory
} from '../build'

async function deployAvalanche () {
  const txnArgs = { gasLimit: 5_500_000, gasPrice: 470_000_000_000 }
  const smallArgs = { gasLimit: 1_500_000, gasPrice: txnArgs.gasPrice }
  let provider = new ethers.providers.JsonRpcProvider('https://api.avax.network/ext/bc/C/rpc');
  // const provider = new providers.InfuraProvider(process.argv[2], 'e33335b99d78415b82f8b9bc5fdc44c0')
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider)

  const tusdImpl = await (await new AvalancheTrueUsdFactory(wallet).deploy(txnArgs)).deployed()
  console.log(`tusdImpl: ${tusdImpl.address}`)
  const tusdProxy = await (await new OwnedUpgradeabilityProxyFactory(wallet).deploy(txnArgs)).deployed()
  console.log(`tusdProxy: ${tusdProxy.address}`)
  await waitForTx(tusdProxy.upgradeTo(tusdImpl.address, smallArgs))
  const tusd = await AvalancheTrueUsdFactory.connect(tusdProxy.address, wallet)

  const controllerImpl = await (await new AvalancheTokenControllerFactory(wallet).deploy(txnArgs)).deployed()
  console.log(`controllerImpl: ${controllerImpl.address}`)
  const controllerProxy = await (await new OwnedUpgradeabilityProxyFactory(wallet).deploy(txnArgs)).deployed()
  console.log(`controllerProxy: ${controllerProxy.address}`)
  await waitForTx(controllerProxy.upgradeTo(controllerImpl.address, smallArgs))
  const controller = await AvalancheTokenControllerFactory.connect(controllerProxy.address, wallet)

  // init tusd
  await waitForTx(tusd.initialize(smallArgs))
  await waitForTx(tusd.setBurnBounds('1000000000000000000000', '20000000000000000000000000', smallArgs))
  await waitForTx(tusd.transferOwnership(controller.address, smallArgs))
  console.log('init tusd')

  await waitForTx(controller.initialize(smallArgs))
  await waitForTx(controller.issueClaimOwnership(tusd.address, smallArgs))
  await waitForTx(controller.setToken(tusd.address, smallArgs))
  await waitForTx(controller.setMintThresholds('500000000000000000000000', '5000000000000000000000000', '20000000000000000000000000', smallArgs))
  await waitForTx(controller.setMintLimits('500000000000000000000000', '5000000000000000000000000', '20000000000000000000000000', smallArgs))
  await waitForTx(controller.refillMultiSigMintPool(smallArgs))
  await waitForTx(controller.refillRatifiedMintPool(smallArgs))
  await waitForTx(controller.refillInstantMintPool(smallArgs))
  await waitForTx(controller.setRegistryAdmin('0x59631fbe77f66b75438379e99333C04a85efE823', smallArgs))
  await waitForTx(controller.transferMintKey('0x0005e574c2edbe9404f8e904a705da7a7664d093', smallArgs))
  console.log('init controller')
}

deployAvalanche().catch(console.error)
