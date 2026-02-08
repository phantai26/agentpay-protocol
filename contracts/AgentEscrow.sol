// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AgentEscrow
 * @dev Smart contract escrow with AI-powered verification for autonomous agents
 * @notice Part of AgentPay Protocol - OpenClaw USDC Hackathon
 */
contract AgentEscrow is ReentrancyGuard, Ownable {
    
    // ============ State Variables ============
    
    IERC20 public immutable USDC;
    address public aiVerifier; // Trusted AI oracle address
    address public feeCollector;
    
    uint256 public escrowCounter;
    uint256 public constant MIN_ESCROW_AMOUNT = 1e6; // 1 USDC (6 decimals)
    uint256 public constant MAX_ESCROW_AMOUNT = 1000000e6; // 1M USDC
    uint256 public constant DISPUTE_WINDOW = 7 days;
    uint256 public constant MIN_DEADLINE = 1 hours;
    uint256 public constant MAX_DEADLINE = 90 days;
    
    // ============ Structs ============
    
    enum EscrowState {
        Created,
        WorkSubmitted,
        Verified,
        Disputed,
        Released,
        Refunded,
        Cancelled
    }
    
    struct Escrow {
        uint256 id;
        address employer;
        address worker;
        uint256 amount;
        uint256 fee;
        string taskDescription;
        string verificationCriteria; // JSON format for AI
        bytes32 workHash;
        string workUrl; // IPFS/Arweave link
        EscrowState state;
        uint256 createdAt;
        uint256 deadline;
        uint256 submittedAt;
        bool aiVerified;
        string verificationReason;
        uint256 verificationScore; // 0-100
    }
    
    struct DisputeInfo {
        bool active;
        uint256 raisedAt;
        address raisedBy;
        string reason;
        uint256 votesForEmployer;
        uint256 votesForWorker;
        mapping(address => bool) hasVoted;
    }
    
    // ============ Mappings ============
    
    mapping(uint256 => Escrow) public escrows;
    mapping(uint256 => DisputeInfo) public disputes;
    mapping(address => uint256[]) public employerEscrows;
    mapping(address => uint256[]) public workerEscrows;
    mapping(address => uint256) public reputationScore; // 0-1000
    mapping(address => uint256) public totalEscrowsCompleted;
    
    // ============ Events ============
    
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed employer,
        address indexed worker,
        uint256 amount,
        uint256 fee,
        uint256 deadline
    );
    
    event WorkSubmitted(
        uint256 indexed escrowId,
        address indexed worker,
        bytes32 workHash,
        string workUrl
    );
    
    event WorkVerified(
        uint256 indexed escrowId,
        bool passed,
        uint256 score,
        string reason
    );
    
    event PaymentReleased(
        uint256 indexed escrowId,
        address indexed worker,
        uint256 amount,
        uint256 fee
    );
    
    event EscrowRefunded(
        uint256 indexed escrowId,
        address indexed employer,
        uint256 amount
    );
    
    event DisputeRaised(
        uint256 indexed escrowId,
        address indexed raisedBy,
        string reason
    );
    
    event DisputeResolved(
        uint256 indexed escrowId,
        address winner,
        uint256 amount
    );
    
    event ReputationUpdated(
        address indexed agent,
        uint256 newScore
    );
    
    // ============ Modifiers ============
    
    modifier onlyEmployer(uint256 _escrowId) {
        require(escrows[_escrowId].employer == msg.sender, "Not employer");
        _;
    }
    
    modifier onlyWorker(uint256 _escrowId) {
        require(escrows[_escrowId].worker == msg.sender, "Not worker");
        _;
    }
    
    modifier onlyAIVerifier() {
        require(msg.sender == aiVerifier, "Not AI verifier");
        _;
    }
    
    modifier escrowExists(uint256 _escrowId) {
        require(_escrowId < escrowCounter, "Escrow does not exist");
        _;
    }
    
    modifier inState(uint256 _escrowId, EscrowState _state) {
        require(escrows[_escrowId].state == _state, "Invalid state");
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        address _usdc,
        address _aiVerifier,
        address _feeCollector
    ) Ownable(msg.sender) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_aiVerifier != address(0), "Invalid verifier");
        require(_feeCollector != address(0), "Invalid fee collector");
        
        USDC = IERC20(_usdc);
        aiVerifier = _aiVerifier;
        feeCollector = _feeCollector;
    }
    
    // ============ Main Functions ============
    
    /**
     * @dev Create a new escrow
     * @param _worker Address of the worker agent
     * @param _amount Amount of USDC to escrow (6 decimals)
     * @param _fee Protocol fee in USDC
     * @param _taskDescription Human-readable task description
     * @param _criteria JSON-formatted verification criteria for AI
     * @param _deadline Unix timestamp deadline
     */
    function createEscrow(
        address _worker,
        uint256 _amount,
        uint256 _fee,
        string memory _taskDescription,
        string memory _criteria,
        uint256 _deadline
    ) external nonReentrant returns (uint256) {
        require(_worker != address(0), "Invalid worker address");
        require(_worker != msg.sender, "Cannot hire yourself");
        require(_amount >= MIN_ESCROW_AMOUNT, "Amount too low");
        require(_amount <= MAX_ESCROW_AMOUNT, "Amount too high");
        require(_deadline > block.timestamp + MIN_DEADLINE, "Deadline too soon");
        require(_deadline < block.timestamp + MAX_DEADLINE, "Deadline too far");
        require(bytes(_taskDescription).length > 0, "Empty task description");
        require(bytes(_criteria).length > 0, "Empty criteria");
        
        uint256 totalAmount = _amount + _fee;
        require(
            USDC.transferFrom(msg.sender, address(this), totalAmount),
            "Transfer failed"
        );
        
        uint256 escrowId = escrowCounter++;
        
        Escrow storage newEscrow = escrows[escrowId];
        newEscrow.id = escrowId;
        newEscrow.employer = msg.sender;
        newEscrow.worker = _worker;
        newEscrow.amount = _amount;
        newEscrow.fee = _fee;
        newEscrow.taskDescription = _taskDescription;
        newEscrow.verificationCriteria = _criteria;
        newEscrow.state = EscrowState.Created;
        newEscrow.createdAt = block.timestamp;
        newEscrow.deadline = _deadline;
        
        employerEscrows[msg.sender].push(escrowId);
        workerEscrows[_worker].push(escrowId);
        
        emit EscrowCreated(
            escrowId,
            msg.sender,
            _worker,
            _amount,
            _fee,
            _deadline
        );
        
        return escrowId;
    }
    
    /**
     * @dev Worker submits completed work
     * @param _escrowId Escrow ID
     * @param _workHash Hash of the work (for verification)
     * @param _workUrl URL to access the work (IPFS/Arweave)
     */
    function submitWork(
        uint256 _escrowId,
        bytes32 _workHash,
        string memory _workUrl
    ) external 
        escrowExists(_escrowId)
        onlyWorker(_escrowId)
        inState(_escrowId, EscrowState.Created)
        nonReentrant 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(block.timestamp <= escrow.deadline, "Deadline passed");
        require(_workHash != bytes32(0), "Invalid work hash");
        require(bytes(_workUrl).length > 0, "Empty work URL");
        
        escrow.workHash = _workHash;
        escrow.workUrl = _workUrl;
        escrow.submittedAt = block.timestamp;
        escrow.state = EscrowState.WorkSubmitted;
        
        emit WorkSubmitted(_escrowId, msg.sender, _workHash, _workUrl);
    }
    
    /**
     * @dev AI verifier checks and verifies work
     * @param _escrowId Escrow ID
     * @param _passed Whether work passed verification
     * @param _score Verification score (0-100)
     * @param _reason Explanation from AI
     */
    function verifyWork(
        uint256 _escrowId,
        bool _passed,
        uint256 _score,
        string memory _reason
    ) external 
        escrowExists(_escrowId)
        onlyAIVerifier
        inState(_escrowId, EscrowState.WorkSubmitted)
        nonReentrant 
    {
        require(_score <= 100, "Invalid score");
        
        Escrow storage escrow = escrows[_escrowId];
        escrow.aiVerified = true;
        escrow.verificationScore = _score;
        escrow.verificationReason = _reason;
        
        if (_passed) {
            escrow.state = EscrowState.Verified;
            emit WorkVerified(_escrowId, true, _score, _reason);
            
            // Auto-release payment if verified
            _releasePayment(_escrowId);
        } else {
            escrow.state = EscrowState.Created; // Back to created state
            emit WorkVerified(_escrowId, false, _score, _reason);
        }
    }
    
    /**
     * @dev Release payment to worker (internal)
     */
    function _releasePayment(uint256 _escrowId) internal {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.state == EscrowState.Verified, "Not verified");
        
        escrow.state = EscrowState.Released;
        
        // Transfer amount to worker
        require(
            USDC.transfer(escrow.worker, escrow.amount),
            "Payment transfer failed"
        );
        
        // Transfer fee to collector
        if (escrow.fee > 0) {
            require(
                USDC.transfer(feeCollector, escrow.fee),
                "Fee transfer failed"
            );
        }
        
        // Update reputation
        _updateReputation(escrow.worker, true);
        _updateReputation(escrow.employer, true);
        
        totalEscrowsCompleted[escrow.worker]++;
        
        emit PaymentReleased(
            _escrowId,
            escrow.worker,
            escrow.amount,
            escrow.fee
        );
    }
    
    /**
     * @dev Employer manually releases payment (if trusts worker)
     */
    function manualRelease(uint256 _escrowId) 
        external 
        escrowExists(_escrowId)
        onlyEmployer(_escrowId)
        nonReentrant 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(
            escrow.state == EscrowState.Created || 
            escrow.state == EscrowState.WorkSubmitted,
            "Invalid state"
        );
        
        escrow.state = EscrowState.Verified;
        _releasePayment(_escrowId);
    }
    
    /**
     * @dev Refund to employer if deadline passed and no work submitted
     */
    function refund(uint256 _escrowId) 
        external 
        escrowExists(_escrowId)
        nonReentrant 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(
            escrow.state == EscrowState.Created,
            "Invalid state"
        );
        require(
            block.timestamp > escrow.deadline,
            "Deadline not passed"
        );
        require(
            msg.sender == escrow.employer || msg.sender == owner(),
            "Not authorized"
        );
        
        escrow.state = EscrowState.Refunded;
        
        uint256 refundAmount = escrow.amount + escrow.fee;
        require(
            USDC.transfer(escrow.employer, refundAmount),
            "Refund failed"
        );
        
        // Update reputation - negative for worker (didn't complete)
        _updateReputation(escrow.worker, false);
        
        emit EscrowRefunded(_escrowId, escrow.employer, refundAmount);
    }
    
    /**
     * @dev Cancel escrow before work submitted (only employer)
     */
    function cancelEscrow(uint256 _escrowId) 
        external 
        escrowExists(_escrowId)
        onlyEmployer(_escrowId)
        inState(_escrowId, EscrowState.Created)
        nonReentrant 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(escrow.submittedAt == 0, "Work already submitted");
        
        escrow.state = EscrowState.Cancelled;
        
        uint256 refundAmount = escrow.amount + escrow.fee;
        require(
            USDC.transfer(escrow.employer, refundAmount),
            "Refund failed"
        );
        
        emit EscrowRefunded(_escrowId, escrow.employer, refundAmount);
    }
    
    /**
     * @dev Raise a dispute
     */
    function raiseDispute(
        uint256 _escrowId,
        string memory _reason
    ) external 
        escrowExists(_escrowId)
        nonReentrant 
    {
        Escrow storage escrow = escrows[_escrowId];
        require(
            msg.sender == escrow.employer || msg.sender == escrow.worker,
            "Not authorized"
        );
        require(
            escrow.state == EscrowState.WorkSubmitted ||
            escrow.state == EscrowState.Created,
            "Invalid state"
        );
        require(!disputes[_escrowId].active, "Dispute already active");
        
        escrow.state = EscrowState.Disputed;
        
        DisputeInfo storage dispute = disputes[_escrowId];
        dispute.active = true;
        dispute.raisedAt = block.timestamp;
        dispute.raisedBy = msg.sender;
        dispute.reason = _reason;
        
        emit DisputeRaised(_escrowId, msg.sender, _reason);
    }
    
    /**
     * @dev Vote on dispute (community governance)
     */
    function voteOnDispute(
        uint256 _escrowId,
        bool _forEmployer
    ) external escrowExists(_escrowId) {
        DisputeInfo storage dispute = disputes[_escrowId];
        require(dispute.active, "No active dispute");
        require(!dispute.hasVoted[msg.sender], "Already voted");
        require(
            msg.sender != escrows[_escrowId].employer &&
            msg.sender != escrows[_escrowId].worker,
            "Cannot vote on own dispute"
        );
        
        dispute.hasVoted[msg.sender] = true;
        
        if (_forEmployer) {
            dispute.votesForEmployer++;
        } else {
            dispute.votesForWorker++;
        }
    }
    
    /**
     * @dev Resolve dispute after voting period
     */
    function resolveDispute(uint256 _escrowId) 
        external 
        escrowExists(_escrowId)
        nonReentrant 
    {
        DisputeInfo storage dispute = disputes[_escrowId];
        require(dispute.active, "No active dispute");
        require(
            block.timestamp > dispute.raisedAt + DISPUTE_WINDOW,
            "Voting period not ended"
        );
        
        Escrow storage escrow = escrows[_escrowId];
        dispute.active = false;
        
        address winner;
        uint256 amount = escrow.amount + escrow.fee;
        
        if (dispute.votesForEmployer > dispute.votesForWorker) {
            // Employer wins - refund
            winner = escrow.employer;
            escrow.state = EscrowState.Refunded;
            require(USDC.transfer(escrow.employer, amount), "Refund failed");
        } else {
            // Worker wins - release payment
            winner = escrow.worker;
            escrow.state = EscrowState.Released;
            require(USDC.transfer(escrow.worker, escrow.amount), "Payment failed");
            if (escrow.fee > 0) {
                require(USDC.transfer(feeCollector, escrow.fee), "Fee failed");
            }
        }
        
        emit DisputeResolved(_escrowId, winner, amount);
    }
    
    /**
     * @dev Update reputation score
     */
    function _updateReputation(address _agent, bool _positive) internal {
        uint256 currentScore = reputationScore[_agent];
        
        if (_positive) {
            // Increase by 10, max 1000
            reputationScore[_agent] = currentScore + 10 > 1000 
                ? 1000 
                : currentScore + 10;
        } else {
            // Decrease by 20
            reputationScore[_agent] = currentScore > 20 
                ? currentScore - 20 
                : 0;
        }
        
        emit ReputationUpdated(_agent, reputationScore[_agent]);
    }
    
    // ============ View Functions ============
    
    function getEscrow(uint256 _escrowId) 
        external 
        view 
        returns (Escrow memory) 
    {
        return escrows[_escrowId];
    }
    
    function getEmployerEscrows(address _employer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return employerEscrows[_employer];
    }
    
    function getWorkerEscrows(address _worker) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return workerEscrows[_worker];
    }
    
    function getReputation(address _agent) 
        external 
        view 
        returns (uint256) 
    {
        return reputationScore[_agent];
    }
    
    function getDisputeInfo(uint256 _escrowId) 
        external 
        view 
        returns (
            bool active,
            uint256 raisedAt,
            address raisedBy,
            string memory reason,
            uint256 votesForEmployer,
            uint256 votesForWorker
        ) 
    {
        DisputeInfo storage dispute = disputes[_escrowId];
        return (
            dispute.active,
            dispute.raisedAt,
            dispute.raisedBy,
            dispute.reason,
            dispute.votesForEmployer,
            dispute.votesForWorker
        );
    }
    
    // ============ Admin Functions ============
    
    function setAIVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0), "Invalid address");
        aiVerifier = _newVerifier;
    }
    
    function setFeeCollector(address _newCollector) external onlyOwner {
        require(_newCollector != address(0), "Invalid address");
        feeCollector = _newCollector;
    }
    
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = USDC.balanceOf(address(this));
        require(USDC.transfer(owner(), balance), "Withdraw failed");
    }
}
