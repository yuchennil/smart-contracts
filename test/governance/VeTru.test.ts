import { expect, use } from 'chai'
import { providers, Wallet } from 'ethers'
import { solidity, MockContract, deployMockContract } from 'ethereum-waffle'

import { setupDeploy } from 'scripts/utils'

import {
  beforeEachWithFixture,
  parseTRU,
  timeTravelTo,
  timeTravel,
} from 'utils'

import {
  TrustTokenFactory,
  TrustToken,
  stkTRUFactory,
  stkTRU,
  TrueRatingAgencyFactory,
  TrueRatingAgency,
  LoanTokenFactory,
  LoanToken,
  ArbitraryDistributorFactory,
  ArbitraryDistributor,
  ILoanFactoryJson
} from 'contracts'

use(solidity)

describe('stkTRU', () => {
  let owner: Wallet, timeLockRegistry: Wallet, saftHolder: Wallet, initialHolder: Wallet, secondAccount: Wallet, thirdAccount: Wallet, fourthAccount: Wallet
  let trustToken: TrustToken
  let stkTRU: stkTRU
  let loanToken: LoanToken
  let trueRatingAgency: TrueRatingAgency
  let distributor: ArbitraryDistributor
  let mockFactory: MockContract
  let provider: providers.JsonRpcProvider

  beforeEachWithFixture(async (wallets, _provider) => {
    ([owner, timeLockRegistry, saftHolder, initialHolder, secondAccount, thirdAccount, fourthAccount] = wallets)
    provider = _provider
    const deployContract = setupDeploy(owner)

    // deploy all related contracts ?
    trustToken = await deployContract(TrustTokenFactory)
    mockFactory = await deployMockContract(owner, ILoanFactoryJson.abi)
    stkTRU = await deployContract(stkTRUFactory)
    distributor = await deployContract(ArbitraryDistributorFactory)
    trueRatingAgency = await deployContract(TrueRatingAgencyFactory)
    loanToken = await deployContract(LoanTokenFactory,trustToken.address,initialHolder.address, secondAccount.address,parseTRU(1000),3600*24,1000)

    // initialize all contracts
    await trustToken.initialize()
    // await stkTRU.initialize()
    await mockFactory.mock.isLoanToken.returns(true)    
    await distributor.initialize(trueRatingAgency.address, trustToken.address, parseTRU(100))
    await trueRatingAgency.initialize(trustToken.address,distributor.address,mockFactory.address)

    // mint TRU token and add rater to the white list
    await trustToken.mint(owner.address,parseTRU(100))
    await trustToken.approve(trueRatingAgency.address,parseTRU(100))
    await stkTRU.connect(owner).whitelist(trueRatingAgency.address,true)
  })
  const vote = async() => {
    await trueRatingAgency.allow(owner.address, true)
    await trueRatingAgency.submit(loanToken.address, { gasLimit: 4_000_000 })
    await trueRatingAgency.connect(owner).yes(loanToken.address,parseTRU(100))
  }
  describe('RatingAgency', () => {
    beforeEach(async ()=> {
        await vote()
    })
    describe('Mint', () => {
        it('mint the same amout of stkTRU', async () => {
            expect(await stkTRU.balanceOf(owner.address)).to.eq(parseTRU(100))
        })
    })
    describe('Burn', () => {
        it('burn all of the stkTRU', async () => {
            await trueRatingAgency.connect(owner).withdraw(loanToken.address, parseTRU(100))
            expect(await stkTRU.balanceOf(owner.address)).to.eq(parseTRU(0))
        })
    })
    describe('non-transferrable', () => {
        beforeEach(async() => {
            await vote()
        })
        it('should revert when transfer',async () => {
            expect(await stkTRU.transfer(secondAccount.address,parseTRU(100))).to.be.reverted
        })
    })
  })



})
