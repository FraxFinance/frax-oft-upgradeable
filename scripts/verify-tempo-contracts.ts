import { execSync } from "child_process";
import * as fs from "fs";
import * as path from "path";

/**
 * Tempo Contract Verification Script
 *
 * Verifies all contracts deployed via Foundry broadcast files on Tempo networks.
 *
 * Usage:
 *   npx ts-node scripts/verify-tempo-contracts.ts <broadcast_file> [options]
 *
 * Options:
 *   --verifier-url <url>    Custom verifier URL (default: https://contracts.tempo.xyz)
 *   --compiler <version>    Compiler version (default: auto-detected from foundry.toml)
 *   --dry-run               Generate requests without submitting
 *   --verbose               Show detailed output
 *
 * Examples:
 *   # Verify contracts on Tempo testnet (Moderato, chainId: 42431)
 *   npx ts-node scripts/verify-tempo-contracts.ts broadcast/DeployFraxUSDSepoliaHubMintableTempoTestnet.s.sol/42431/run-latest.json
 *
 *   # Verify contracts on Tempo mainnet (chainId: TBD)
 *   npx ts-node scripts/verify-tempo-contracts.ts broadcast/DeployFraxUSDSepoliaHubMintableTempoMainnet.s.sol/<chainId>/run-latest.json
 *
 *   # With custom verifier URL
 *   npx ts-node scripts/verify-tempo-contracts.ts broadcast/Deploy.s.sol/42431/run-latest.json --verifier-url https://contracts.tempo.xyz
 *
 *   # Dry run (generate requests without submitting)
 *   npx ts-node scripts/verify-tempo-contracts.ts broadcast/Deploy.s.sol/42431/run-latest.json --dry-run
 *
 * npm scripts (defined in package.json):
 *   pnpm verify:tempo <broadcast_file>           # General verification
 *   pnpm verify:tempo:testnet <broadcast_file>   # Tempo testnet (Moderato)
 *   pnpm verify:tempo:mainnet <broadcast_file>   # Tempo mainnet
 */

interface Transaction {
  hash: string;
  transactionType: "CREATE" | "CALL" | string;
  contractName: string | null;
  contractAddress: string;
  function: string | null;
  arguments: string[] | null;
  transaction: {
    input: string;
  };
}

interface BroadcastFile {
  transactions: Transaction[];
}

interface VerificationRequest {
  stdJsonInput: object;
  compilerVersion: string;
  contractIdentifier: string;
  creationTransactionHash?: string;
}

interface VerificationResponse {
  verificationId?: string;
  message?: string;
  error?: string;
}

interface VerificationStatusResponse {
  status?: string;
  error?: string;
  message?: string;
}

interface VerificationResult {
  contractName: string;
  address: string;
  status: "success" | "failed" | "pending" | "skipped" | "already_verified";
  message: string;
  verificationId?: string;
}

interface ContractInfoResponse {
  matchId?: string;
  match?: string;
  creationMatch?: string;
  runtimeMatch?: string;
  verifiedAt?: string;
  isVerified?: boolean;
  verified?: boolean;
  sourceCode?: string;
  sources?: object;
  files?: object;
  error?: string;
}

// Configuration
const CONFIG = {
  verifierUrl: "https://contracts.tempo.xyz",
  compilerVersion: "0.8.22+commit.4fc1097e",
  pollInterval: 3000, // ms
  maxPollAttempts: 20,
  verbose: false,
  dryRun: false,
};

// Contract path mappings for common contracts
const CONTRACT_PATH_OVERRIDES: Record<string, string> = {
  TransparentUpgradeableProxy:
    "node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/TransparentUpgradeableProxy.sol",
  ProxyAdmin:
    "node_modules/@fraxfinance/layerzero-v2-upgradeable/messagelib/contracts/upgradeable/proxy/ProxyAdmin.sol",
  FraxProxyAdmin: "contracts/FraxProxyAdmin.sol",
  ImplementationMock: "contracts/ImplementationMock.sol",
  FraxOFTMintableAdapterUpgradeableTIP20:
    "contracts/tempo/oft-upgradeable/FraxOFTMintableAdapterUpgradeableTIP20.sol",
  FrxUSDPolicyAdminTempo: "contracts/frxUsd/FrxUSDPolicyAdminTempo.sol",
  FraxOFTWalletUpgradeable: "contracts/FraxOFTWalletUpgradeable.sol",
};

