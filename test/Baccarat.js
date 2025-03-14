require('@nomicfoundation/hardhat-chai-matchers')
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const AddressZero = '0x0000000000000000000000000000000000000000'

describe("Baccarat Contract", function () {
    async function deployContract() {
        const [owner, admin, guardian, player1, player2] = await ethers.getSigners();
        const minBetValue = ethers.parseEther("1");
        const maxBetValue = ethers.parseEther("100");

        const Token = await ethers.getContractFactory("MockERC20");
        const token = await Token.deploy("Game Token", "GAME", 18);
        await token.waitForDeployment();
        const token_address = await token.getAddress()

      // Deploy the Baccarat contract
        const BaccaratFactory = await ethers.getContractFactory("Baccarat");
        const baccarat = await BaccaratFactory.deploy(
            guardian.address,
            admin.address,
            token_address,
            minBetValue,
            maxBetValue
        );
        await baccarat.waitForDeployment();
        const baccarat_address = await baccarat.getAddress()

        const domain = {
            name: "Baccarat",
            version: "1",
            chainId: 1337, // Hardhat's default chain ID
            verifyingContract: baccarat_address // Will be replaced
        };
          
        const types = {
            Placed: [
                { name: "user", type: "address" },
                { name: "amount", type: "uint256" },
                { name: "timestamp", type: "uint256" }
            ]
        };
    
        // Fund the contract with tokens
        await token.mint(baccarat_address, ethers.parseEther("1000000"));
        
        // Fund players with tokens
        await token.mint(player1.address, ethers.parseEther("1000"));
        await token.mint(player2.address, ethers.parseEther("1000"));
        
        // Approve contract to spend player tokens
        await token.connect(player1).approve(baccarat_address, ethers.parseEther("1000"));
        await token.connect(player2).approve(baccarat_address, ethers.parseEther("1000"));
    
        return {
          owner,
          admin,
          guardian,
          player1,
          player2,
          baccarat,
          token,
          minBetValue,
          maxBetValue,
          types,
          domain
        }
    }

  describe("Constructor", function () {
    it("Should set initial state correctly", async function () {
        const { baccarat, admin, guardian, minBetValue, maxBetValue, token } = await loadFixture(deployContract)
        const token_address = await token.getAddress()
        expect(await baccarat.admin()).to.equal(admin.address);
        expect(await baccarat.guardian()).to.equal(guardian.address);
        expect(await baccarat.token()).to.equal(token_address);
        expect(await baccarat.miniumBetValue()).to.equal(minBetValue);
        expect(await baccarat.maxiumBetValue()).to.equal(maxBetValue);
        expect(await baccarat.winProbability()).to.equal(5);
        expect(await baccarat.isLocked()).to.equal(false);
    });
  });

  describe("Admin Functions", function () {
    it("Should allow admin to request admin change", async function () {
        const { baccarat, admin, player1 } = await loadFixture(deployContract)
        await expect(baccarat.connect(admin).requestAdminChange(player1.address))
            .to.emit(baccarat, "AdminChangeRequested")
            .withArgs(player1.address, await time.latest());

        expect(await baccarat.pendingAdmin()).to.equal(player1.address);
    });

    it("Should allow admin to confirm admin change after 3 days", async function () {
        const { baccarat, admin, player1 } = await loadFixture(deployContract)
        await baccarat.connect(admin).requestAdminChange(player1.address);
        const requestTime = await time.latest();
        
        // Try to confirm before 3 days elapsed
        await expect(baccarat.connect(admin).confirmAdminChange())
            .to.be.revertedWith("Must wait 3 days to confirm admin change");
        
        // Advance time by 3 days
        await time.increaseTo(requestTime + (3 * 24 * 60 * 60) + 1);
        
        await expect(baccarat.connect(admin).confirmAdminChange())
            .to.emit(baccarat, "AdminChanged")
            .withArgs(player1.address);
        
        expect(await baccarat.admin()).to.equal(player1.address);
        expect(await baccarat.pendingAdmin()).to.equal(AddressZero);
        expect(await baccarat.pendingAdminChangeTime()).to.equal(0);
    });

    it("Should allow guardian to cancel admin change", async function () {
        const { baccarat, admin, player1, guardian } = await loadFixture(deployContract)
        await baccarat.connect(admin).requestAdminChange(player1.address);
        
        await expect(baccarat.connect(guardian).cancelAdminChange())
            .to.emit(baccarat, "AdminChangeCancelled");
        
        expect(await baccarat.pendingAdmin()).to.equal(AddressZero);
        expect(await baccarat.pendingAdminChangeTime()).to.equal(0);
    });

    it("Should allow admin to change win probability", async function () {
      const newProbability = 10;
      const { baccarat, admin } = await loadFixture(deployContract)
      
      await expect(baccarat.connect(admin).requestChangeWinProbability(newProbability))
        .to.emit(baccarat, "WinProbabilityRequested")
        .withArgs(newProbability);
      
        expect(await baccarat.pendingWinProbability()).to.equal(newProbability);
        
        const requestTime = await time.latest();
        
        // Try to confirm before 3 days elapsed
        await expect(baccarat.connect(admin).confirmChangeWinProbability())
            .to.be.revertedWith("Must wait 3 days to confirm seed reels change");
        
        // Advance time by 3 days
        await time.increaseTo(requestTime + (3 * 24 * 60 * 60) + 1);
        
        await expect(baccarat.connect(admin).confirmChangeWinProbability())
            .to.emit(baccarat, "WinProbabilityChanged")
            .withArgs(newProbability);
        
        expect(await baccarat.winProbability()).to.equal(newProbability);
    });

    it("Should allow admin to change bet limits", async function () {
        const { baccarat, admin } = await loadFixture(deployContract)
        const newMinBet = ethers.parseEther("0.2");
        const newMaxBet = ethers.parseEther("20");
        
        await expect(baccarat.connect(admin).changeMinBetValue(newMinBet))
            .to.emit(baccarat, "ChangedMinBetValue")
            .withArgs(admin.address, newMinBet);
        
        expect(await baccarat.miniumBetValue()).to.equal(newMinBet);
        
        await expect(baccarat.connect(admin).changeMaxBetValue(newMaxBet))
            .to.emit(baccarat, "ChangedMaxBetValue")
            .withArgs(admin.address, newMaxBet);
        
        expect(await baccarat.maxiumBetValue()).to.equal(newMaxBet);
    });

    it("Should reject invalid bet limit changes", async function () {
        const { baccarat, admin, minBetValue, maxBetValue } = await loadFixture(deployContract)

        await expect(baccarat.connect(admin).changeMinBetValue(0))
            .to.be.revertedWith("The minium bet value greater than 0");
        
        await expect(baccarat.connect(admin).changeMinBetValue(maxBetValue + 1n))
            .to.be.revertedWith("The maxium bet value greater than minium bet value");
        
        await expect(baccarat.connect(admin).changeMaxBetValue(0))
            .to.be.revertedWith("The maxium bet value greater than 0");
        
        await expect(baccarat.connect(admin).changeMaxBetValue(minBetValue + 1n))
            .to.be.revertedWith("The maxium bet value greater than minium bet value");
        });
  });

  describe("Guardian Functions", function () {
    it("Should allow guardian to request guardian change", async function () {
        const { baccarat, guardian, player1 } = await loadFixture(deployContract)
        await expect(baccarat.connect(guardian).requestChangeGuardian(player1.address))
            .to.emit(baccarat, "GuardianChangeRequested")
            .withArgs(player1.address, await time.latest());

        expect(await baccarat.pendingGuardian()).to.equal(player1.address);
    });

    it("Should allow guardian to confirm guardian change after 3 days", async function () {
        const { baccarat, guardian, player1 } = await loadFixture(deployContract)
        await baccarat.connect(guardian).requestChangeGuardian(player1.address);
        const requestTime = await time.latest();
        
        // Advance time by 3 days
        await time.increaseTo(requestTime + (3 * 24 * 60 * 60) + 1);
        
        await expect(baccarat.connect(guardian).confirmChangeGuardian())
            .to.emit(baccarat, "GuardianChanged")
            .withArgs(player1.address);
        
        expect(await baccarat.guardian()).to.equal(player1.address);
    });

    it("Should allow guardian to lock and unlock the contract", async function () {
        const { baccarat, guardian, player1 } = await loadFixture(deployContract)
        await expect(baccarat.connect(guardian).lockContract())
            .to.emit(baccarat, "ContractLocked")
            .withArgs(guardian.address);
        
        expect(await baccarat.isLocked()).to.equal(true);
        
        await expect(baccarat.connect(guardian).unlockContract())
            .to.emit(baccarat, "ContractUnlocked")
            .withArgs(guardian.address);
        
        expect(await baccarat.isLocked()).to.equal(false);
    });
  });

  describe("Fund Withdrawal", function () {
    it("Should allow admin to request and withdraw funds after 7 days", async function () {
        const { baccarat, admin } = await loadFixture(deployContract)
        await expect(baccarat.connect(admin).requestWithdrawFund())
            .to.emit(baccarat, "WithdrawFundRequested");
      
        const requestTime = await time.latest();
        
        // Try to withdraw before 7 days elapsed
        await expect(baccarat.connect(admin).withdrawFund(ethers.parseEther("1000")))
            .to.be.revertedWith("Must wait 7 days to withdraw funds");
        
        // Advance time by 7 days
        await time.increaseTo(requestTime + (7 * 24 * 60 * 60) + 1);
        
        const withdrawAmount = ethers.parseEther("1000");
        const adminBalanceBefore = await token.balanceOf(admin.address);
        
        await expect(baccarat.connect(admin).withdrawFund(withdrawAmount))
            .to.emit(baccarat, "WithdrawFund")
            .withArgs(admin.address, withdrawAmount);
        
        const adminBalanceAfter = await token.balanceOf(admin.address);
        expect(adminBalanceAfter.sub(adminBalanceBefore)).to.equal(withdrawAmount);
    });

    it("Should allow guardian to cancel withdrawal request", async function () {
        const { baccarat, admin, guardian } = await loadFixture(deployContract)
        await baccarat.connect(admin).requestWithdrawFund();
        
        await expect(baccarat.connect(guardian).cancelWithdrawFund())
            .to.emit(baccarat, "WithdrawFundCancelled");
        
        expect(await baccarat.pendingWithdrawFundTime()).to.equal(0);
    });
  });

  describe("Bet Placement", function () {
    afterEach(async function () {
        await new Promise(resolve => setTimeout(resolve, 20000)); // Delay 20s
    });
    it("Should validate signature and allow placing bets", async function () {
        const { baccarat, admin, token, player1, domain, types } = await loadFixture(deployContract)
        const betAmount = ethers.parseEther("1");
        const timestamp = await time.latest();

        // Create bets
        const bets = [
            {
            amount: betAmount,
            betType: 0 // PLAYER
            }
        ];

        const placed = {
            user: player1.address,
            amount: betAmount,
            timestamp: timestamp
        };

        // Sign with admin's key
        const signature = await admin.signTypedData(domain, types, placed);
        
        // User balance before
        const userBalanceBefore = await token.balanceOf(player1.address);
        
        // Place bet
        await baccarat.connect(player1).placeBet(bets, betAmount, timestamp, signature);
        
        // User balance after
        const userBalanceAfter = await token.balanceOf(player1.address);
        
        // Check that the user's balance has decreased by the bet amount
        expect(userBalanceBefore.sub(userBalanceAfter)).to.equal(betAmount);
        
        // Check that timestamp was recorded
        expect(await baccarat.lastTimestamp(player1.address)).to.equal(timestamp);
    });

    it("Should reject bets with invalid signatures", async function () {
        const { baccarat, player1, player2, domain, types } = await loadFixture(deployContract)
        const betAmount = ethers.parseEther("1");
        const timestamp = await time.latest();


        const bets = [{ amount: betAmount, betType: 0 }];

        const placed = {
            user: player1.address,
            amount: betAmount,
            timestamp: timestamp
        };

        // Sign with user2's key instead of admin
        const invalidSignature = await player2.signTypedData(domain, types, placed);
        
        // Try to place bet with invalid signature
        await expect(baccarat.connect(player1).placeBet(bets, betAmount, timestamp, invalidSignature))
            .to.be.revertedWith("Invalid signature");
    });

    it("Should reject bets with expired timestamps", async function () {
        const { baccarat, player1, admin, domain, types } = await loadFixture(deployContract)
        const betAmount = ethers.parseEther("1");
        const timestamp = await time.latest();
    
        // Advance time by more than 60 seconds
        await time.increase(61);
        
        const bets = [{ amount: betAmount, betType: 0 }];
        
        const placed = {
            user: player1.address,
            amount: betAmount,
            timestamp: timestamp
        };

        const signature = await admin.signTypedData(domain, types, placed);
      
        // Try to place bet with expired timestamp
        await expect(baccarat.connect(player1).placeBet(bets, betAmount, timestamp, signature))
            .to.be.revertedWith("Timestamp expired");
    });

    it("Should reject bets when contract is locked", async function () {
        const { baccarat, guardian, admin, player1, domain, types } = await loadFixture(deployContract)
        const betAmount = ethers.parseEther("1");
        const timestamp = await time.latest();
       
        const bets = [{ amount: betAmount, betType: 0 }];
      
        const placed = {
            user: player1.address,
            amount: betAmount,
            timestamp: timestamp
        };

        const signature = await admin.signTypedData(domain, types, placed);
      
        // Lock the contract
        await baccarat.connect(guardian).lockContract();
        
        // Try to place bet when contract is locked
        await expect(baccarat.connect(player1).placeBet(bets, betAmount, timestamp, signature))
            .to.be.revertedWith("Contract is locked");
    });

    it("Should verify bet amount restrictions", async function () {
        const timestamp = await time.latest();
        const { baccarat, admin, player1, domain, types, minBetValue, maxBetValue } = await loadFixture(deployContract)
        
        // Try with too small bet
        const tooSmallBet = minBetValue - 1n;
        const tooSmallBets = [{ amount: tooSmallBet, betType: 0 }];
        
        // Create signature for small bet
        const smallPlaced = {
            user: player1.address,
            amount: tooSmallBet,
            timestamp: timestamp
        };
      
      const smallSignature = await admin.signTypedData(domain, types, smallPlaced );
      
      await expect(baccarat.connect(player1).placeBet(tooSmallBets, tooSmallBet, timestamp, smallSignature))
        .to.be.revertedWith("The bet amount must be greater than the minimum required value");
      
        // Try with too large bet
        const tooLargeBet = maxBetValue + 1n;
        const tooLargeBets = [{ amount: tooLargeBet, betType: 0 }];
      
      // Create signature for large bet
      const largePlaced = {
        user: player1.address,
        amount: tooLargeBet,
        timestamp: timestamp
      };
      
      const largeSignature = await admin._signTypedData(domain, types, largePlaced);
      
      await expect(baccarat.connect(user1).placeBet(tooLargeBets, tooLargeBet, timestamp, largeSignature))
        .to.be.revertedWith("Bet exceeds maximum limit");
    });
  });
});