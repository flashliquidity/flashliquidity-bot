import { ethers, network } from "hardhat"
import { expect } from "chai"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { ADDRESS_ZERO, FACTORY_ADDR, WETH_ADDR, ROUTER_ADDR } from "./utilities"

const factoryJson = require("./core-deployments/FlashLiquidityFactory.json")
const routerJson = require("./core-deployments/FlashLiquidityRouter.json")

describe("FlashBotFactory", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.transferGovernanceDelay = 60
        this.bob = this.signers[1]
        this.dev = this.signers[2]
        this.minter = this.signers[3]
        this.alice = this.signers[4]
        this.bastion = this.signers[5]
        this.lpToken = this.signers[6]
        this.externalPool = this.signers[4]
        this.wethPriceFeed = this.signers[5]
        this.rewardTokenPriceFeed = this.signers[6]
        this.bastion = this.signers[5]
        this.FlashBotFactory = await ethers.getContractFactory("FlashBotFactory")
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
    })

    beforeEach(async function () {
        this.factory = new ethers.Contract(FACTORY_ADDR, factoryJson.abi, this.dev)
        this.router = new ethers.Contract(ROUTER_ADDR, routerJson.abi, this.dev)
        this.flashbotFactory = await this.FlashBotFactory.deploy(
            WETH_ADDR,
            this.governor.address,
            this.transferGovernanceDelay
        )
        await this.flashbotFactory.deployed()
        this.token1 = await this.ERC20Mock.deploy("Mock token", "MOCK1", 1000000000)
        this.token2 = await this.ERC20Mock.deploy("Mock token", "MOCK2", 1000000000)
        await this.token1.deployed()
        await this.token2.deployed()
        await this.token1.connect(this.minter).transfer(this.bastion.address, 2000000)
        await this.token2.connect(this.minter).transfer(this.bastion.address, 2000000)
    })

    it("Should allow only Governor to request governance transfer", async function () {
        await expect(
            this.flashbotFactory.connect(this.bob).setPendingGovernor(this.bob.address)
        ).to.be.revertedWith("Only Governor")
        expect(await this.flashbotFactory.pendingGovernor()).to.not.be.equal(this.bob.address)
        await this.flashbotFactory.connect(this.governor).setPendingGovernor(this.bob.address)
        expect(await this.flashbotFactory.pendingGovernor()).to.be.equal(this.bob.address)
        expect(await this.flashbotFactory.govTransferReqTimestamp()).to.not.be.equal(0)
    })

    it("Should not allow to set pendingGovernor to zero address", async function () {
        await expect(
            this.flashbotFactory.connect(this.governor).setPendingGovernor(ADDRESS_ZERO)
        ).to.be.revertedWith("Zero Address")
    })

    it("Should allow to transfer governance only after min delay has passed from request", async function () {
        await this.flashbotFactory.connect(this.governor).setPendingGovernor(this.bob.address)
        await expect(this.flashbotFactory.transferGovernance()).to.be.revertedWith("Too Early")
        await time.increase(this.transferGovernanceDelay)
        await this.flashbotFactory.transferGovernance()
        expect(await this.flashbotFactory.governor()).to.be.equal(this.bob.address)
    })

    it("Should allow only Governor to initialize the connector to Bastion", async function () {
        await expect(
            this.flashbotFactory.connect(this.bob).initialize(this.bastion.address)
        ).to.be.revertedWith("Only Governor")
        await this.flashbotFactory.connect(this.governor).initialize(this.bastion.address)
    })

    it("Should not allow to initialize the connector to Bastion more then once", async function () {
        await this.flashbotFactory.connect(this.governor).initialize(this.bastion.address)
        await expect(
            this.flashbotFactory.connect(this.governor).initialize(this.bastion.address)
        ).to.be.revertedWith("Already Initialized")
    })

    it("Should not allow to deploy FlashBots until initialized", async function () {
        await expect(
            this.flashbotFactory
                .connect(this.governor)
                .deployFlashbot(
                    this.token1.address,
                    this.token2.address,
                    this.lpToken.address,
                    [this.externalPool.address],
                    ADDRESS_ZERO,
                    this.wethPriceFeed.address,
                    this.rewardTokenPriceFeed.address,
                    1,
                    2,
                    3
                )
        ).to.be.revertedWith("Not Initialized")
    })

    it("Should allow only Bastion to deploy FlashBots", async function () {
        await this.flashbotFactory.connect(this.governor).initialize(this.bastion.address)
        await expect(
            this.flashbotFactory
                .connect(this.governor)
                .deployFlashbot(
                    this.token1.address,
                    this.token2.address,
                    this.lpToken.address,
                    [this.externalPool.address],
                    ADDRESS_ZERO,
                    this.wethPriceFeed.address,
                    this.rewardTokenPriceFeed.address,
                    1,
                    2,
                    3
                )
        ).to.be.revertedWith("Not Bastion")
        await this.flashbotFactory
            .connect(this.bastion)
            .deployFlashbot(
                this.token1.address,
                this.token2.address,
                this.lpToken.address,
                [this.externalPool.address],
                ADDRESS_ZERO,
                this.wethPriceFeed.address,
                this.rewardTokenPriceFeed.address,
                1,
                2,
                3
            )
    })
})