function log(message: string, level: "info" | "warn" | "error" | "success" = "info") {
  const colors = {
    info: "\x1b[34m",
    warn: "\x1b[33m",
    error: "\x1b[31m",
    success: "\x1b[32m",
  };
  const reset = "\x1b[0m";
  console.log(`${colors[level]}${message}${reset}`);
}

function logVerbose(message: string) {
  if (CONFIG.verbose) {
    console.log(`  ${message}`);
  }
}

function extractChainId(broadcastPath: string): string {
  const match = broadcastPath.match(/\/(\d+)\//);
  if (!match) {
    throw new Error(`Could not extract chain ID from path: ${broadcastPath}`);
  }
  return match[1];
}

function findContractPath(contractName: string): string | null {
  // Check overrides first - these may use remappings (e.g., @fraxfinance/)
  // so we don't check if file exists, forge will resolve them
  if (CONTRACT_PATH_OVERRIDES[contractName]) {
    return CONTRACT_PATH_OVERRIDES[contractName];
  }

  // Search in contracts directory
  const searchDirs = ["contracts", "lib"];
  for (const dir of searchDirs) {
    if (!fs.existsSync(dir)) continue;

    try {
      const result = execSync(`find ${dir} -name "${contractName}.sol" 2>/dev/null | head -1`, {
        encoding: "utf-8",
      }).trim();
      if (result) return result;
    } catch {
      // Continue searching
    }
  }

  return null;
}

function generateStandardJsonInput(contractAddress: string, contractIdentifier: string): object | null {
  try {
    const result = execSync(
      `forge verify-contract ${contractAddress} "${contractIdentifier}" --show-standard-json-input`,
      { encoding: "utf-8", maxBuffer: 50 * 1024 * 1024 }
    );
    return JSON.parse(result);
  } catch (error) {
    log(`Failed to generate standard JSON input: ${error}`, "error");
    return null;
  }
}

async function submitVerification(
  chainId: string,
  contractAddress: string,
  request: VerificationRequest
): Promise<VerificationResponse> {
  const url = `${CONFIG.verifierUrl}/v2/verify/${chainId}/${contractAddress}`;

  logVerbose(`POST ${url}`);

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
  });

  return response.json() as Promise<VerificationResponse>;
}

async function pollVerificationStatus(
  chainId: string,
  contractAddress: string,
  verificationId: string
): Promise<VerificationStatusResponse> {
  const url = `${CONFIG.verifierUrl}/v2/verify/${chainId}/${contractAddress}/${verificationId}`;

  logVerbose(`GET ${url}`);

  try {
    const response = await fetch(url);
    const text = await response.text();
    logVerbose(`Response: ${text.substring(0, 200)}`);
    
    try {
      return JSON.parse(text) as VerificationStatusResponse;
    } catch {
      // If not JSON, check if it's a simple status string
      if (text.includes("verified") || text.includes("perfect") || text.includes("partial")) {
        return { status: "verified" };
      }
      return { status: "pending", message: text };
    }
  } catch (error) {
    logVerbose(`Error polling status: ${error}`);
    return { status: "pending", error: String(error) };
  }
}

