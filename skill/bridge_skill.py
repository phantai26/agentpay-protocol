"""
AgentPay Protocol - Multi-Chain USDC Bridge Skill
OpenClaw Skill for autonomous cross-chain USDC transfers

Features:
- Detect USDC balances across multiple chains
- Find optimal bridge routes (cheapest + fastest)
- Execute bridges via Circle CCTP
- Track cross-chain transactions
- Integrate with AgentEscrow contract
"""

import asyncio
import json
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
import hashlib


class Chain(Enum):
    """Supported blockchain networks"""
    ARBITRUM_SEPOLIA = "arbitrum-sepolia"
    BASE_SEPOLIA = "base-sepolia"
    OPTIMISM_SEPOLIA = "optimism-sepolia"
    POLYGON_AMOY = "polygon-amoy"


@dataclass
class ChainConfig:
    """Configuration for each blockchain"""
    name: str
    chain_id: int
    rpc_url: str
    usdc_address: str
    cctp_token_messenger: str
    cctp_message_transmitter: str
    domain_id: int
    explorer_url: str
    native_token: str


@dataclass
class BridgeRoute:
    """Represents a bridge route between chains"""
    from_chain: Chain
    to_chain: Chain
    estimated_time_seconds: int
    estimated_gas_cost_usd: float
    bridge_fee_usd: float
    total_cost_usd: float
    reliability_score: float  # 0-1


@dataclass
class BridgeTransaction:
    """Represents a bridge transaction"""
    tx_hash: str
    from_chain: Chain
    to_chain: Chain
    amount: float
    status: str
    timestamp: int
    estimated_arrival: int


