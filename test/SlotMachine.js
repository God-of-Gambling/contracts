require('@nomicfoundation/hardhat-chai-matchers')
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const AddressZero = '0x0000000000000000000000000000000000000000'

describe("SlotMachine", function () {
    
    async function deployContract() {
        const [owner, admin, guardian, player1, player2] = await ethers.getSigners();
        const minBetValue = ethers.parseEther("1");
        const maxBetValue = ethers.parseEther("100");

        const Token = await ethers.getContractFactory("MockERC20");
        const token = await Token.deploy("Game Token", "GAME", 18);
        await token.waitForDeployment();
        const token_address = await token.getAddress()

        // Deploy SlotMachine contract
        SlotMachine = await ethers.getContractFactory("SlotMachine");
        slotMachine = await SlotMachine.deploy(
        guardian.address,
        admin.address,
        token_address,
        minBetValue,
        maxBetValue
        );
        await slotMachine.waitForDeployment();
        const slot_machine_address = await slotMachine.getAddress()

        const domain = {
            name: "SlotMachine",
            version: "1",
            chainId: 1337, // Hardhat's default chain ID
            verifyingContract: slot_machine_address // Will be replaced
        };
          
        const types = {
            Bet: [
                { name: "user", type: "address" },
                { name: "amount", type: "uint256" },
                { name: "timestamp", type: "uint256" }
            ]
        };
    
        // Fund the contract with tokens
        await token.mint(slot_machine_address, ethers.parseEther("1000000"));
        
        // Fund players with tokens
        await token.mint(player1.address, ethers.parseEther("1000"));
        await token.mint(player2.address, ethers.parseEther("1000"));
        
        // Approve contract to spend player tokens
        await token.connect(player1).approve(slot_machine_address, ethers.parseEther("1000"));
        await token.connect(player2).approve(slot_machine_address, ethers.parseEther("1000"));
    
        return {
          owner,
          admin,
          guardian,
          player1,
          player2,
          slotMachine,
          token,
          minBetValue,
          maxBetValue,
          types,
          domain
        }
    }

    describe("Deployment", function () {
        it("Should set the right admin and guardian", async function () {
            const { slotMachine, admin, guardian } = await loadFixture(deployContract)
            expect(await slotMachine.admin()).to.equal(admin.address);
            expect(await slotMachine.guardian()).to.equal(guardian.address);
        });
        
        it("Should set the right token", async function () {
            const { slotMachine, token } = await loadFixture(deployContract)
            const token_address = await token.getAddress()
            expect(await slotMachine.token()).to.equal(token_address);
        });
        
        it("Should set the right bet values", async function () {
            const { slotMachine, minBetValue, maxBetValue } = await loadFixture(deployContract)
            expect(await slotMachine.minBetValue()).to.equal(minBetValue);
            expect(await slotMachine.maxBetValue()).to.equal(maxBetValue);
        });
        
        it("Should set the initial seed reels", async function () {
            const { slotMachine } = await loadFixture(deployContract)
            const seedReels = await Promise.all([
                slotMachine.seedReels(0),
                slotMachine.seedReels(1),
                slotMachine.seedReels(2)
            ]);
        
            expect(seedReels[0]).to.equal(10n);
            expect(seedReels[1]).to.equal(1000n);
            expect(seedReels[2]).to.equal(10000n);
        });

        it("Should initialize rewards correctly", async function () {
            // Check first reward (A,A,A)
            const { slotMachine } = await loadFixture(deployContract)
            const reward = await slotMachine.rewards(0);
            expect(reward.reels[0]).to.equal(0n); // Reels.A == 0
            expect(reward.reels[1]).to.equal(0n);
            expect(reward.reels[2]).to.equal(0n);
            expect(reward.multiply).to.equal(15n);
        });
    });
  
    describe("Betting", function () {
        afterEach(async function () {
            await new Promise(resolve => setTimeout(resolve, 20000)); // Delay 20s
        });
        it("Should allow placing a valid bet", async function () {
            const { slotMachine, player1, admin, types, domain, token } = await loadFixture(deployContract)
            const betAmount = ethers.parseEther("5");
            const timestamp = Math.floor(Date.now() / 1000) - (10 + Math.floor(Math.random() * 10));
        
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp
            };
        
            // Sign the bet data with admin's private key
            const signature = await admin.signTypedData(domain, types, bet);
            
            // Get token balance before bet
            const balanceBefore = await token.balanceOf(player1.address);
            
            // Place bet
            await time.increaseTo(timestamp);
            await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
                .to.emit(slotMachine, "Result");
                
            // Check token transfer occurred
            const balanceAfter = await token.balanceOf(player1.address);
            
            // The difference could be betAmount (loss) or some other value (win)
            // We just verify some transaction happened
            expect(balanceBefore).to.not.equal(balanceAfter);
        });
        
        it("Should reject bet with invalid signature", async function () {
            const { slotMachine, player1, types, domain } = await loadFixture(deployContract)
            const betAmount = ethers.parseEther("5");
            const timestamp = Math.floor(Date.now() / 1000) - (10 + Math.floor(Math.random() * 20));
            
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp
            };
        
            // Sign with player1 instead of admin (invalid)
            const signature = await player1.signTypedData(domain, types, bet);
        
            await time.increaseTo(timestamp);
            await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
                .to.be.revertedWith("Invalid signature");
            });
        
        it("Should reject bet below minimum value", async function () {
            const { slotMachine, player1, types, domain, admin } = await loadFixture(deployContract)
            const betAmount = ethers.parseEther("0.5"); // Below min
            const timestamp = Math.floor(Date.now() / 1000) - (10 + Math.floor(Math.random() * 20));
        
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp: timestamp
            };
        
            const signature = await admin.signTypedData(domain, types, bet);
            
            await time.increaseTo(timestamp);
            await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
                .to.be.revertedWith("The bet amount must be greater than the minimum required value.");
        });
        
        it("Should reject bet above maximum value", async function () {
            const { slotMachine, player1, types, domain, admin } = await loadFixture(deployContract)
            const betAmount = ethers.parseEther("101"); // Above max
            const timestamp = Math.floor(Date.now() / 1000) - (10 + Math.floor(Math.random() * 20));
            
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp
            };
        
            const signature = await admin.signTypedData(domain, types, bet);
        
            await time.increaseTo(timestamp);
            await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
                .to.be.revertedWith("Bet exceeds maximum limit");
        });
        
        it("Should reject expired timestamp", async function () {
            const { slotMachine, player1, types, domain, admin } = await loadFixture(deployContract)
            const betAmount = ethers.parseEther("5");
            const timestamp = Math.floor(Date.now() / 1000) - (10 + Math.floor(Math.random() * 20));
            
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp
            };
        
            const signature = await admin.signTypedData(domain, types, bet);
        
            // Time moves forward more than 60 seconds
            await time.increaseTo(timestamp + 70);
            await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
                .to.be.revertedWith("Timestamp expired");
        });
        
        it("Should reject timestamp from the future", async function () {
            const { slotMachine, player1, types, domain, admin } = await loadFixture(deployContract)
            const betAmount = ethers.parseEther("5");
            const timestamp = Math.floor(Date.now() / 1000) + 3600; // 1 hour in the future
        
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp
            };
        
            const signature = await admin.signTypedData(domain, types, bet);
        
        await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
            .to.be.revertedWith("Timestamp from the future");
        });
        
        it("Should reject reusing timestamp", async function () {
            const { slotMachine, player1, types, domain, admin } = await loadFixture(deployContract)
            const betAmount = ethers.parseEther("5");
            const timestamp = Math.floor(Date.now() / 1000) - (10 + Math.floor(Math.random() * 20));
            
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp: timestamp
            };
        
            const signature = await admin.signTypedData(domain, types, bet);
        
            await time.increaseTo(timestamp);
            await slotMachine.connect(player1).placeBet(betAmount, timestamp, signature);
        
            // Try to place another bet with the same timestamp
            await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
                .to.be.revertedWith("Timestamp must be newer");
        });
    });
  
    describe("Admin Functions", function () {
        it("Should allow admin to change min bet value", async function () {
            const { slotMachine, admin } = await loadFixture(deployContract)

            const newMinBet = ethers.parseEther("2");
            
            await expect(slotMachine.connect(admin).changeMinBetValue(newMinBet))
                .to.emit(slotMachine, "ChangedMinBetValue")
                .withArgs(admin.address, newMinBet);
            
            expect(await slotMachine.minBetValue()).to.equal(newMinBet);
        });
        
        it("Should allow admin to change max bet value", async function () {
            const newMaxBet = ethers.parseEther("200");
            const { slotMachine, admin } = await loadFixture(deployContract)
            
            await expect(slotMachine.connect(admin).changeMaxBetValue(newMaxBet))
                .to.emit(slotMachine, "ChangedMaxBetValue")
                .withArgs(admin.address, newMaxBet);
            
            expect(await slotMachine.maxBetValue()).to.equal(newMaxBet);
        });
        
        it("Should reject min bet value change from non-admin", async function () {
            const { slotMachine, player1 } = await loadFixture(deployContract)
            await expect(slotMachine.connect(player1).changeMinBetValue(ethers.parseEther("2")))
                .to.be.revertedWith("Only admin can execute this");
        });
        
        it("Should reject max bet value change from non-admin", async function () {
            const { slotMachine, player1 } = await loadFixture(deployContract)
            await expect(slotMachine.connect(player1).changeMaxBetValue(ethers.parseEther("200")))
                .to.be.revertedWith("Only admin can execute this");
        });
        
        it("Should reject invalid bet value changes", async function () {
            // Min bet greater than max bet
            const { slotMachine, admin } = await loadFixture(deployContract)
            await expect(slotMachine.connect(admin).changeMinBetValue(ethers.parseEther("200")))
                .to.be.revertedWith("The maxium bet value greater than minium bet value");
            
            // Max bet less than min bet
            const newMin = ethers.parseEther("50");
            await slotMachine.connect(admin).changeMinBetValue(newMin);
            await expect(slotMachine.connect(admin).changeMaxBetValue(ethers.parseEther("40")))
                .to.be.revertedWith("The maxium bet value greater than minium bet value");
        });
    });
  
    describe("Admin/Guardian Change", function () {
        it("Should allow admin to request admin change", async function () {
            const { slotMachine, admin, player1 } = await loadFixture(deployContract)
            await expect(slotMachine.connect(admin).requestAdminChange(player1.address))
                .to.emit(slotMachine, "AdminChangeRequested")
                .withArgs(player1.address, await time.latest());
            
            expect(await slotMachine.pendingAdmin()).to.equal(player1.address);
        });
        
        it("Should allow guardian to request guardian change", async function () {
            const { slotMachine, guardian, player1 } = await loadFixture(deployContract)
            await expect(slotMachine.connect(guardian).requestChangeGuardian(player1.address))
                .to.emit(slotMachine, "GuardianChangeRequested")
                .withArgs(player1.address, await time.latest());
            
            expect(await slotMachine.pendingGuardian()).to.equal(player1.address);
        });
        
        it("Should confirm admin change after waiting period", async function () {
            const { slotMachine, admin, player1 } = await loadFixture(deployContract)
            await slotMachine.connect(admin).requestAdminChange(player1.address);
            
            // Fast forward 3 days
            await time.increase(3 * 24 * 60 * 60 + 1);
            
            await expect(slotMachine.connect(admin).confirmAdminChange())
                .to.emit(slotMachine, "AdminChanged")
                .withArgs(player1.address);
            
            expect(await slotMachine.admin()).to.equal(player1.address);
            expect(await slotMachine.pendingAdmin()).to.equal(AddressZero);
        });
        
        it("Should confirm guardian change after waiting period", async function () {
            const { slotMachine, guardian, player1 } = await loadFixture(deployContract)
            await slotMachine.connect(guardian).requestChangeGuardian(player1.address);
            
            // Fast forward 3 days
            await time.increase(3 * 24 * 60 * 60 + 1);
            
            await expect(slotMachine.connect(guardian).confirmChangeGuardian())
                .to.emit(slotMachine, "GuardianChanged")
                .withArgs(player1.address);
            
            expect(await slotMachine.guardian()).to.equal(player1.address);
            expect(await slotMachine.pendingGuardian()).to.equal(AddressZero);
        });
        
        it("Should not confirm admin change before waiting period", async function () {
            const { slotMachine, admin, player1 } = await loadFixture(deployContract)
            await slotMachine.connect(admin).requestAdminChange(player1.address);
            
            // Fast forward just 2 days
            await time.increase(2 * 24 * 60 * 60);
            
            await expect(slotMachine.connect(admin).confirmAdminChange())
                .to.be.revertedWith("Must wait 3 days to confirm admin change");
        });
        
        it("Should not confirm guardian change before waiting period", async function () {
            const { slotMachine, guardian, player1 } = await loadFixture(deployContract)
            await slotMachine.connect(guardian).requestChangeGuardian(player1.address);
            
            // Fast forward just 2 days
            await time.increase(2 * 24 * 60 * 60);
            
            await expect(slotMachine.connect(guardian).confirmChangeGuardian())
                .to.be.revertedWith("Must wait 3 days to confirm admin change");
        });
        
        it("Should allow guardian to cancel pending admin change", async function () {
            const { slotMachine, admin, guardian, player1 } = await loadFixture(deployContract)
            await slotMachine.connect(admin).requestAdminChange(player1.address);
            
            await expect(slotMachine.connect(guardian).cancelAdminChange())
                .to.emit(slotMachine, "AdminChangeCancelled");
            
            expect(await slotMachine.pendingAdmin()).to.equal(AddressZero);
        });
        
        it("Should allow guardian to cancel pending guardian change", async function () {
            const { slotMachine, guardian, player1 } = await loadFixture(deployContract)
            await slotMachine.connect(guardian).requestChangeGuardian(player1.address);
            
            await expect(slotMachine.connect(guardian).cancelGuardianChange())
                .to.emit(slotMachine, "GuardianChangeCancelled");
            
            expect(await slotMachine.pendingGuardian()).to.equal(AddressZero);
        });
    });
  
    describe("Seed Reels Management", function () {
        it("Should allow admin to request seed reels change", async function () {
            const { slotMachine, admin } = await loadFixture(deployContract)
            await expect(slotMachine.connect(admin).requestChangeSeedReels(20, 2000, 20000))
                .to.emit(slotMachine, "SeedReelsRequested");
            
            const pendingSeeds = [
                await slotMachine.pendingSeedReels(0),
                await slotMachine.pendingSeedReels(1),
                await slotMachine.pendingSeedReels(2)
            ];
            
            expect(pendingSeeds[0]).to.equal(20);
            expect(pendingSeeds[1]).to.equal(2000);
            expect(pendingSeeds[2]).to.equal(20000);
        });
        
        it("Should confirm seed reels change after waiting period", async function () {
            const { slotMachine, admin } = await loadFixture(deployContract)
            await slotMachine.connect(admin).requestChangeSeedReels(20, 2000, 20000);
            
            // Fast forward 3 days
            await time.increase(3 * 24 * 60 * 60 + 1);
            
            await expect(slotMachine.connect(admin).confirmChangeSeedReels())
                .to.emit(slotMachine, "SeedReelsChanged");
            
            const newSeeds = [
                await slotMachine.seedReels(0),
                await slotMachine.seedReels(1),
                await slotMachine.seedReels(2)
            ];
            
            expect(newSeeds[0]).to.equal(20);
            expect(newSeeds[1]).to.equal(2000);
            expect(newSeeds[2]).to.equal(20000);
        });
        
        it("Should not allow identical seed values", async function () {
            const { slotMachine, admin } = await loadFixture(deployContract)
            await expect(slotMachine.connect(admin).requestChangeSeedReels(20, 20, 20))
                .to.be.revertedWith("All three seed must be different");
        });
        
        it("Should not allow zero seed values", async function () {
            const { slotMachine, admin } = await loadFixture(deployContract)
            await expect(slotMachine.connect(admin).requestChangeSeedReels(0, 2000, 20000))
                .to.be.revertedWith("Seed reel must be greater than 0");
        });
    });
  
    describe("Fund Management", function () {
        it("Should allow admin to request fund withdrawal", async function () {
            const { slotMachine, admin } = await loadFixture(deployContract)
            await expect(slotMachine.connect(admin).requestWithdrawFund())
                .to.emit(slotMachine, "WithdrawFundRequested");
            
            expect(await slotMachine.pendingWithdrawFundTime()).to.not.equal(0);
        });
        
        it("Should allow admin to withdraw funds after waiting period", async function () {
            const { slotMachine, admin, token } = await loadFixture(deployContract)
            const slot_machine_address = await slotMachine.getAddress()
            // Request withdrawal
            await slotMachine.connect(admin).requestWithdrawFund();
            
            // Fast forward 7 days
            await time.increase(7 * 24 * 60 * 60 + 1);
        
            const withdrawAmount = ethers.parseEther("100");
            const contractBalanceBefore = await token.balanceOf(slot_machine_address);
            const adminBalanceBefore = await token.balanceOf(admin.address);
        
            await expect(slotMachine.connect(admin).withdrawFund(withdrawAmount))
                .to.emit(slotMachine, "WithdrawFund")
                .withArgs(admin.address, withdrawAmount);
            
            const contractBalanceAfter = await token.balanceOf(slot_machine_address);
            const adminBalanceAfter = await token.balanceOf(admin.address);
            
            expect(contractBalanceAfter).to.equal(contractBalanceBefore - withdrawAmount);
            expect(adminBalanceAfter).to.equal(adminBalanceBefore + withdrawAmount);
        });
        
        it("Should not allow withdrawal before waiting period", async function () {
            const { slotMachine, admin } = await loadFixture(deployContract)
            await slotMachine.connect(admin).requestWithdrawFund();
            
            // Fast forward just 6 days
            await time.increase(6 * 24 * 60 * 60);
            
            await expect(slotMachine.connect(admin).withdrawFund(ethers.parseEther("100")))
                .to.be.revertedWith("Must wait 7 days to withdraw funds");
        });
        
        it("Should allow guardian to cancel withdrawal request", async function () {
            const { slotMachine, admin, guardian } = await loadFixture(deployContract)
            await slotMachine.connect(admin).requestWithdrawFund();
            
            await expect(slotMachine.connect(guardian).cancelWithdrawFund())
                .to.emit(slotMachine, "WithdrawFundCancelled");
            
            expect(await slotMachine.pendingWithdrawFundTime()).to.equal(0);
        });
    });
  
    describe("Lock/Unlock Contract", function () {
        it("Should allow guardian to lock contract", async function () {
            const { slotMachine, guardian } = await loadFixture(deployContract)
            await expect(slotMachine.connect(guardian).lockContract())
                .to.emit(slotMachine, "ContractLocked")
                .withArgs(guardian.address);
            
            expect(await slotMachine.isLocked()).to.equal(true);
        });
        
        it("Should allow guardian to unlock contract", async function () {
            // First lock
            const { slotMachine, guardian } = await loadFixture(deployContract)
            await slotMachine.connect(guardian).lockContract();
            
            await expect(slotMachine.connect(guardian).unlockContract())
                .to.emit(slotMachine, "ContractUnlocked")
                .withArgs(guardian.address);
            
            expect(await slotMachine.isLocked()).to.equal(false);
        });
        
        it("Should prevent betting when contract is locked", async function () {
            const { slotMachine, guardian, admin, types, domain, player1 } = await loadFixture(deployContract)
            // Lock the contract
            await slotMachine.connect(guardian).lockContract();
            
            const betAmount = ethers.parseEther("5");
            const timestamp = Math.floor(Date.now() / 1000) - (10 + Math.floor(Math.random() * 20));
            
            const bet = {
                user: player1.address,
                amount: betAmount,
                timestamp
            };
            
            const signature = await admin.signTypedData(domain, types, bet);
            
            await time.increaseTo(timestamp);
            await expect(slotMachine.connect(player1).placeBet(betAmount, timestamp, signature))
                .to.be.revertedWith("Contract is locked");
        });
    });
});