async function checkIfAlreadyVerified(
  chainId: string,
  contractAddress: string
): Promise<boolean> {
  try {
    // Try the contract metadata endpoint
    const metadataUrl = `${CONFIG.verifierUrl}/v2/contract/${chainId}/${contractAddress}`;
    logVerbose(`Checking verification status: GET ${metadataUrl}`);
    
    const metadataResponse = await fetch(metadataUrl);
    if (metadataResponse.ok) {
      const data = (await metadataResponse.json()) as ContractInfoResponse;
      // Tempo API returns matchId, match, verifiedAt when contract is verified
      if (data.matchId || data.match || data.verifiedAt) {
        logVerbose(`Contract verified at: ${data.verifiedAt}, match: ${data.match}`);
        return true;
      }
    }

    return false;
  } catch (error) {
    logVerbose(`Error checking verification status: ${error}`);
    return false;
  }
}

async function verifyContract(
  chainId: string,
  contractName: string,
  contractAddress: string,
  txHash: string
): Promise<VerificationResult> {
  log(`\n────────────────────────────────────────────────────────`);
  log(`Verifying: ${contractName}`);
  log(`Address: ${contractAddress}`);
  log(`TX Hash: ${txHash}`);
  // Check if already verified
  log(`  → Checking if already verified...`, "warn");
  const alreadyVerified = await checkIfAlreadyVerified(chainId, contractAddress);
  if (alreadyVerified) {
    log(`  ✓ Already verified - skipping`, "success");
    return {
      contractName,
      address: contractAddress,
      status: "already_verified",
      message: "Contract is already verified",
    };
  }
  // Find contract source path
  const contractPath = findContractPath(contractName);
  if (!contractPath) {
    return {
      contractName,
      address: contractAddress,
      status: "failed",
      message: `Could not find source file for ${contractName}`,
    };
  }

  const contractIdentifier = `${contractPath}:${contractName}`;
  log(`Contract ID: ${contractIdentifier}`, "info");

  // Generate standard JSON input
  log(`  → Generating standard JSON input...`, "warn");
  const stdJsonInput = generateStandardJsonInput(contractAddress, contractIdentifier);
  if (!stdJsonInput) {
    return {
      contractName,
      address: contractAddress,
      status: "failed",
      message: "Failed to generate standard JSON input",
    };
  }

  // Build verification request
  const request: VerificationRequest = {
    stdJsonInput,
    compilerVersion: CONFIG.compilerVersion,
    contractIdentifier,
    creationTransactionHash: txHash,
  };

  if (CONFIG.dryRun) {
    log(`  ✓ Dry run - request generated successfully`, "success");
    return {
      contractName,
      address: contractAddress,
      status: "success",
      message: "Dry run - request generated",
    };
  }

  // Submit verification
  log(`  → Submitting verification request...`, "warn");
  const response = await submitVerification(chainId, contractAddress, request);

  if (!response.verificationId) {
    return {
      contractName,
      address: contractAddress,
      status: "failed",
      message: response.message || response.error || "Unknown error",
    };
  }

  log(`  ✓ Submitted (ID: ${response.verificationId})`, "success");

  // Poll for status - check the contract endpoint since status endpoint may not exist
  log(`  → Polling verification status...`, "warn");
  for (let attempt = 0; attempt < CONFIG.maxPollAttempts; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, CONFIG.pollInterval));

    // Check if contract is now verified via the contract endpoint
    const isNowVerified = await checkIfAlreadyVerified(chainId, contractAddress);
    if (isNowVerified) {
      log(`  ✓ Verification successful`, "success");
      return {
        contractName,
        address: contractAddress,
        status: "success",
        message: "verified",
        verificationId: response.verificationId,
      };
    }

    logVerbose(`Status: pending (attempt ${attempt + 1}/${CONFIG.maxPollAttempts})`);
  }

  log(`  ⏳ Verification still pending after ${CONFIG.maxPollAttempts} attempts`, "warn");
  return {
    contractName,
    address: contractAddress,
    status: "pending",
    message: `Still pending - check manually`,
    verificationId: response.verificationId,
  };
}

