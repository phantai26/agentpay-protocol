# AgentPay Protocol

**Trust-minimized payment infrastructure for autonomous AI agents**  
A simple escrow smart contract combined with off-chain AI-powered work verification and dynamic fee mechanism.

## Problem

Autonomous AI agents and freelance workers need a secure way to get paid for tasks without trust issues:
- Funds can be locked or stolen if paid upfront
- Manual verification is slow and biased
- No built-in mechanism for task criteria and quality check
- Fees often fixed and not reflective of task complexity

## Solution

AgentPay uses a **smart contract escrow** to lock USDC until work is verified by an AI (Claude mock in demo).  
Key features:
- Employer locks funds in escrow with task details
- Worker completes task (off-chain) and submits proof (e.g., IPFS link + hash)
- AI verifies quality against predefined criteria
- If passed → automatic payment release (worker gets amount, protocol gets fee)
- Fee: configurable (currently simple fixed fee in constructor)

### Current Flow (Demo)
1. Employer transfers USDC to escrow contract
2. Worker completes task off-chain
3. AI (Claude) evaluates output (simulated in Python script)
4. If verification passes → call releasePayment() → funds released

## Deployment Status (Feb 08, 2026)

- Network: **Ethereum Sepolia** (Chain ID: 11155111)
- **AgentEscrow**: [0xa04c2316A207ABd9c7C03e821eaa3d221d0d0e5d](https://sepolia.etherscan.io/address/0xa04c2316A207ABd9c7C03e821eaa3d221d0d0e5d)
- **FeeManager**: [0x7be68cc704149d4a12D5f20B061F308b76F22A0b](https://sepolia.etherscan.io/address/0x7be68cc704149d4a12D5f20B061F308b76F22A0b)
- **USDC (Circle testnet)**: [0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238](https://sepolia.etherscan.io/address/0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238)

Contracts verified on Sepolia Etherscan (source code public).

## Tech Stack

- Solidity ^0.8.20 + OpenZeppelin (ReentrancyGuard, Ownable, IERC20)
- Hardhat (deployment & compilation)
- Python 3.9+ (demo client & AI verification mock via Claude)
- Circle testnet USDC

## Quick Start

### Prerequisites

```bash
node >= 18
python >= 3.9

Installation
git clone https://github.com/yourusername/agentpay-protocol.git
cd agentpay-protocol

# Smart contracts
cd contracts
npm install

# Python demo
cd ../skill
pip install -r requirements.txt

Configuration (.env in contracts/)env
PRIVATE_KEY=0x...                            # Test wallet (NEVER commit!)
SEPOLIA_RPC=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY  # Or https://rpc.sepolia.org
DEFAULT_NETWORK=sepolia
AGENT_ESCROW_ADDRESS_SEPOLIA=0xa04c2316A207ABd9c7C03e821eaa3d221d0d0e5d
FEE_MANAGER_ADDRESS_SEPOLIA=0x7be68cc704149d4a12D5f20B061F308b76F22A0b
Get test tokens:
ETH: https://www.alchemy.com/faucets/ethereum-sepolia
USDC: https://faucet.circle.com (select Ethereum Sepolia)

Deploy (if redeploy needed)
cd contracts
npx hardhat compile
npx hardhat run scripts/deploy.js --network sepolia
Update .env with new addresses.

Run Full Demo (Simulation)
cd skill
python agentpay_client.py
Output shows:

Mock escrow creation
Work submission (IPFS URL + hash)
AI verification (Claude mock, score 95/100)
Payment release (100 USDC to worker, 0.95 USDC fee)

On-Chain Interaction (Manual)

Approve USDC → Etherscan → Write Contract → approve(escrow, amount)
Transfer USDC to escrow address
As aiVerifier (deployer wallet) → call releasePayment() on AgentEscrow

See token transfers on Etherscan.
Proof & Demo Materials

Deploy transaction & output: deploy-output.png
Python full demo log: python-demo-output.png
AgentEscrow on Etherscan: https://sepolia.etherscan.io/address/0xa04c2316A207ABd9c7C03e821eaa3d221d0d0e5d
FeeManager on Etherscan: https://sepolia.etherscan.io/address/0x7be68cc704149d4a12D5f20B061F308b76F22A0b

Known Limitations

AI verification is off-chain (trusted Claude simulation in Python)
No on-chain work submission or verification logic yet
Fee is simple fixed (configurable via constructor/owner)
Cross-chain CCTP configured but not demonstrated
Reputation/complexity-based fees conceptual only

Security Notes

Uses audited OpenZeppelin libraries
ReentrancyGuard on releasePayment
Ownable access control
This is a testnet PoC — production requires audit, multi-sig, timelocks

Built for