// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title FeeManager
 * @dev Dynamic fee calculation for AgentPay Protocol
 */
contract FeeManager is Ownable {
    
    // Fee parameters (in basis points, 1 bp = 0.01%)
    uint256 public baseFee = 100; // 1%
    uint256 public minFee = 50;   // 0.5%
    uint256 public maxFee = 300;  // 3%
    
    // Tier thresholds (in USDC, 6 decimals)
    uint256 public tier1Threshold = 1000e6;  // $1,000
    uint256 public tier2Threshold = 10000e6; // $10,000
    uint256 public tier3Threshold = 50000e6; // $50,000
    
    // Multipliers (in basis points)
    uint256 public highComplexityMultiplier = 150; // 1.5x
    uint256 public mediumComplexityMultiplier = 100; // 1x
    uint256 public lowComplexityMultiplier = 75; // 0.75x
    
    uint256 public highReputationDiscount = 90; // 10% off
    uint256 public mediumReputationDiscount = 95; // 5% off
    
    // Cross-chain fee
    uint256 public crossChainFee = 50; // 0.5%
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Calculate fee for an escrow
     * @param amount Escrow amount in USDC (6 decimals)
     * @param complexity 0=low, 1=medium, 2=high
     * @param workerReputation Reputation score (0-1000)
     * @param isCrossChain Whether it's cross-chain
     * @return fee Fee amount in USDC
     */
    function calculateFee(
        uint256 amount,
        uint256 complexity,
        uint256 workerReputation,
        bool isCrossChain
    ) external view returns (uint256) {
        require(amount > 0, "Invalid amount");
        require(complexity <= 2, "Invalid complexity");
        
        // Start with base fee
        uint256 fee = (amount * baseFee) / 10000;
        
        // Apply complexity multiplier
        if (complexity == 2) {
            fee = (fee * highComplexityMultiplier) / 100;
        } else if (complexity == 0) {
            fee = (fee * lowComplexityMultiplier) / 100;
        }
        // Medium complexity stays at 1x
        
        // Apply volume discount
        if (amount >= tier3Threshold) {
            fee = (fee * 70) / 100; // 30% discount
        } else if (amount >= tier2Threshold) {
            fee = (fee * 80) / 100; // 20% discount
        } else if (amount >= tier1Threshold) {
            fee = (fee * 90) / 100; // 10% discount
        }
        
        // Apply reputation discount
        if (workerReputation >= 800) {
            fee = (fee * highReputationDiscount) / 100;
        } else if (workerReputation >= 500) {
            fee = (fee * mediumReputationDiscount) / 100;
        }
        
        // Add cross-chain fee
        if (isCrossChain) {
            fee += (amount * crossChainFee) / 10000;
        }
        
        // Ensure within bounds
        uint256 minFeeAmount = (amount * minFee) / 10000;
        uint256 maxFeeAmount = (amount * maxFee) / 10000;
        
        if (fee < minFeeAmount) {
            fee = minFeeAmount;
        } else if (fee > maxFeeAmount) {
            fee = maxFeeAmount;
        }
        
        return fee;
    }
    
    /**
     * @dev Get fee percentage for display (in basis points)
     */
    function getFeePercentage(
        uint256 amount,
        uint256 complexity,
        uint256 workerReputation,
        bool isCrossChain
    ) external view returns (uint256) {
        uint256 fee = this.calculateFee(
            amount,
            complexity,
            workerReputation,
            isCrossChain
        );
        return (fee * 10000) / amount; // Return in basis points
    }
    
    // ============ Admin Functions ============
    
    function setBaseFee(uint256 _baseFee) external onlyOwner {
        require(_baseFee >= minFee && _baseFee <= maxFee, "Invalid base fee");
        baseFee = _baseFee;
    }
    
    function setFeeRange(uint256 _minFee, uint256 _maxFee) external onlyOwner {
        require(_minFee < _maxFee, "Invalid range");
        require(_maxFee <= 500, "Max fee too high"); // Max 5%
        minFee = _minFee;
        maxFee = _maxFee;
    }
    
    function setTierThresholds(
        uint256 _tier1,
        uint256 _tier2,
        uint256 _tier3
    ) external onlyOwner {
        require(_tier1 < _tier2 && _tier2 < _tier3, "Invalid thresholds");
        tier1Threshold = _tier1;
        tier2Threshold = _tier2;
        tier3Threshold = _tier3;
    }
    
    function setCrossChainFee(uint256 _fee) external onlyOwner {
        require(_fee <= 100, "Fee too high"); // Max 1%
        crossChainFee = _fee;
    }
}
