/**
 * Register SAFT accounts script
 *
 * ts-node scripts/register_saft_addresses.ts "network" "path to csv with addresses"
 */

import fs from 'fs'
import { utils, constants, providers, Wallet } from 'ethers'
import { TimeLockRegistry } from '../build/types/TimeLockRegistry'
import { TimeLockRegistryFactory } from '../build/types/TimeLockRegistryFactory'
import { TrustToken } from '../build/types/TrustToken'
import { TrustTokenFactory } from '../build/types/TrustTokenFactory'

export const txnArgs = { gasLimit: 100_000, gasPrice: 40_000_000_000 }

export interface SaftAccount {
  address: string,
  amount: string,
}

const toTrustToken = (amount: string) => utils.parseUnits(amount, 6)
const sum = (numbers: utils.BigNumber[]) => numbers.reduce((cumSum, value) => cumSum.add(value), constants.Zero)

export const registerSaftAccounts = async (registry: TimeLockRegistry, trustToken: TrustToken, accounts: SaftAccount[]) => {
  const totalAllowance = sum(accounts.map(({ amount }) => toTrustToken(amount)))
  const tx = await trustToken.approve(registry.address, totalAllowance, txnArgs)
  await tx.wait()
  console.log('Transfers approved')
  let { nonce } = tx
  const pendingTransactions = []
  for (const { address, amount } of accounts) {
    let decimalAmount = amount.slice(0, -2) + "." + amount.slice(-2)
    pendingTransactions.push((await registry.register(address, toTrustToken(amount), { ...txnArgs, nonce: nonce + 1 })).wait()
      .then(() => console.log(`Done: ${address} for ${decimalAmount} TRU`))
      .catch((err) => console.error(`Failed for ${address}`, err)),
    )
    nonce++
  }
  await Promise.all(pendingTransactions)
}

export const parseAccountList = (text: string): SaftAccount[] =>
  text
    .split('\n')
    .filter((line) => line.split(',').length > 1)
    .map((line) => ({
      address: line.split(',')[0].trim(),
      amount: line.split(',')[1].trim(),
    }))

const readAccountList = (filePath: string) => parseAccountList(fs.readFileSync(filePath).toString())

if (require.main === module) {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const deployedAddresses = {
    timeLockRegistry: "0x5Fe2F5F2Cc97887746C5cB44386A94061F35DcC4",
    trustToken: "0x4C19596f5aAfF459fA38B0f7eD92F11AE6543784"
  }

  const provider = new providers.InfuraProvider(process.argv[2], 'e33335b99d78415b82f8b9bc5fdc44c0')
  const wallet = new Wallet(process.env.PRIVATE_KEY, provider)
  const registry = TimeLockRegistryFactory.connect(deployedAddresses.timeLockRegistry, wallet)
  const trustToken = TrustTokenFactory.connect(deployedAddresses.trustToken, wallet)
  const accountList = readAccountList(process.argv[3])
  registerSaftAccounts(registry, trustToken, accountList).then(() => console.log('Done.'))
}
