#!/bin/bash
# Tempo Contract Verification Script
# Verifies all contracts deployed via Foundry broadcast files on Tempo networks
#
# Usage: 
#   ./scripts/verify-tempo-contracts.sh <broadcast_file> [verifier_url]
#
# Examples:
#   # Testnet (Moderato)
#   ./scripts/verify-tempo-contracts.sh broadcast/DeployFraxUSDSepoliaHubMintableTempoTestnet.s.sol/42431/run-latest.json
#   
#   # Mainnet (Allegretto) - specify custom verifier URL if needed  
#   ./scripts/verify-tempo-contracts.sh broadcast/DeployFraxUSD.s.sol/421614/run-latest.json https://contracts.tempo.xyz

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BROADCAST_FILE="${1:-}"
VERIFIER_URL="${2:-https://contracts.tempo.xyz}"
COMPILER_VERSION="0.8.22+commit.4fc1097e"
POLL_INTERVAL=3
MAX_POLL_ATTEMPTS=20

# Validate inputs
if [ -z "$BROADCAST_FILE" ]; then
    echo -e "${RED}Error: Broadcast file path required${NC}"
    echo "Usage: $0 <broadcast_file> [verifier_url]"
    exit 1
fi

if [ ! -f "$BROADCAST_FILE" ]; then
    echo -e "${RED}Error: Broadcast file not found: $BROADCAST_FILE${NC}"
    exit 1
fi

# Check for required tools
for cmd in jq curl forge; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed${NC}"
        exit 1
    fi
done

# Extract chain ID from the broadcast file path
CHAIN_ID=$(echo "$BROADCAST_FILE" | grep -oE '/[0-9]+/' | tr -d '/')
if [ -z "$CHAIN_ID" ]; then
    echo -e "${RED}Error: Could not extract chain ID from broadcast file path${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           Tempo Contract Verification Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Broadcast file:${NC} $BROADCAST_FILE"
echo -e "${YELLOW}Chain ID:${NC} $CHAIN_ID"
echo -e "${YELLOW}Verifier URL:${NC} $VERIFIER_URL"
echo -e "${YELLOW}Compiler:${NC} $COMPILER_VERSION"
echo ""

# Extract CREATE transactions (contract deployments) from broadcast file
echo -e "${BLUE}Extracting deployed contracts...${NC}"

CONTRACTS=$(jq -r '.transactions[] | select(.transactionType == "CREATE") | {
    name: .contractName,
    address: .contractAddress,
    hash: .hash,
    arguments: .arguments
} | @base64' "$BROADCAST_FILE")

if [ -z "$CONTRACTS" ]; then
    echo -e "${RED}No CREATE transactions found in broadcast file${NC}"
    exit 1
fi

# Count contracts
CONTRACT_COUNT=$(echo "$CONTRACTS" | wc -l | tr -d ' ')
echo -e "${GREEN}Found $CONTRACT_COUNT contracts to verify${NC}"
echo ""

# Store verification results
declare -a VERIFICATION_RESULTS=()
VERIFIED_COUNT=0
FAILED_COUNT=0

# Function to decode base64 contract info
decode_contract() {
    echo "$1" | base64 --decode
}

# Function to find contract source path
find_contract_path() {
    local contract_name="$1"
    local contract_path=""
    
    # Search in contracts/ directory first
    contract_path=$(find contracts -name "${contract_name}.sol" 2>/dev/null | head -1)
    
    # If not found, search in lib/ for OpenZeppelin contracts
    if [ -z "$contract_path" ]; then
        contract_path=$(find lib -name "${contract_name}.sol" 2>/dev/null | head -1)
    fi
    
    echo "$contract_path"
}

# Function to check if contract is already verified
check_if_verified() {
    local contract_address="$1"
    
    # Query the contract metadata endpoint to check verification status
    local response=$(curl -s "${VERIFIER_URL}/v2/contract/${CHAIN_ID}/${contract_address}" 2>/dev/null)
    
    # Tempo API returns matchId, match, verifiedAt when contract is verified
    local match_id=$(echo "$response" | jq -r '.matchId // empty' 2>/dev/null)
    local match=$(echo "$response" | jq -r '.match // empty' 2>/dev/null)
    local verified_at=$(echo "$response" | jq -r '.verifiedAt // empty' 2>/dev/null)
    
    if [ -n "$match_id" ] || [ -n "$match" ] || [ -n "$verified_at" ]; then
        return 0  # Already verified
    fi
    
    return 1  # Not verified
}

