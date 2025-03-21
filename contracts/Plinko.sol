// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// import "hardhat/console.sol";

contract Plinko is ReentrancyGuard {

    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    struct Bet {
        address user;
        uint256 amount;
        uint256 timestamp;
    }

    IERC20 public immutable token;

    uint public winProbability;
    address public admin;
    address public guardian;
    address public pendingAdmin;
    uint256 public pendingAdminChangeTime;

    address public pendingGuardian;
    uint256 public pendingGuardianChangeTime;
    uint256 public pendingWithdrawFundTime;

    uint public pendingWinProbability;
    uint256 public pendingWinProbabilityChangeTime;

    uint256 public maxiumBetValue;
    uint256 public miniumBetValue;
    uint256 public maxiumBetPerBall;
    uint256 public maxiumPlacedBall;

    uint256[] public rewards;

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

    event WithdrawFund(address to, uint256 amount);
    event WithdrawFundRequested(uint256 requestTime);
    event Result(address user, uint[] balls, uint256 amount);
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
    event WinProbabilityRequested(uint winProbability);
    event WinProbabilityChangeCancelled();
    event WinProbabilityChanged(uint winProbability);

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

    constructor(address _guardian, address _admin, address _token, uint256 _minBetValue, uint256 _maxBetValue) payable {       
        require(_maxBetValue > 0, "The maximum bet value must be greater than 0");
        require(_minBetValue > 0, "The minimum bet value must be greater than 0");
        require(_maxBetValue >= _minBetValue, "The maximum bet value must be greater than the minimum bet value");

        token = IERC20(_token);
        admin = _admin;
        guardian = _guardian;        
        winProbability = 10;        
        maxiumBetValue = _maxBetValue;
        miniumBetValue = _minBetValue;

        uint8 tk_decimals = IERC20Metadata(address(token)).decimals();
        maxiumBetPerBall = 1 * 10 ** tk_decimals;
        maxiumPlacedBall = 5;

        rewards = [0, 10, 11, 21, 56];
        maxRewardMultiply = 56;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("Plinko")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
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

    function placeBet(uint256 _numBall, uint256 _amount, uint256 _timestamp, bytes calldata signature) payable external notLocked {
        require(_amount >= miniumBetValue, "The bet amount must be greater than the minimum required value");
        require(_amount <= maxiumBetValue, "Bet exceeds maximum limit");
        require(_numBall > 0, "The number of balls must be greater than 0");
        require(_numBall <= maxiumPlacedBall, "The maximum allowed number of balls has been reached");

        uint256 betPerBall = _amount / _numBall;

        require(betPerBall <= maxiumBetPerBall, "The bet amount per ball cannot exceed the allowed limit");

        uint256 maxPotentialPayout = (_amount * maxRewardMultiply) / 10;
        require(token.balanceOf(address(this)) >= maxPotentialPayout, "Contract has insufficient funds");
        
        // Check timestamp
        require(block.timestamp >= _timestamp, "Timestamp from the future");
        require(block.timestamp <= _timestamp + 60, "Timestamp expired");
        require(_timestamp > lastTimestamp[msg.sender], "Timestamp must be newer");

        Bet memory bet = Bet({
            user: msg.sender,
            amount: _amount,
            timestamp: _timestamp
        });

        require(_verifySignature(bet, signature), "Invalid signature");

        lastTimestamp[msg.sender] = _timestamp;
        token.safeTransferFrom(msg.sender, address(this), _amount);

        uint[] memory balls = generateBalls(_numBall, _timestamp);
        
        uint256 rewardAmount = _calculateWinnings(betPerBall, balls);

        uint256 maxPayout = token.balanceOf(address(this));
        if (rewardAmount > maxPayout) {
            rewardAmount = 0;
            token.safeTransfer(msg.sender, _amount);
            emit Result(msg.sender, balls, rewardAmount);
            return;
        }

        if (rewardAmount > 0) {
            token.safeTransfer(msg.sender, rewardAmount);
        }

        emit Result(msg.sender, balls, rewardAmount);
    }

    function _calculateWinnings(uint256 ballBet, uint[] memory _balls) internal view returns(uint256) {
        uint256 reward = 0;
        uint ballsLen = _balls.length;
        for (uint i = 0; i < ballsLen; i++) {
            reward = reward + ((ballBet * rewards[_balls[i]]) / 10);
        }
        return reward;
    }

    function generateBalls(uint256 _numBall, uint256 _timestamp) internal view returns(uint[] memory) { 
        uint[] memory balls = new uint[](_numBall);

        uint256[3] memory _wList = [uint256(4), uint256(2), uint256(3)];
        uint256[2] memory _lList = [uint256(1), uint256(0)];

        for (uint i = 0; i < _numBall; i++) {
            uint _rand = _random(1000, i + 2);
            uint256 randomChance = _random(100, _timestamp + _rand);
            bool w = randomChance < winProbability;
            if (w) {
                balls[i] = _wList[_random(3, _timestamp + _rand)];
            } else {
                balls[i] = _lList[_random(2, _timestamp + _rand)];
            }
        }
        
        return balls;
    }

    function _random(uint256 mod, uint256 _seed) internal view returns(uint){
        uint rand = uint(            
            keccak256(abi.encodePacked(msg.sender, blockhash(block.number - 1), block.prevrandao, _seed))
        ) % mod;        
        return rand;        
    }

    function requestChangeWinProbability(uint _winProbability) external onlyAdmin {
        require(_winProbability < 50, "Invalid winProbability");
        pendingWinProbability = _winProbability;
        pendingWinProbabilityChangeTime = block.timestamp;
        emit WinProbabilityRequested(_winProbability);
    }

    function confirmChangeWinProbability() external onlyAdmin {
        require(pendingWinProbability > 0, "No pending win probability change");
        require(pendingWinProbabilityChangeTime > 0, "No pending win probability change");
        require(block.timestamp >= pendingWinProbabilityChangeTime + (3 days), "Must wait 3 days to confirm seed reels change");
        winProbability = pendingWinProbability;
        pendingWinProbability = 0;
        pendingWinProbabilityChangeTime = 0;
        emit WinProbabilityChanged(winProbability);
    }

    function cancelWinProbabilityChange() external onlyAdmin {
        pendingWinProbability = 0; 
        pendingWinProbabilityChangeTime = 0;
        emit WinProbabilityChangeCancelled();
    }

    function changeMinBetValue(uint256 _minBetValue) external onlyAdmin {
        require(_minBetValue > 0, "The minium bet value greater than 0");
        require(maxiumBetValue > _minBetValue, "The maxium bet value greater than minium bet value");
        miniumBetValue = _minBetValue;
        emit ChangedMinBetValue(msg.sender, _minBetValue);
    } 

    function changeMaxBetValue(uint256 _maxBetValue) external onlyAdmin {
        require(_maxBetValue > 0, "The maxium bet value greater than 0");
        require(_maxBetValue > miniumBetValue, "The maxium bet value greater than minium bet value");
        maxiumBetValue = _maxBetValue;
        emit ChangedMaxBetValue(msg.sender, _maxBetValue);
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