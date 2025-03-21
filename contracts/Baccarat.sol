// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Baccarat is ReentrancyGuard {

    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    enum BetType {
        PLAYER,
        TIER,
        BANKER
    }

    struct Card {
        uint id;
        uint value;
    }

    struct Bet {
        uint256 amount;
        BetType betType;
    }

    struct Placed {
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

    mapping(address => uint256) public lastTimestamp;

    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant BET_TYPEHASH = keccak256(
        "Bet(address user,uint256 amount,uint256 timestamp)"
    );

    bytes32 private immutable DOMAIN_SEPARATOR;
    uint256 public immutable maxRewardMultiply;

    mapping(uint256 => uint256) private rewardMultiply;
    bool public isLocked = false;

    Card[13] cards;

    event Received(address from, uint256 amount);
    event Result(address user, Card[3] playerCards, Card[3] bankerCards, uint256 wonAmount, uint256 playerScore, uint256 bankerScore);
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

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("Baccarat")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        maxRewardMultiply = 4;
        rewardMultiply[uint256(BetType.PLAYER)] = 2;
        rewardMultiply[uint256(BetType.TIER)] = 4;
        rewardMultiply[uint256(BetType.BANKER)] = 2;

        cards[0] = Card(1, 1);
        cards[1] = Card(2, 2);
        cards[2] = Card(3, 3);
        cards[3] = Card(4, 4);
        cards[4] = Card(5, 5);
        cards[5] = Card(6, 6);
        cards[6] = Card(7, 7);
        cards[7] = Card(8, 8);
        cards[8] = Card(9, 9);
        cards[9] = Card(10, 0);
        cards[10] = Card(11, 0);
        cards[11] = Card(12, 0);
        cards[12] = Card(13, 0);
    }

    function _hashPlaced(Placed memory placed) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                BET_TYPEHASH,
                placed.user,
                placed.amount,
                placed.timestamp
            )
        );
    }

    function _toTypedDataHash(Placed memory placed) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _hashPlaced(placed))
        );
    }

    function _verifySignature(Placed memory placed, bytes calldata signature) internal view returns (bool) {
        bytes32 digest = _toTypedDataHash(placed);
        return ECDSA.recover(digest, signature) == admin;
    }


    function placeBet(Bet[] calldata bets, uint256 _amount, uint256 _timestamp, bytes calldata signature) payable external notLocked {
        require(_amount >= miniumBetValue, "The bet amount must be greater than the minimum required value");
        require(_amount <= maxiumBetValue, "Bet exceeds maximum limit");

        uint256 totalBetAmount = 0;
        for (uint i = 0; i < bets.length; i++) {
            totalBetAmount += bets[i].amount;
        }
        require(totalBetAmount == _amount, "Total bet amount must match sent value");

        uint256 maxPotentialPayout = _amount * maxRewardMultiply;
        require(token.balanceOf(address(this)) >= maxPotentialPayout, "Contract has insufficient funds");

        // Check timestamp
        require(block.timestamp >= _timestamp, "Timestamp from the future");
        require(block.timestamp <= _timestamp + 60, "Timestamp expired");
        require(_timestamp > lastTimestamp[msg.sender], "Timestamp must be newer");

        Placed memory placed = Placed({
            user: msg.sender,
            amount: _amount,
            timestamp: _timestamp
        });
        
        require(_verifySignature(placed, signature), "Invalid signature");

        lastTimestamp[msg.sender] = _timestamp;
        token.safeTransferFrom(msg.sender, address(this), _amount);

        (Card[3] memory firstCards, Card[3] memory secondCards) = _dealCards(_timestamp);

        (Card[3] memory playerCards, Card[3] memory bankerCards) = _assignmentCards(bets, firstCards, secondCards, _timestamp);

        (uint playerScore, uint bankerScore) = _calcCardScore(playerCards, bankerCards);


        uint256 rewardAmount = _calculateWinnings(bets, playerScore, bankerScore);

        uint256 maxPayout = token.balanceOf(address(this));
        if (rewardAmount > maxPayout) {
            rewardAmount = 0;
            token.safeTransfer(msg.sender, _amount);
            emit Result(msg.sender, playerCards, bankerCards, rewardAmount, playerScore, bankerScore);
            return;
        }

        if (rewardAmount > 0) {
            token.safeTransfer(msg.sender, rewardAmount);
        }
        emit Result(msg.sender, playerCards, bankerCards, rewardAmount, playerScore, bankerScore);
    }

    function _calcReward(BetType _betType, uint256 _amount) internal view returns (uint256) {
        uint256 reward = _amount * rewardMultiply[uint256(_betType)];
        return reward;
    }

    function _calcCardScore(Card[3] memory firstCards, Card[3] memory secondCards) internal pure returns (uint, uint) {
        uint _firstCardScore = (firstCards[0].value + firstCards[1].value) % 10;
        uint _secondCardScore = (secondCards[0].value + secondCards[1].value) % 10;

        if (_firstCardScore < 8 && _secondCardScore < 8) {
            if (_firstCardScore < 6) _firstCardScore = (_firstCardScore + firstCards[2].value) % 10;
            if (_secondCardScore < 6) _secondCardScore = (_secondCardScore + secondCards[2].value) % 10;
        }
        return (_firstCardScore, _secondCardScore);
    }

    function _assignmentCards(Bet[] calldata bets, Card[3] memory firstCards, Card[3] memory secondCards, uint256 _timestamp) internal view returns (Card[3] memory, Card[3] memory) {
        Card[3] memory playerCards;
        Card[3] memory bankerCards;
        
        uint betsLen = bets.length;
        uint256 randomChance = _random(100, _timestamp);
        bool w = randomChance < winProbability;

        (uint firstCardScore, uint secondCardScore) = _calcCardScore(firstCards, secondCards);

        Bet memory bet;
        if (w) {
            
            if (betsLen == 1) {
                bet = bets[0];
            } else {
                uint rand = _random(betsLen, _timestamp);
                bet = bets[rand];
            }
        } else {
            if (betsLen < 3) {  
                bool[3] memory betTypes;
                   // Đánh dấu các betType có trong bets
                for (uint i = 0; i < betsLen; i++) {
                    betTypes[uint256(bets[i].betType)] = true;
                }

                for (uint i = 0; i < 3; i++) {
                    if (betTypes[i] == false) {
                        if (uint256(BetType.PLAYER) == i) {
                            bet = Bet(0, BetType.PLAYER);
                            break;
                        } else if (uint256(BetType.BANKER) == i) {
                            bet = Bet(0, BetType.BANKER);
                            break;
                        } else {
                            bet = Bet(0, BetType.TIER);
                        }
                    }
                }
            } else {
                uint256 lowestReward;
                for (uint256 i = 0; i < bets.length; i++) {
                    uint256 reward = bets[i].amount * rewardMultiply[uint256(bets[i].betType)];
                    if (reward < lowestReward) {
                        lowestReward = reward;
                        bet = bets[i];
                    }
                }
            }
        }
        if (bet.betType == BetType.PLAYER) {
            playerCards = firstCardScore > secondCardScore ? firstCards : secondCards;
            bankerCards = firstCardScore > secondCardScore ? secondCards : firstCards;
        } else if (bet.betType == BetType.BANKER) {
            bankerCards = firstCardScore > secondCardScore ? firstCards : secondCards;
            playerCards = firstCardScore > secondCardScore ? secondCards : firstCards;
        } else {
            playerCards = firstCards;
            bankerCards = firstCards;
        }
        return (playerCards, bankerCards);
    }

    function _dealCards(uint256 _timestamp) internal view returns (Card[3] memory firstCards, Card[3] memory secondCards) {
        Card[3] memory _firstCards;
        Card[3] memory _secondCards;

        Card[6] memory _listCards;

        for (uint i = 0; i < 6; i++) {
            uint _rand = _random(1000, i + 2);
            _listCards[i] = cards[_random(13, _timestamp + _rand)];
        }

        _firstCards[0] = _listCards[0];
        _firstCards[1] = _listCards[1];
        _firstCards[2] = _listCards[2];
        _secondCards[0] = _listCards[3];
        _secondCards[1] = _listCards[4];
        _secondCards[2] = _listCards[5];

        return (_firstCards, _secondCards);
    }

    function _calculateWinnings(Bet[] memory bets, uint256 playerScore, uint256 bankerScore) internal view returns (uint256) {
        uint256 totalWin = 0;
        for (uint i = 0; i < bets.length; i++) {
            if (bets[i].betType == BetType.PLAYER && playerScore > bankerScore) {
                totalWin += bets[i].amount * rewardMultiply[uint256(BetType.PLAYER)];
            } else if (bets[i].betType == BetType.BANKER && bankerScore > playerScore) {
                totalWin += bets[i].amount * rewardMultiply[uint256(BetType.BANKER)];
            } else if (bets[i].betType == BetType.TIER && playerScore == bankerScore) {
                totalWin += bets[i].amount * rewardMultiply[uint256(BetType.TIER)];
            }
        }
        return totalWin;
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