# Function to verify a single contract
verify_contract() {
    local contract_name="$1"
    local contract_address="$2"
    local tx_hash="$3"
    
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}Verifying:${NC} $contract_name"
    echo -e "${BLUE}Address:${NC} $contract_address"
    echo -e "${BLUE}TX Hash:${NC} $tx_hash"
    
    # Check if already verified
    echo -e "${YELLOW}  → Checking if already verified...${NC}"
    if check_if_verified "$contract_address"; then
        echo -e "${GREEN}  ✓ Already verified - skipping${NC}"
        return 0
    fi
    
    # Find contract source path
    local contract_path=$(find_contract_path "$contract_name")
    
    if [ -z "$contract_path" ]; then
        echo -e "${RED}  ✗ Could not find source file for $contract_name${NC}"
        return 1
    fi
    
    local contract_identifier="${contract_path}:${contract_name}"
    echo -e "${BLUE}Contract ID:${NC} $contract_identifier"
    
    # Generate standard JSON input
    local temp_json_input=$(mktemp)
    local temp_request=$(mktemp)
    
    echo -e "${YELLOW}  → Generating standard JSON input...${NC}"
    if ! forge verify-contract "$contract_address" "$contract_identifier" \
        --show-standard-json-input > "$temp_json_input" 2>/dev/null; then
        echo -e "${RED}  ✗ Failed to generate standard JSON input${NC}"
        rm -f "$temp_json_input" "$temp_request"
        return 1
    fi
    
    # Validate JSON was generated
    if ! jq empty "$temp_json_input" 2>/dev/null; then
        echo -e "${RED}  ✗ Generated invalid JSON${NC}"
        rm -f "$temp_json_input" "$temp_request"
        return 1
    fi
    
    # Build verification request
    echo -e "${YELLOW}  → Submitting verification request...${NC}"
    jq -c --arg version "$COMPILER_VERSION" \
          --arg identifier "$contract_identifier" \
          --arg txHash "$tx_hash" \
          '{
            stdJsonInput: .,
            compilerVersion: $version,
            contractIdentifier: $identifier,
            creationTransactionHash: $txHash
          }' "$temp_json_input" > "$temp_request"
    
    # Submit verification request
    local response=$(curl -s -X POST \
        "${VERIFIER_URL}/v2/verify/${CHAIN_ID}/${contract_address}" \
        -H "Content-Type: application/json" \
        -d @"$temp_request")
    
    rm -f "$temp_json_input" "$temp_request"
    
    # Check for verification ID
    local verification_id=$(echo "$response" | jq -r '.verificationId // empty')
    
    if [ -z "$verification_id" ]; then
        local error_msg=$(echo "$response" | jq -r '.message // .error // "Unknown error"')
        echo -e "${RED}  ✗ Verification submission failed: $error_msg${NC}"
        return 1
    fi
    
    echo -e "${GREEN}  ✓ Submitted (ID: $verification_id)${NC}"
    
    # Poll for verification status
    echo -e "${YELLOW}  → Polling verification status...${NC}"
    local attempts=0
    while [ $attempts -lt $MAX_POLL_ATTEMPTS ]; do
        sleep $POLL_INTERVAL
        
        local status_response=$(curl -s \
            "${VERIFIER_URL}/v2/verify/${CHAIN_ID}/${contract_address}/${verification_id}")
        
        local status=$(echo "$status_response" | jq -r '.status // "pending"')
        
        case "$status" in
            "verified"|"perfect"|"partial")
                echo -e "${GREEN}  ✓ Verification successful: $status${NC}"
                return 0
                ;;
            "failed"|"error")
                local error=$(echo "$status_response" | jq -r '.error // .message // "Unknown error"')
                echo -e "${RED}  ✗ Verification failed: $error${NC}"
                return 1
                ;;
            *)
                attempts=$((attempts + 1))
                echo -e "${YELLOW}    Status: $status (attempt $attempts/$MAX_POLL_ATTEMPTS)${NC}"
                ;;
        esac
    done
    
    echo -e "${YELLOW}  ⏳ Verification still pending after $MAX_POLL_ATTEMPTS attempts${NC}"
    echo -e "${YELLOW}    Check manually: ${VERIFIER_URL}/v2/verify/${CHAIN_ID}/${contract_address}/${verification_id}${NC}"
    return 2
}

# Process each contract
for contract_b64 in $CONTRACTS; do
    contract_json=$(decode_contract "$contract_b64")
    
    contract_name=$(echo "$contract_json" | jq -r '.name')
    contract_address=$(echo "$contract_json" | jq -r '.address')
    tx_hash=$(echo "$contract_json" | jq -r '.hash')
    
    # Skip null contract names (shouldn't happen, but safety check)
    if [ "$contract_name" == "null" ] || [ -z "$contract_name" ]; then
        echo -e "${YELLOW}Skipping transaction with no contract name${NC}"
        continue
    fi
    
    if verify_contract "$contract_name" "$contract_address" "$tx_hash"; then
        VERIFIED_COUNT=$((VERIFIED_COUNT + 1))
        VERIFICATION_RESULTS+=("${GREEN}✓${NC} $contract_name ($contract_address)")
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        VERIFICATION_RESULTS+=("${RED}✗${NC} $contract_name ($contract_address)")
    fi
done

# Print summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    Verification Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
for result in "${VERIFICATION_RESULTS[@]}"; do
    echo -e "  $result"
done
echo ""
echo -e "${GREEN}Verified:${NC} $VERIFIED_COUNT"
echo -e "${RED}Failed:${NC} $FAILED_COUNT"
echo -e "${YELLOW}Total:${NC} $CONTRACT_COUNT"
echo ""

if [ $FAILED_COUNT -eq 0 ]; then
    echo -e "${GREEN}All contracts verified successfully!${NC}"
    exit 0
else
    echo -e "${YELLOW}Some contracts failed verification. Check the output above for details.${NC}"
    exit 1
fi
