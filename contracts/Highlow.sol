// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Highlow is ReentrancyGuard {

    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    enum BetType {
        HIGH,
        LOW
    }

    struct Card {
        uint id;
        uint value;
    }

    struct Player {
        uint ssid;
        Card refferalCard;
    }

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

    bool public isLocked = false;

    mapping(address => uint256) public lastTimestamp;

    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 private constant BET_TYPEHASH = keccak256(
        "Bet(address user,uint256 amount,uint256 timestamp)"
    );

    bytes32 private immutable DOMAIN_SEPARATOR;
    uint256 public immutable rewardMultiply;

    Card[13] cards;

    mapping(address => Player) players;

    event StartGame(uint ssid, Card card);
    event WithdrawFund(address to, uint256 amount);
    event WithdrawFundRequested(uint256 requestTime);
    event Result(address user, uint ssid, Card betCard, Card nextCard, uint256 amount);
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

        rewardMultiply = 2;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("Highlow")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
        
        cards[0] = Card(1, 11);
        cards[1] = Card(2, 2);
        cards[2] = Card(3, 3);
        cards[3] = Card(4, 4);
        cards[4] = Card(5, 5);
        cards[5] = Card(6, 6);
        cards[6] = Card(7, 7);
        cards[7] = Card(8, 8);
        cards[8] = Card(9, 9);
        cards[9] = Card(10, 10);
        cards[10] = Card(11, 10);
        cards[11] = Card(12, 10);
        cards[12] = Card(13, 10);
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

    function startGame(uint256 _timestamp, bytes calldata signature) external notLocked {
        // Check timestamp
        require(block.timestamp >= _timestamp, "Timestamp from the future");
        require(block.timestamp <= _timestamp + 60, "Timestamp expired");
        require(_timestamp > lastTimestamp[msg.sender], "Timestamp must be newer");

        uint8 decimals = IERC20Metadata(address(token)).decimals();

        Bet memory bet = Bet({
            user: msg.sender,
            amount: 1 * 10 ** decimals,
            timestamp: _timestamp
        });
        
        require(_verifySignature(bet, signature), "Invalid signature");

        lastTimestamp[msg.sender] = _timestamp;

        uint ssid = _random(100000, _timestamp);

        Card memory _refferalCard = _randomRefferalCard(_timestamp);

        players[msg.sender] = Player(ssid, _refferalCard);

        emit StartGame(ssid, _refferalCard);
    }

    function placeBet(uint _ssid, BetType _betType, uint256 _amount, uint256 _timestamp, bytes calldata signature) payable external notLocked {
        require(_amount >= miniumBetValue, "The bet amount must be greater than the minimum required value");
        require(_amount <= maxiumBetValue, "Bet exceeds maximum limit");
      
        require(_ssid == players[msg.sender].ssid, "The session is not match");

        uint256 maxPotentialPayout = _amount * rewardMultiply;
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

        Card memory _refferalCard = players[msg.sender].refferalCard;
        Card memory _betCard = generateBetCard(_refferalCard, _betType, _timestamp);
        Card memory _nextCard = _randomRefferalCard(_timestamp);
        uint _nextSsid = _random(100000, _timestamp);
        uint256 rewardAmount = 0;

        if ((_betType == BetType.HIGH && _refferalCard.value > _betCard.value) || (_betType == BetType.LOW && _refferalCard.value < _betCard.value)) {
            rewardAmount = _amount * rewardMultiply;
        }

        uint256 maxPayout = token.balanceOf(address(this));
        if (rewardAmount > maxPayout) {
            rewardAmount = 0;
            token.safeTransfer(msg.sender, _amount);
            emit Result(msg.sender, _nextSsid, _betCard, _nextCard, rewardAmount);
            players[msg.sender] = Player(_nextSsid, _nextCard);
            return;
        }

        if (rewardAmount > 0) {
            token.safeTransfer(msg.sender, rewardAmount);
        }

        emit Result(msg.sender, _nextSsid, _betCard, _nextCard, rewardAmount);
        players[msg.sender] = Player(_nextSsid, _nextCard);
    }

    function generateBetCard(Card memory _refferalCard, BetType _betType, uint256 _timestamp) internal view returns(Card memory) {
        Card memory _betCard;

        uint256 randomChance = _random(100, _timestamp);
        bool w = randomChance < winProbability;

        uint count = 0;
        uint cardsLen = cards.length;
        Card[] memory _betCards = new Card[](cardsLen);

        if (w) {
            if (_betType == BetType.HIGH) {                
                for (uint i = 0; i < cardsLen; i++) {
                    if (cards[i].value < _refferalCard.value) {
                        _betCards[count] = cards[i];
                        count++;
                    }
                }
            } else {
                for (uint i = 0; i < cardsLen; i++) {
                    if (cards[i].value > _refferalCard.value) {
                        _betCards[count] = cards[i];
                        count++;
                    }
                }
            }
        } else {
            if (_betType == BetType.HIGH) {                
                for (uint i = 0; i < cardsLen; i++) {
                    if (cards[i].value >= _refferalCard.value) {
                        _betCards[count] = cards[i];
                        count++;
                    }
                }
            } else {
                for (uint i = 0; i < cardsLen; i++) {
                    if (cards[i].value <= _refferalCard.value) {
                        _betCards[count] = cards[i];
                        count++;
                    }
                }
            }
        }
         // set random bet card
        if (count == 0) {
            _betCard = cards[_random(cards.length, _timestamp)]; 
        } else if (count == 1) {
            _betCard = _betCards[0];
        } else {
            _betCard = _betCards[_random(count, _timestamp)];
        }

        return _betCard;
    }

    function _randomRefferalCard(uint256 _timestamp) internal view returns(Card memory){
        Card memory _refferalCard = cards[_random(4, _timestamp) + 4]; // only random from 4 -> 8
        return _refferalCard;
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