// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import "hardhat/console.sol";

contract SlotMachine is ReentrancyGuard {

    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    enum Reels { A, GRAPE, ORANGE, MELON, CHERRY, J, LEMON, K, Q }

    struct Bet {
        address user;
        uint256 amount;
        uint256 timestamp;
    }

    struct Reward {
        Reels[3] reels;
        uint256 multiply;
    }

    Reward[] public rewards;
    IERC20 public immutable token;

    address public admin;
    address public guardian;
    address public pendingAdmin;
    uint256 public pendingAdminChangeTime;
    address public pendingGuardian;
    uint256 public pendingGuardianChangeTime;
    uint256 public pendingWithdrawFundTime;

    uint256[3] public pendingSeedReels;
    uint256 public pendingSeedReelsChangeTime;

    uint256 public maxBetValue;
    uint256 public minBetValue;
    
    uint256[3] public seedReels;

    bool public isLocked = false;

    mapping(address => uint256) public lastTimestamp;

    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant BET_TYPEHASH = keccak256(
        "Bet(address user,uint256 amount,uint256 timestamp)"
    );

    bytes32 private immutable DOMAIN_SEPARATOR;
    uint256 public immutable maxRewardMultiply;

    event Result(address user, Reels[3] reels, uint256 amountWon);
    event WithdrawFund(address to, uint256 amount);
    event WithdrawFundRequested(uint256 requestTime);
    event ContractLocked(address by);
    event ContractUnlocked(address by);
    event AdminChangeRequested(address newAdmin, uint256 requestTime);
    event AdminChanged(address newAdmin);
    event AdminChangeCancelled();
    event GuardianChangeRequested(address newGuardian, uint256 requestTime);
    event GuardianChanged(address newGuardian);
    event GuardianChangeCancelled();
    event ChangedMinBetValue(address admin, uint256 minBetValue);
    event ChangedMaxBetValue(address admin, uint256 maxBetValue);
    event WithdrawFundCancelled();
    event SeedReelsChanged(uint256[3] seedReels);
    event SeedReelsRequested(uint256[3] seedReels);
    event SeedReelsChangeCancelled();

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can execute this");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Only guardian can execute this");
        _;
    }

    modifier notLocked() {
        require(!isLocked, "Contract is locked");
        _;
    }

    constructor(address _guardian, address _admin, address _token, uint256 _minBetValue, uint256 _maxBetValue) {
        require(_admin != address(0), "Invalid admin address");
        require(_guardian != address(0), "Invalid guardian address");
        require(_token != address(0), "Invalid token address");
        require(_maxBetValue > 0 && _minBetValue > 0 && _maxBetValue >= _minBetValue, "Invalid bet values");

        admin = _admin;
        guardian = _guardian;
        token = IERC20(_token);
        maxBetValue = _maxBetValue;
        minBetValue = _minBetValue;

        seedReels = [10,1000,10000];

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("SlotMachineBrokerV4")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        maxRewardMultiply = 15;
        rewards.push(Reward([Reels.A, Reels.A, Reels.A], 15));
        rewards.push(Reward([Reels.K, Reels.K, Reels.K], 15));
        rewards.push(Reward([Reels.Q, Reels.Q, Reels.Q], 15));
        rewards.push(Reward([Reels.J, Reels.J, Reels.J], 15));
        rewards.push(Reward([Reels.LEMON, Reels.LEMON, Reels.LEMON], 8));
        rewards.push(Reward([Reels.CHERRY, Reels.CHERRY, Reels.CHERRY], 3));
        rewards.push(Reward([Reels.GRAPE, Reels.GRAPE, Reels.GRAPE], 5));
        rewards.push(Reward([Reels.ORANGE, Reels.ORANGE, Reels.ORANGE], 12));
        rewards.push(Reward([Reels.MELON, Reels.MELON, Reels.MELON], 10));
    }

    function _hashBet(Bet memory bet) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                BET_TYPEHASH,
                bet.user,
                bet.amount,
                bet.timestamp
            )
        );
    }

    function _toTypedDataHash(Bet memory bet) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _hashBet(bet))
        );
    }

    function _verifySignature(Bet memory bet, bytes calldata signature) internal view returns (bool) {
        bytes32 digest = _toTypedDataHash(bet);
        return ECDSA.recover(digest, signature) == admin;
    }

    function placeBet(uint256 amount, uint256 _timestamp, bytes calldata signature) external notLocked nonReentrant {
        require(amount >= minBetValue, "The bet amount must be greater than the minimum required value.");
        require(amount <= maxBetValue, "Bet exceeds maximum limit");
        
        uint256 maxPotentialPayout = amount * maxRewardMultiply;
        require(token.balanceOf(address(this)) >= maxPotentialPayout, "Contract has insufficient funds");

        // Check timestamp
        require(block.timestamp >= _timestamp, "Timestamp from the future");
        require(block.timestamp <= _timestamp + 60, "Timestamp expired");
        require(_timestamp > lastTimestamp[msg.sender], "Timestamp must be newer");

        Bet memory bet = Bet({
            user: msg.sender,
            amount: amount,
            timestamp: _timestamp
        });
        
        require(_verifySignature(bet, signature), "Invalid signature");

        lastTimestamp[msg.sender] = _timestamp;
        token.safeTransferFrom(msg.sender, address(this), amount);
    
        Reels[3] memory resultReels = generateReels(_timestamp);
        uint256 rewardAmount = 0;

        uint rewardLen = rewards.length;

        for (uint i = 0; i < rewardLen; i++) {
            if (
                resultReels[0] == rewards[i].reels[0] &&
                resultReels[1] == rewards[i].reels[1] &&
                resultReels[2] == rewards[i].reels[2]
            ) {
                rewardAmount = amount * rewards[i].multiply;
                break;
            }
        }

        uint256 maxPayout = token.balanceOf(address(this));
        if (rewardAmount > maxPayout) {
            rewardAmount = 0;
            token.safeTransfer(msg.sender, amount);
            emit Result(msg.sender, resultReels, amount);
            return;
        }

        if (rewardAmount > 0) {
            token.safeTransfer(msg.sender, rewardAmount);
        }

        emit Result(msg.sender, resultReels, rewardAmount);
    }

    function generateReels(uint256 _timestamp) internal view returns (Reels[3] memory) {
        uint _randReel1 = _random(seedReels[0], _timestamp);
        uint _randReel2 = _random(seedReels[1], _timestamp);
        uint _randReel3 = _random(seedReels[2], _timestamp);

        return [
            Reels(_random(9, _randReel1)),
            Reels(_random(9, _randReel2)),
            Reels(_random(9, _randReel3))
        ];
    }

    function _random(uint256 mod, uint256 _seed) internal view returns(uint){
        uint rand = uint(            
            keccak256(abi.encodePacked(msg.sender, blockhash(block.number - 1), block.prevrandao, _seed))
        ) % mod;        
        return rand;        
    }

    function changeMinBetValue(uint256 _minBetValue) external onlyAdmin {
        require(_minBetValue > 0, "The minium bet value greater than 0");
        require(maxBetValue >= _minBetValue, "The maxium bet value greater than minium bet value");
        minBetValue = _minBetValue;
        emit ChangedMinBetValue(msg.sender, _minBetValue);
    } 

    function changeMaxBetValue(uint256 _maxBetValue) external onlyAdmin {
        require(_maxBetValue > 0, "The maxium bet value greater than 0");
        require(_maxBetValue >= minBetValue, "The maxium bet value greater than minium bet value");
        maxBetValue = _maxBetValue;
        emit ChangedMaxBetValue(msg.sender, _maxBetValue);
    }

    function requestChangeSeedReels(uint256 _seedReel1, uint256 _seedReel2, uint256 _seedReel3) external onlyAdmin {
        require(
        _seedReel1 != _seedReel2 && _seedReel2 != _seedReel3 && _seedReel1 != _seedReel3,
        "All three seed must be different"
        );
        require(_seedReel1 > 0 && _seedReel2 > 0 && _seedReel3 > 0, 'Seed reel must be greater than 0');
        pendingSeedReels = [_seedReel1, _seedReel2, _seedReel3];
        pendingSeedReelsChangeTime = block.timestamp;
        emit SeedReelsRequested(seedReels);
    }

    function confirmChangeSeedReels() external onlyAdmin {
        require(pendingSeedReels[0] > 0 && pendingSeedReels[1] > 0 && pendingSeedReels[2] > 0, "No pending seed reels change");
        require(pendingSeedReelsChangeTime > 0, "No pending seed reels change");
        require(block.timestamp >= pendingSeedReelsChangeTime + (3 days), "Must wait 3 days to confirm seed reels change");
        seedReels = pendingSeedReels;
        pendingSeedReels = [0,0,0];
        pendingSeedReelsChangeTime = 0;
        emit SeedReelsChanged(seedReels);
    }

    function cancelSeedReelsChange() external onlyAdmin {
        pendingSeedReels = [0,0,0]; 
        pendingGuardianChangeTime = 0;
        emit SeedReelsChangeCancelled();
    }
    
    function requestChangeGuardian(address newGuardian) external onlyGuardian() {
        require(newGuardian != address(0), "Invalid address");
        pendingGuardian = newGuardian;
        pendingGuardianChangeTime = block.timestamp;
        emit GuardianChangeRequested(newGuardian, block.timestamp);
    }

    function confirmChangeGuardian() external onlyGuardian {
        require(pendingGuardian != address(0), "No pending guardian change");
        require(pendingGuardianChangeTime > 0, "No pending guardian change");
        require(block.timestamp >= pendingGuardianChangeTime + (3 days), "Must wait 3 days to confirm admin change");
        guardian = pendingGuardian;
        pendingGuardian = address(0);
        pendingGuardianChangeTime = 0;
        emit GuardianChanged(guardian);
    }

    function cancelGuardianChange() external onlyGuardian {
        pendingGuardian = address(0); 
        pendingGuardianChangeTime = 0;
        emit GuardianChangeCancelled();
    }

    function requestAdminChange(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid address");
        pendingAdmin = newAdmin;
        pendingAdminChangeTime = block.timestamp;
        emit AdminChangeRequested(newAdmin, block.timestamp);
    }

    function confirmAdminChange() external onlyAdmin {
        require(pendingAdmin != address(0), "No pending admin change");
        require(pendingAdminChangeTime > 0, "No pending admin change");
        require(block.timestamp >= pendingAdminChangeTime + (3 days), "Must wait 3 days to confirm admin change");
        admin = pendingAdmin;
        pendingAdmin = address(0);
        pendingAdminChangeTime = 0;
        emit AdminChanged(admin);
    }

    function cancelAdminChange() external onlyGuardian {
        pendingAdmin = address(0); 
        pendingAdminChangeTime = 0;
        emit AdminChangeCancelled();
    }

    function requestWithdrawFund() external onlyAdmin {
        require(pendingWithdrawFundTime == 0, 'Withdrawal request is in progress');
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        pendingWithdrawFundTime = block.timestamp;
        emit WithdrawFundRequested(block.timestamp);
    }

    function cancelWithdrawFund() external onlyGuardian {
        pendingWithdrawFundTime = 0;
        emit WithdrawFundCancelled();
    }

    function withdrawFund(uint256 amount) external onlyAdmin nonReentrant notLocked {
        require(pendingWithdrawFundTime > 0, "No pending withdraw");
        require(block.timestamp >= pendingWithdrawFundTime + (7 days), "Must wait 7 days to withdraw funds");
        pendingWithdrawFundTime = 0;
        token.safeTransfer(admin, amount);      
        emit WithdrawFund(admin, amount);
    }

    function lockContract() external onlyGuardian {
        isLocked = true;
        emit ContractLocked(msg.sender);
    }

    function unlockContract() external onlyGuardian {
        isLocked = false;
        emit ContractUnlocked(msg.sender);
    }
}