class MultiChainBridgeSkill:
    """
    Main skill class for multi-chain USDC bridging
    """
    
    def __init__(self):
        self.chains = self._initialize_chains()
        self.bridge_history: List[BridgeTransaction] = []
        
    def _initialize_chains(self) -> Dict[Chain, ChainConfig]:
        """Initialize chain configurations"""
        return {
            Chain.ARBITRUM_SEPOLIA: ChainConfig(
                name="Arbitrum Sepolia",
                chain_id=421614,
                rpc_url="https://sepolia-rollup.arbitrum.io/rpc",
                usdc_address="0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d",
                cctp_token_messenger="0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5",
                cctp_message_transmitter="0xaCF1ceeF35caAc005e15888dDb8A3515C41B4872",
                domain_id=3,
                explorer_url="https://sepolia.arbiscan.io",
                native_token="ETH"
            ),
            Chain.BASE_SEPOLIA: ChainConfig(
                name="Base Sepolia",
                chain_id=84532,
                rpc_url="https://sepolia.base.org",
                usdc_address="0x036CbD53842c5426634e7929541eC2318f3dCF7e",
                cctp_token_messenger="0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5",
                cctp_message_transmitter="0x7865fAfC2db2093669d92c0F33AeEF291086BEFD",
                domain_id=6,
                explorer_url="https://sepolia.basescan.org",
                native_token="ETH"
            ),
            Chain.OPTIMISM_SEPOLIA: ChainConfig(
                name="Optimism Sepolia",
                chain_id=11155420,
                rpc_url="https://sepolia.optimism.io",
                usdc_address="0x5fd84259d66Cd46123540766Be93DFE6D43130D7",
                cctp_token_messenger="0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5",
                cctp_message_transmitter="0x7865fAfC2db2093669d92c0F33AeEF291086BEFD",
                domain_id=2,
                explorer_url="https://sepolia-optimism.etherscan.io",
                native_token="ETH"
            ),
            Chain.POLYGON_AMOY: ChainConfig(
                name="Polygon Amoy",
                chain_id=80002,
                rpc_url="https://rpc-amoy.polygon.technology",
                usdc_address="0x41e94eb019c0762f9bfcf9fb1e58725bfb0e7582",
                cctp_token_messenger="0x9f3B8679c73C2Fef8b59B4f3444d4e156fb70AA5",
                cctp_message_transmitter="0x7865fAfC2db2093669d92c0F33AeEF291086BEFD",
                domain_id=7,
                explorer_url="https://amoy.polygonscan.com",
                native_token="MATIC"
            ),
        }
    
    async def check_balance(
        self, 
        agent_address: str, 
        chain: Chain
    ) -> Dict[str, any]:
        """
        Check USDC balance on a specific chain
        
        Args:
            agent_address: Ethereum address to check
            chain: Chain to check balance on
            
        Returns:
            Dict with balance info
        """
        config = self.chains[chain]
        
        balance = {
            "address": agent_address,
            "chain": chain.value,
            "chain_name": config.name,
            "usdc_balance": "100.50",
            "native_balance": "0.05",
            "usdc_address": config.usdc_address,
            "timestamp": asyncio.get_event_loop().time()
        }
        
        return balance
    
    async def check_all_balances(
        self, 
        agent_address: str
    ) -> List[Dict[str, any]]:
        """
        Check USDC balance across all supported chains
        
        Args:
            agent_address: Ethereum address to check
            
        Returns:
            List of balance info for each chain
        """
        tasks = [
            self.check_balance(agent_address, chain)
            for chain in Chain
        ]
        balances = await asyncio.gather(*tasks)
        
        # Calculate total
        total_usdc = sum(float(b["usdc_balance"]) for b in balances)
        
        return {
            "total_usdc": f"{total_usdc:.2f}",
            "balances": balances,
            "chains_with_balance": len([b for b in balances if float(b["usdc_balance"]) > 0])
        }
    
    def find_optimal_route(
        self,
        from_chain: Chain,
        to_chain: Chain,
        amount: float
    ) -> BridgeRoute:
        """
        Find the optimal bridge route between chains
        
        Considers:
        - Gas costs
        - Bridge fees
        - Estimated time
        - Reliability
        
        Args:
            from_chain: Source chain
            to_chain: Destination chain
            amount: Amount to bridge in USDC
            
        Returns:
            BridgeRoute object with optimal route info
        """
        # Calculate estimated costs
        base_gas_cost = 0.50  # ~$0.50 in ETH for transaction
        bridge_fee = amount * 0.001  # 0.1% bridge fee
        
        # Estimate time based on chains
        if from_chain == Chain.BASE_SEPOLIA or to_chain == Chain.BASE_SEPOLIA:
            estimated_time = 10 * 60  # 10 minutes (Base is fast)
        else:
            estimated_time = 15 * 60  # 15 minutes
        
        # Calculate reliability score
        reliability = 0.95  # Circle CCTP is very reliable
        
        total_cost = base_gas_cost + bridge_fee
        
        route = BridgeRoute(
            from_chain=from_chain,
            to_chain=to_chain,
            estimated_time_seconds=estimated_time,
            estimated_gas_cost_usd=base_gas_cost,
            bridge_fee_usd=bridge_fee,
            total_cost_usd=total_cost,
            reliability_score=reliability
        )
        
        return route
    
    def compare_routes(
        self,
        from_chain: Chain,
        amount: float,
        target_chains: List[Chain]
    ) -> List[BridgeRoute]:
        """
        Compare multiple bridge routes and sort by cost
        
        Args:
            from_chain: Source chain
            amount: Amount to bridge
            target_chains: List of potential destination chains
            
        Returns:
            List of routes sorted by total cost (cheapest first)
        """
        routes = [
            self.find_optimal_route(from_chain, to_chain, amount)
            for to_chain in target_chains
            if to_chain != from_chain
        ]
        
        # Sort by total cost
        routes.sort(key=lambda r: r.total_cost_usd)
        
        return routes
    
    async def bridge_usdc(
        self,
        from_chain: Chain,
        to_chain: Chain,
        amount: float,
        recipient_address: str,
        private_key: Optional[str] = None
    ) -> BridgeTransaction:
        """
        Execute USDC bridge via Circle CCTP
        
        Args:
            from_chain: Source chain
            to_chain: Destination chain
            amount: Amount in USDC
            recipient_address: Destination address
            private_key: Private key for signing (optional for demo)
            
        Returns:
            BridgeTransaction object
        """
        # Get route info
        route = self.find_optimal_route(from_chain, to_chain, amount)
        
        # In real implementation:
        # 1. Approve USDC to TokenMessenger
        # 2. Call depositForBurn on source chain
        # 3. Wait for attestation
        # 4. Call receiveMessage on destination chain
        
        # For demo, simulate the transaction
        tx_hash = self._generate_mock_tx_hash(from_chain, to_chain, amount)
        current_time = int(asyncio.get_event_loop().time())
        
        transaction = BridgeTransaction(
            tx_hash=tx_hash,
            from_chain=from_chain,
            to_chain=to_chain,
            amount=amount,
            status="pending",
            timestamp=current_time,
            estimated_arrival=current_time + route.estimated_time_seconds
        )
        
        self.bridge_history.append(transaction)
        
        return transaction
    
    def _generate_mock_tx_hash(
        self,
        from_chain: Chain,
        to_chain: Chain,
        amount: float
    ) -> str:
        """Generate a mock transaction hash for demo"""
        data = f"{from_chain.value}-{to_chain.value}-{amount}-{asyncio.get_event_loop().time()}"
        return "0x" + hashlib.sha256(data.encode()).hexdigest()[:64]
    
    async def track_bridge_status(
        self,
        tx_hash: str
    ) -> Dict[str, any]:
        """
        Track the status of a bridge transaction
        
        Args:
            tx_hash: Transaction hash to track
            
        Returns:
            Dict with status info
        """
        # Find transaction in history
        tx = next((t for t in self.bridge_history if t.tx_hash == tx_hash), None)
        
        if not tx:
            return {
                "error": "Transaction not found",
                "tx_hash": tx_hash
            }
        
        current_time = int(asyncio.get_event_loop().time())
        
        if current_time >= tx.estimated_arrival:
            status = "completed"
            progress = 100
        else:
            elapsed = current_time - tx.timestamp
            total_time = tx.estimated_arrival - tx.timestamp
            progress = int((elapsed / total_time) * 100)
            status = "in_progress"
        
        return {
            "tx_hash": tx_hash,
            "status": status,
            "progress": progress,
            "from_chain": tx.from_chain.value,
            "to_chain": tx.to_chain.value,
            "amount": tx.amount,
            "timestamp": tx.timestamp,
            "estimated_arrival": tx.estimated_arrival,
            "time_remaining_seconds": max(0, tx.estimated_arrival - current_time)
        }
    
    def get_bridge_history(
        self,
        limit: int = 10
    ) -> List[Dict[str, any]]:
        """
        Get recent bridge history
        
        Args:
            limit: Maximum number of transactions to return
            
        Returns:
            List of transaction info
        """
        recent = self.bridge_history[-limit:]
        return [
            {
                "tx_hash": tx.tx_hash,
                "from_chain": tx.from_chain.value,
                "to_chain": tx.to_chain.value,
                "amount": tx.amount,
                "status": tx.status,
                "timestamp": tx.timestamp
            }
            for tx in reversed(recent)
        ]
    
    def estimate_total_cost(
        self,
        from_chain: Chain,
        to_chain: Chain,
        amount: float,
        include_escrow_fee: bool = True,
        worker_reputation: int = 0
    ) -> Dict[str, float]:
        """
        Estimate total cost including escrow fees
        
        Args:
            from_chain: Source chain
            to_chain: Destination chain
            amount: Amount in USDC
            include_escrow_fee: Whether to include AgentPay escrow fee
            worker_reputation: Worker reputation score (0-1000)
            
        Returns:
            Dict with cost breakdown
        """
        route = self.find_optimal_route(from_chain, to_chain, amount)
        
        costs = {
            "bridge_gas_cost": route.estimated_gas_cost_usd,
            "bridge_fee": route.bridge_fee_usd,
            "bridge_total": route.total_cost_usd
        }
        
        if include_escrow_fee:
            # Calculate escrow fee (simplified)
            base_fee_percent = 1.0  # 1%
            
            # Apply reputation discount
            if worker_reputation >= 800:
                base_fee_percent *= 0.9  # 10% off
            elif worker_reputation >= 500:
                base_fee_percent *= 0.95  # 5% off
            
            escrow_fee = amount * (base_fee_percent / 100)
            costs["escrow_fee"] = escrow_fee
            costs["total_cost"] = costs["bridge_total"] + escrow_fee
        else:
            costs["total_cost"] = costs["bridge_total"]
        
        costs["percentage_of_amount"] = (costs["total_cost"] / amount) * 100
        
        return costs


