import { ethers } from "hardhat"
import { expect } from "chai"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { ADDRESS_ZERO, LINKERC667, REGISTRY_ADDR, REGISTRAR_ADDR } from "./utilities"

describe("UpkeepsStationFactory", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = this.signers[0]
        this.bob = this.signers[1]
        this.dev = this.signers[2]
        this.minter = this.signers[3]
        this.bastion = this.signers[4]
        this.transferGovernanceDelay = 60
        this.toUpkeepAmount = ethers.utils.parseUnits("1.0", 18)
        this.createUpkeepAmount = ethers.utils.parseUnits("5.0", 18)
        this.UpkeepsStationFactory = await ethers.getContractFactory("UpkeepsStationFactory")
    })

    beforeEach(async function () {
        this.link = await ethers.getContractAt("LinkTokenInterface", LINKERC667)
        this.registry = await ethers.getContractAt("KeeperRegistryInterface", REGISTRY_ADDR)
        this.stationFactory = await this.UpkeepsStationFactory.deploy(
            this.governor.address,
            REGISTRAR_ADDR,
            LINKERC667,
            REGISTRY_ADDR,
            this.transferGovernanceDelay,
            60,
            this.toUpkeepAmount,
            this.toUpkeepAmount,
            this.toUpkeepAmount,
            this.toUpkeepAmount,
            5
        )
        await this.stationFactory.deployed()
    })

    it("Should allow only Governor to request governance transfer", async function () {
        await expect(
            this.stationFactory.connect(this.bob).setPendingGovernor(this.bob.address)
        ).to.be.revertedWith("Only Governor")
        expect(await this.stationFactory.pendingGovernor()).to.not.be.equal(this.bob.address)
        await this.stationFactory.connect(this.governor).setPendingGovernor(this.bob.address)
        expect(await this.stationFactory.pendingGovernor()).to.be.equal(this.bob.address)
        expect(await this.stationFactory.govTransferReqTimestamp()).to.not.be.equal(0)
    })

    it("Should not allow to set pendingGovernor to zero address", async function () {
        await expect(
            this.stationFactory.connect(this.governor).setPendingGovernor(ADDRESS_ZERO)
        ).to.be.revertedWith("Zero Address")
    })

    it("Should allow to transfer governance only after min delay has passed from request", async function () {
        await this.stationFactory.connect(this.governor).setPendingGovernor(this.bob.address)
        await expect(this.stationFactory.transferGovernance()).to.be.revertedWith("Too Early")
        await time.increase(this.transferGovernanceDelay)
        await this.stationFactory.transferGovernance()
        expect(await this.stationFactory.governor()).to.be.equal(this.bob.address)
    })

    it("Should not allow to initialize the connector to Bastion more then once", async function () {
        await expect(
            this.stationFactory
                .connect(this.bob)
                .initialize(
                    this.bastion.address,
                    "STATION",
                    300000,
                    ethers.utils.formatBytes32String(""),
                    this.createUpkeepAmount
                )
        ).to.be.revertedWith("Only Governor")
    })
})
