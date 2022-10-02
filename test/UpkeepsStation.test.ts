import { ethers } from "hardhat"
import { expect } from "chai"
import { LINKERC667, REGISTRY_ADDR } from "./utilities"

describe("UpkeepsStation", function () {
    before(async function () {
        this.signers = await ethers.getSigners()
        this.governor = await this.signers[0]
        this.stationFactory = this.signers[1]
        this.bob = this.signers[3]
        this.minter = this.signers[4]
        this.bot = this.signers[5]
        this.UpkeepsStation = await ethers.getContractFactory("UpkeepsStation", this.stationFactory)
        this.ERC20Mock = await ethers.getContractFactory("ERC20Mock", this.minter)
    })

    beforeEach(async function () {
        this.link = await ethers.getContractAt("LinkTokenInterface", LINKERC667)
        this.registry = await ethers.getContractAt("KeeperRegistryInterface", REGISTRY_ADDR)
        this.station = await this.UpkeepsStation.deploy(LINKERC667, REGISTRY_ADDR)
        this.token1 = await this.ERC20Mock.deploy("Mock token", "MOCK1", 1000000000)
        this.token2 = await this.ERC20Mock.deploy("Mock token", "MOCK2", 1000000000)
        await this.token1.deployed()
        await this.token2.deployed()
        await this.token1.connect(this.minter).transfer(this.station.address, 2000000)
        await this.token2.connect(this.minter).transfer(this.station.address, 2000000)
    })

    it("Should set station factory address correctly", async function () {
        expect(await this.station.stationsFactory()).to.equal(this.stationFactory.address)
    })

    it("Should allow only station factory to revoke funds from station", async function () {
        await this.token1.connect(this.minter).transfer(this.station.address, 2000000)
        await this.token2.connect(this.minter).transfer(this.station.address, 2000000)
        await expect(
            this.station
                .connect(this.bob)
                .transferToStation([this.token1.address, this.token2.address], [2000000, 2000000])
        ).to.be.revertedWith("Only Stations Factory")
        await this.station
            .connect(this.stationFactory)
            .transferToStation([this.token1.address, this.token2.address], [2000000, 2000000])
        expect(await this.token1.balanceOf(this.stationFactory.address)).to.be.equal(2000000)
        expect(await this.token2.balanceOf(this.stationFactory.address)).to.be.equal(2000000)
    })

    it("Should allow only station factory to add upkeeps to station", async function () {
        await expect(
            this.station.connect(this.bob).addUpkeep(4444, this.bot.address)
        ).to.be.revertedWith("Only Stations Factory")
        await this.station.connect(this.stationFactory).addUpkeep(4444, this.bot.address)
    })

    it("Should not allow to add the same upkeep more then once", async function () {
        await this.station.connect(this.stationFactory).addUpkeep(4444, this.bot.address)
        await expect(
            this.station.connect(this.stationFactory).addUpkeep(4444, this.bob.address)
        ).to.be.revertedWith("Already Registered")
    })

    it("Should allow only station factory to remove upkeeps from station", async function () {
        await this.station.connect(this.stationFactory).addUpkeep(4444, this.bot.address)
        await expect(
            this.station.connect(this.bob).removeUpkeep(this.bot.address)
        ).to.be.revertedWith("Only Stations Factory")
    })
})