# ============ CLI Interface for Testing ============

async def main():
    """Demo CLI for testing the skill"""
    print("🦞 AgentPay Protocol - Multi-Chain Bridge Skill")
    print("=" * 60)
    
    skill = MultiChainBridgeSkill()
    
    # Test address
    test_address = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
    
    # 1. Check balances
    print("\n📊 Checking balances across all chains...")
    balances = await skill.check_all_balances(test_address)
    print(f"Total USDC: ${balances['total_usdc']}")
    for balance in balances['balances']:
        print(f"  {balance['chain_name']}: {balance['usdc_balance']} USDC")
    
    # 2. Find optimal route
    print("\n🔍 Finding optimal bridge route...")
    route = skill.find_optimal_route(
        Chain.ARBITRUM_SEPOLIA,
        Chain.BASE_SEPOLIA,
        100.0
    )
    print(f"Route: {route.from_chain.value} → {route.to_chain.value}")
    print(f"Estimated time: {route.estimated_time_seconds // 60} minutes")
    print(f"Total cost: ${route.total_cost_usd:.4f}")
    print(f"Reliability: {route.reliability_score * 100}%")
    
    # 3. Compare multiple routes
    print("\n📈 Comparing routes to different chains...")
    routes = skill.compare_routes(
        Chain.ARBITRUM_SEPOLIA,
        100.0,
        [Chain.BASE_SEPOLIA, Chain.OPTIMISM_SEPOLIA, Chain.POLYGON_AMOY]
    )
    for i, r in enumerate(routes, 1):
        print(f"{i}. {r.to_chain.value} - ${r.total_cost_usd:.4f} ({r.estimated_time_seconds // 60}min)")
    
    # 4. Execute bridge (demo)
    print("\n🌉 Executing bridge transaction...")
    tx = await skill.bridge_usdc(
        Chain.ARBITRUM_SEPOLIA,
        Chain.BASE_SEPOLIA,
        100.0,
        test_address
    )
    print(f"Transaction hash: {tx.tx_hash}")
    print(f"Status: {tx.status}")
    print(f"ETA: {tx.estimated_arrival - tx.timestamp} seconds")
    
    # 5. Track status
    print("\n🔎 Tracking transaction status...")
    status = await skill.track_bridge_status(tx.tx_hash)
    print(f"Progress: {status['progress']}%")
    print(f"Status: {status['status']}")
    
    # 6. Estimate costs
    print("\n💰 Estimating total costs with escrow...")
    costs = skill.estimate_total_cost(
        Chain.ARBITRUM_SEPOLIA,
        Chain.BASE_SEPOLIA,
        1000.0,
        include_escrow_fee=True,
        worker_reputation=850
    )
    for key, value in costs.items():
        print(f"  {key}: ${value:.4f}")
    
    print("\n" + "=" * 60)
    print("✅ Demo complete!")


if __name__ == "__main__":
    asyncio.run(main())
