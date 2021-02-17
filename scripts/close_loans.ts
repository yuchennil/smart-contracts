/**
 * PRIVATE_KEY={private_key} ts-node scripts/close_loans.ts "{network}"
 */
import { ethers, providers } from 'ethers'

import {
  TrueLenderFactory,
  LoanTokenFactory
} from '../build'

async function closeRopstenLoans () {
  const txnArgs = { gasLimit: 3_500_000, gasPrice: 1_000_000_000 }
  const provider = new providers.InfuraProvider(process.argv[2], 'e33335b99d78415b82f8b9bc5fdc44c0')
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider)

  const trueLenderAddress = '0xb1f283F554995F666bD3238F229ADf0aF7d54fC4'
  const trueLender = await TrueLenderFactory.connect(trueLenderAddress, wallet)
  const loans = await trueLender.loans()
  const blockNumber = await provider.getBlockNumber()
  const time = (await provider.getBlock(blockNumber)).timestamp
  console.log(loans)

  for (let i = 0; i < loans.length; i++) {
      await checkAndCloseLoan(txnArgs, wallet, time, trueLender, loans[i])
  }
}

// 0=Awaiting, 1=Funded, 2=Withdrawn, 3=Settled, 4=Defaulted, 5=Liquidated
async function checkAndCloseLoan(txnArgs, wallet, time, trueLender, loanAddress) {
    const loan = await LoanTokenFactory.connect(loanAddress, wallet)
    const loanStatus = await loan.status()
    const start = await loan.start()
    const term = await loan.term()
    const end = start.add(term).toNumber()
    const expired: boolean = end <= time
    console.log("loan: ", loanAddress)
    if (loanStatus == 0) {
        console.log("status: 0 - Awaiting")
    }
    else if (loanStatus == 1) {
        console.log("status: 1 - Funded")
    }
    else if (loanStatus == 2) {
        console.log("status: 2 - Withdrawn")
    }
    else if (loanStatus == 3) {
        console.log("status: 3 - Settled")
    }
    else if (loanStatus == 4) {
        console.log("status: 4 - Defaulted")
    }
    else if (loanStatus == 5) {
        console.log("status: 5 - Liquidated")
    }
    // only reclaim if not defaulted
    if (expired && loanStatus < 3) {
        console.log("loan: ", loan.address, " Expired ")
        await loan.close(txnArgs)
        console.log("Loan Closed")
        if (!(loanStatus == 4)) {
            await trueLender.reclaim(loanAddress, txnArgs)
            console.log("Loan Reclaimed")
        }
        else {
            console.log("Loan Defaulted")
        }
    }
    console.log("\n")
}

closeRopstenLoans().catch(console.error)
