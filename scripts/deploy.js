const hre = require("hardhat");

// USDC addresses on different testnets
const USDC_ADDRESSES = {
  arbitrumSepolia: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d", // Circle USDC
  baseSepolia: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", // Circle USDC
  optimismSepolia: "0x5fd84259d66Cd46123540766Be93DFE6D43130D7", // Circle USDC
  polygonAmoy: "0x41e94eb019c0762f9bfcf9fb1e58725bfb0e7582", // Circle USDC
  sepolia: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", // Circle USDC
};

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;
  
  console.log("=".repeat(60));
  console.log("🚀 AgentPay Protocol Deployment");
  console.log("=".repeat(60));
  console.log(`Network: ${network}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance: ${hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address))} ETH`);
  console.log("=".repeat(60));

  // Get USDC address for this network
  const usdcAddress = USDC_ADDRESSES[network];
  if (!usdcAddress) {
    throw new Error(`USDC address not configured for network: ${network}`);
  }
  console.log(`✅ USDC Address: ${usdcAddress}`);

  // Deploy FeeManager
  console.log("\n📦 Deploying FeeManager...");
  const FeeManager = await hre.ethers.getContractFactory("FeeManager");
  const feeManager = await FeeManager.deploy();
  await feeManager.waitForDeployment();
  const feeManagerAddress = await feeManager.getAddress();
  console.log(`✅ FeeManager deployed to: ${feeManagerAddress}`);

  // Deploy AgentEscrow
  console.log("\n📦 Deploying AgentEscrow...");
  const AgentEscrow = await hre.ethers.getContractFactory("AgentEscrow");
  const agentEscrow = await AgentEscrow.deploy(
    usdcAddress,
    deployer.address, // AI Verifier (initially deployer)
    deployer.address  // Fee Collector (initially deployer)
  );
  await agentEscrow.waitForDeployment();
  const agentEscrowAddress = await agentEscrow.getAddress();
  console.log(`✅ AgentEscrow deployed to: ${agentEscrowAddress}`);

  // Save deployment info
  const deploymentInfo = {
    network: network,
    chainId: (await hre.ethers.provider.getNetwork()).chainId.toString(),
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      FeeManager: feeManagerAddress,
      AgentEscrow: agentEscrowAddress,
      USDC: usdcAddress,
    },
    config: {
      aiVerifier: deployer.address,
      feeCollector: deployer.address,
    }
  };

  console.log("\n=".repeat(60));
  console.log("✅ DEPLOYMENT COMPLETE!");
  console.log("=".repeat(60));
  console.log(JSON.stringify(deploymentInfo, null, 2));
  console.log("=".repeat(60));

  // Save to file
  const fs = require("fs");
  const path = require("path");
  const deploymentsDir = path.join(__dirname, "../deployments");
  
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const filename = `${network}-${Date.now()}.json`;
  fs.writeFileSync(
    path.join(deploymentsDir, filename),
    JSON.stringify(deploymentInfo, null, 2)
  );
  console.log(`\n💾 Deployment info saved to: deployments/${filename}`);

  // Verification info
  console.log("\n📝 To verify contracts, run:");
  console.log(`npx hardhat verify --network ${network} ${feeManagerAddress}`);
  console.log(`npx hardhat verify --network ${network} ${agentEscrowAddress} "${usdcAddress}" "${deployer.address}" "${deployer.address}"`);

  return deploymentInfo;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