async function main() {
  const args = process.argv.slice(2);

  // Parse arguments
  let broadcastFile = "";
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--verifier-url" && args[i + 1]) {
      CONFIG.verifierUrl = args[++i];
    } else if (args[i] === "--compiler" && args[i + 1]) {
      CONFIG.compilerVersion = args[++i];
    } else if (args[i] === "--dry-run") {
      CONFIG.dryRun = true;
    } else if (args[i] === "--verbose") {
      CONFIG.verbose = true;
    } else if (!args[i].startsWith("--")) {
      broadcastFile = args[i];
    }
  }

  if (!broadcastFile) {
    console.error("Usage: npx ts-node scripts/verify-tempo-contracts.ts <broadcast_file> [options]");
    console.error("");
    console.error("Options:");
    console.error("  --verifier-url <url>    Custom verifier URL");
    console.error("  --compiler <version>    Compiler version");
    console.error("  --dry-run               Generate requests without submitting");
    console.error("  --verbose               Show detailed output");
    process.exit(1);
  }

  if (!fs.existsSync(broadcastFile)) {
    log(`Error: Broadcast file not found: ${broadcastFile}`, "error");
    process.exit(1);
  }

  const chainId = extractChainId(broadcastFile);

  log("═══════════════════════════════════════════════════════════════");
  log("           Tempo Contract Verification Script");
  log("═══════════════════════════════════════════════════════════════");
  log(`Broadcast file: ${broadcastFile}`, "warn");
  log(`Chain ID: ${chainId}`, "warn");
  log(`Verifier URL: ${CONFIG.verifierUrl}`, "warn");
  log(`Compiler: ${CONFIG.compilerVersion}`, "warn");
  if (CONFIG.dryRun) log(`Mode: DRY RUN`, "warn");

  // Read broadcast file
  const broadcast: BroadcastFile = JSON.parse(fs.readFileSync(broadcastFile, "utf-8"));

  // Filter CREATE transactions
  const deployments = broadcast.transactions.filter(
    (tx) => tx.transactionType === "CREATE" && tx.contractName
  );

  if (deployments.length === 0) {
    log("No CREATE transactions found in broadcast file", "error");
    process.exit(1);
  }

  log(`\nFound ${deployments.length} contracts to verify`, "success");

  // Verify each contract
  const results: VerificationResult[] = [];
  for (const deployment of deployments) {
    const result = await verifyContract(
      chainId,
      deployment.contractName!,
      deployment.contractAddress,
      deployment.hash
    );
    results.push(result);
  }

  // Print summary
  log("\n═══════════════════════════════════════════════════════════════");
  log("                    Verification Summary");
  log("═══════════════════════════════════════════════════════════════\n");

  const successCount = results.filter((r) => r.status === "success").length;
  const alreadyVerifiedCount = results.filter((r) => r.status === "already_verified").length;
  const failedCount = results.filter((r) => r.status === "failed").length;
  const pendingCount = results.filter((r) => r.status === "pending").length;

  for (const result of results) {
    const icon =
      result.status === "success" || result.status === "already_verified"
        ? "✓"
        : result.status === "failed"
        ? "✗"
        : "⏳";
    const color =
      result.status === "success" || result.status === "already_verified"
        ? "success"
        : result.status === "failed"
        ? "error"
        : "warn";
    log(`  ${icon} ${result.contractName} (${result.address})`, color);
    if (result.message && CONFIG.verbose) {
      logVerbose(`    ${result.message}`);
    }
  }

  log("");
  log(`Already Verified: ${alreadyVerifiedCount}`, "success");
  log(`Newly Verified: ${successCount}`, "success");
  log(`Failed: ${failedCount}`, "error");
  log(`Pending: ${pendingCount}`, "warn");
  log(`Total: ${results.length}`, "info");

  if (failedCount === 0 && pendingCount === 0) {
    log("\nAll contracts verified successfully!", "success");
    process.exit(0);
  } else {
    log("\nSome contracts need attention. Check the output above.", "warn");
    process.exit(1);
  }
}

main().catch((error) => {
  log(`Error: ${error.message}`, "error");
  process.exit(1);
});
