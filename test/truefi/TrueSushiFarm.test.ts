import { expect, use } from 'chai'
import { MaxUint256 } from '@ethersproject/constants'
import { Wallet, BigNumber, BigNumberish } from 'ethers'
import { MockProvider, solidity } from 'ethereum-waffle'

import {
  beforeEachWithFixture,
  timeTravel,
  timeTravelTo,
  expectCloseTo,
  expectScaledCloseTo,
  parseEth,
} from 'utils'

import {
  MockErc20Token,
  MockErc20TokenFactory,
  LinearTrueDistributor,
  TrueSushiFarmFactory,
  TrueSushiFarm,
  LinearTrueDistributorFactory,
  MasterChef,
  MasterChefFactory,
} from 'contracts'

use(solidity)

describe('TrueSushiFarm', () => {
  const DAY = 24 * 3600
  let start: number
  
  let provider: MockProvider
  let owner: Wallet
  let staker1: Wallet
  let staker2: Wallet

  let distributor: LinearTrueDistributor
  let trustToken: MockErc20Token
  let stakingToken: MockErc20Token
  let sushi: MockErc20Token
  let masterChef: MasterChef
  let farm: TrueSushiFarm
  let farm2: TrueSushiFarm

  const REWARD_DAYS = 10
  const DURATION = REWARD_DAYS * DAY
  const amount = BigNumber.from(1e11) // 1000 TRU = 100/day
  const txArgs = { gasLimit: 6_000_000 }
  const sushiPoolId = 0
  const totalSushiRewardPerBlock = parseEth(100)

  const fromTru = (amount: BigNumberish) => BigNumber.from(amount).mul(BigNumber.from(1e8))

  beforeEachWithFixture(async (wallets, _provider) => {
    [owner, staker1, staker2] = wallets
    provider = _provider
    trustToken = await new MockErc20TokenFactory(owner).deploy()
    stakingToken = await new MockErc20TokenFactory(owner).deploy()
    sushi = await new MockErc20TokenFactory(owner).deploy()
    distributor = await new LinearTrueDistributorFactory(owner).deploy()
    masterChef = await new MasterChefFactory(owner).deploy(sushi.address, owner.address, totalSushiRewardPerBlock, 0, 0)
    await masterChef.add(100, stakingToken.address, true)
    const now = Math.floor(Date.now() / 1000)
    start = now + DAY

    await distributor.initialize(start, DURATION, amount, trustToken.address)

    farm = await new TrueSushiFarmFactory(owner).deploy()
    farm2 = await new TrueSushiFarmFactory(owner).deploy()

    await distributor.setFarm(farm.address)
    await farm.initialize(stakingToken.address, distributor.address, masterChef.address, sushiPoolId, 'Sushi Farm')

    await trustToken.mint(distributor.address, amount)
    // await distributor.transfer(owner.address, farm.address, amount)
    await stakingToken.mint(staker1.address, parseEth(1000))
    await stakingToken.mint(staker2.address, parseEth(1000))
    await stakingToken.connect(staker1).approve(farm.address, MaxUint256)
    await stakingToken.connect(staker2).approve(farm.address, MaxUint256)
  })

  describe('initializer', () => {
    it('name is correct', async () => {
      expect(await farm.name()).to.equal('Sushi Farm')
    })

    it('owner can withdraw funds', async () => {
      await distributor.empty()
      expect(await trustToken.balanceOf(owner.address)).to.equal(amount)
    })

    it('owner can change farm with event', async () => {
      await expect(distributor.setFarm(farm2.address)).to.emit(distributor, 'FarmChanged')
        .withArgs(farm2.address)
    })

    it('cannot init farm unless distributor is set to farm', async () => {
      await expect(farm2.initialize(stakingToken.address, distributor.address, masterChef.address, sushiPoolId, 'Test farm'))
        .to.be.revertedWith('TrueSushiFarm: Distributor farm is not set')
    })
  })

  describe('one staker', () => {
    beforeEach(async () => {
      await timeTravelTo(provider, start)
    })

    it('correct events emitted', async () => {
      await expect(farm.connect(staker1).stake(parseEth(500), txArgs)).to.emit(farm, 'Stake')
        .withArgs(staker1.address, parseEth(500))
      await timeTravel(provider, DAY)
      await expect(farm.connect(staker1).claim(txArgs)).to.emit(farm, 'Claim')
      await expect(farm.connect(staker1).unstake(parseEth(500), txArgs)).to.emit(farm, 'Unstake')
        .withArgs(staker1.address, parseEth(500))
    })

    it('staking changes stake balance', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      expect(await farm.staked(staker1.address)).to.equal(parseEth(500))
      expect(await farm.totalStaked()).to.equal(parseEth(500))

      await farm.connect(staker1).stake(parseEth(500), txArgs)
      expect(await farm.staked(staker1.address)).to.equal(parseEth(1000))
      expect(await farm.totalStaked()).to.equal(parseEth(1000))
    })

    it('unstaking changes stake balance', async () => {
      await farm.connect(staker1).stake(parseEth(1000), txArgs)
      await farm.connect(staker1).unstake(parseEth(500), txArgs)
      expect(await farm.staked(staker1.address)).to.equal(parseEth(500))
      expect(await farm.totalStaked()).to.equal(parseEth(500))
    })

    it('exiting changes stake balance', async () => {
      await farm.connect(staker1).stake(parseEth(1000), txArgs)
      await farm.connect(staker1).exit(parseEth(500), txArgs)
      expect(await farm.staked(staker1.address)).to.equal(parseEth(500))
      expect(await farm.totalStaked()).to.equal(parseEth(500))
    })

    it('cannot unstake more than is staked', async () => {
      await farm.connect(staker1).stake(parseEth(1000), txArgs)
      await expect(farm.connect(staker1).unstake(parseEth(1001), txArgs)).to.be.revertedWith('TrueSushiFarm: Cannot withdraw amount bigger than available balance')
    })

    it('cannot exit more than is staked', async () => {
      await farm.connect(staker1).stake(parseEth(1000), txArgs)
      await expect(farm.connect(staker1).exit(parseEth(1001), txArgs)).to.be.revertedWith('TrueSushiFarm: Cannot withdraw amount bigger than available balance')
    })

    it('yields rewards per staked tokens (using claim)', async () => {
      await farm.connect(staker1).stake(parseEth(1000), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).claim(txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(100)))
    })

    it('yields rewards per staked tokens (using exit)', async () => {
      await farm.connect(staker1).stake(parseEth(1000), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).exit(parseEth(1000), txArgs)
      
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(100)))
      expect(await sushi.balanceOf(staker1.address)).to.equal(totalSushiRewardPerBlock.mul(2))
    })
    
    it('estimate rewards correctly', async () => {
      await farm.connect(staker1).stake(parseEth(1000), txArgs)
      await timeTravel(provider, DAY)
      expect(expectScaledCloseTo((await farm.claimable(staker1.address, trustToken.address)), fromTru(100)))
      expect(expectScaledCloseTo(await farm.claimable(staker1.address, sushi.address), totalSushiRewardPerBlock.mul(1)))
      
      await timeTravel(provider, DAY)
      expect(expectScaledCloseTo((await farm.claimable(staker1.address, trustToken.address)), fromTru(200)))
      expect(expectScaledCloseTo(await farm.claimable(staker1.address, sushi.address), totalSushiRewardPerBlock.mul(2)))
      
      await farm.connect(staker1).unstake(100, txArgs)
      expect(expectScaledCloseTo((await farm.claimable(staker1.address, trustToken.address)), fromTru(200)))
      expect(expectScaledCloseTo(await farm.claimable(staker1.address, sushi.address), totalSushiRewardPerBlock.mul(3)))
      
      await farm.connect(staker1).claim(txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(200)))
      expect(expectScaledCloseTo((await sushi.balanceOf(staker1.address)), totalSushiRewardPerBlock.mul(4)))
      expect(expectScaledCloseTo(await farm.claimable(staker1.address, sushi.address), totalSushiRewardPerBlock.mul(0)))
      
      await farm.connect(staker1).claim(txArgs)
      expect(expectScaledCloseTo((await sushi.balanceOf(staker1.address)), totalSushiRewardPerBlock.mul(5)))
      expect(expectScaledCloseTo(await farm.claimable(staker1.address, sushi.address), totalSushiRewardPerBlock.mul(0)))
    })

    it('rewards when stake increases', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).claim(txArgs)

      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(200)))
    })

    it('sending stake tokens to TrueSushiFarm does not affect calculations', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await stakingToken.connect(staker1).transfer(farm.address, parseEth(500), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).claim(txArgs)

      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(100)))
    })

    it('staking claims pending rewards', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).stake(parseEth(500), txArgs)

      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(100)))
    })

    it('claiming clears claimableRewards', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await timeTravel(provider, DAY)
      // force an update to claimableReward:
      await farm.connect(staker1).unstake(parseEth(1), txArgs)
      expect(await farm.claimableReward(trustToken.address, staker1.address)).to.be.gt(0)

      await farm.connect(staker1).claim(txArgs)
      expect(await farm.claimableReward(trustToken.address, staker1.address)).to.equal(0)
      expect(await farm.claimable(staker1.address, trustToken.address)).to.equal(0)
    })

    it('claimable is zero from the start', async () => {
      expect(await farm.claimable(staker1.address, trustToken.address)).to.equal(0)
    })

    it('claimable is callable after unstake', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).unstake(parseEth(500), txArgs)
      expect(await farm.claimable(staker1.address, trustToken.address)).to.be.gt(0)
    })

    it('calling distribute does not break reward calculations', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await timeTravel(provider, DAY)
      await distributor.distribute(txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).claim(txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(200)))
    })

    it('owner withdrawing distributes funds', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      expect(expectCloseTo((await trustToken.balanceOf(farm.address)), fromTru(0), 2e6))
      await timeTravel(provider, DAY)
      await distributor.connect(owner).empty(txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(farm.address)), fromTru(100)))
      await farm.connect(staker1).claim(txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(100)))
      expect(expectCloseTo((await trustToken.balanceOf(farm.address)), fromTru(0), 2e6))
    })

    it('changing farm distributes funds', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      expect(expectCloseTo((await trustToken.balanceOf(farm.address)), fromTru(0), 2e6))
      await timeTravel(provider, DAY)
      await distributor.connect(owner).setFarm(farm2.address, txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(farm.address)), fromTru(100)))
      await farm.connect(staker1).claim(txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), fromTru(100)))
      expect(expectCloseTo((await trustToken.balanceOf(farm.address)), fromTru(0), 2e6))
    })

    it('can withdraw liquidity after all TRU is distributed', async () => {
      await farm.connect(staker1).stake(parseEth(500), txArgs)
      await timeTravel(provider, DAY * REWARD_DAYS)
      await farm.connect(staker1).claim(txArgs)
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), amount))
      await timeTravel(provider, DAY)
      await farm.connect(staker1).unstake(parseEth(500), txArgs)
    })
  })

  describe('with two stakers', function () {
    const dailyReward = amount.div(REWARD_DAYS)

    beforeEach(async () => {
      // staker1 with 4/5 of stake
      await farm.connect(staker1).stake(parseEth(400), txArgs)
      // staker 2 has 1/5 of stake
      await farm.connect(staker2).stake(parseEth(100), txArgs)
      await timeTravelTo(provider, start)
    })

    it('earn rewards in proportion to stake share (TRU)', async () => {
      const days = 1
      await timeTravel(provider, DAY * days)
      await farm.connect(staker1).claim(txArgs)
      await farm.connect(staker2).claim(txArgs)

      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)),
        dailyReward.mul(days).mul(4).div(5)))
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker2.address)),
        dailyReward.mul(days).mul(1).div(5)))
    })

    it('if additional funds are transferred to farm, they are also distributed accordingly to shares (TRU)', async () => {
      const days = 1
      const additionalReward = fromTru(100)
      const totalReward = dailyReward.add(additionalReward)
      await timeTravel(provider, DAY * days)
      await trustToken.mint(farm.address, additionalReward, txArgs)
      await farm.connect(staker1).claim(txArgs)
      await farm.connect(staker2).claim(txArgs)

      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)),
        totalReward.mul(days).mul(4).div(5)))
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker2.address)),
        totalReward.mul(days).mul(1).div(5)))
    })

    it('handles reward calculation after unstaking (TRU)', async () => {
      const days = 1
      await timeTravel(provider, DAY)
      await farm.connect(staker1).unstake(parseEth(300), txArgs)
      await timeTravel(provider, DAY)
      await farm.connect(staker1).claim(txArgs)
      await farm.connect(staker2).claim(txArgs)

      const staker1Reward = dailyReward.mul(days).mul(4).div(5).add(
        dailyReward.mul(days).mul(1).div(2))
      const staker2Reward = dailyReward.mul(days).mul(1).div(5).add(
        dailyReward.mul(days).mul(1).div(2))

      expect(expectScaledCloseTo((await trustToken.balanceOf(staker1.address)), staker1Reward))
      expect(expectScaledCloseTo((await trustToken.balanceOf(staker2.address)), staker2Reward))
    })

    it('earn rewards in proportion to stake share (SUSHI)', async () => {
      await provider.send('evm_mine', [])
      // 4 blocks after stake
      // full reward for 1 block and 4/5 for 3 = 17/5 block rewards
      await farm.connect(staker1).claim(txArgs)
      await provider.send('evm_mine', [])
      await provider.send('evm_mine', [])
      // 6 blocks after stake
      await farm.connect(staker2).claim(txArgs)

      expect(await sushi.balanceOf(staker1.address)).to.equal(totalSushiRewardPerBlock.mul(17).div(5))
      expect(await sushi.balanceOf(staker2.address)).to.equal(totalSushiRewardPerBlock.mul(6).div(5))
    })

    it('if additional funds are transferred to farm, they are also distributed accordingly to shares (SUSHI)', async () => {
      const additionalReward = fromTru(100)
      const totalReward = totalSushiRewardPerBlock.add(additionalReward)
      await sushi.mint(farm.address, additionalReward, txArgs)
      await provider.send('evm_mine', [])
      await farm.connect(staker1).claim(txArgs)
      await farm.connect(staker2).claim(txArgs)

      expect(await sushi.balanceOf(staker1.address)).to.equal(totalSushiRewardPerBlock.mul(17).div(5).add(totalReward.mul(4).div(5)))
      expect(await sushi.balanceOf(staker2.address)).to.equal(totalSushiRewardPerBlock.mul(4).div(5).add(totalReward.mul(1).div(5)))
    })

    it('handles reward calculation after unstaking (SUSHI)', async () => {
      await provider.send('evm_mine', [])
      // 4 blocks after stake
      // full reward for 1 block and 4/5 for 3 = 17/5 block rewards
      await farm.connect(staker1).exit(parseEth(400), txArgs)
      await provider.send('evm_mine', [])
      await provider.send('evm_mine', [])
      // 6 blocks after stake, 3 block for 1/5, 3 blocks for full
      await farm.connect(staker2).claim(txArgs)

      expect(await sushi.balanceOf(staker1.address)).to.equal(totalSushiRewardPerBlock.mul(17).div(5))
      expect(await sushi.balanceOf(staker2.address)).to.equal(totalSushiRewardPerBlock.mul(18).div(5))
    })
  })
})
