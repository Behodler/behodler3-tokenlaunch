#!/bin/bash

# Mythril Analysis Script for Behodler3 Token Launch
# Fixes import callback issues by providing proper solc configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Mythril Analysis Script for Behodler3 Token Launch${NC}"
echo -e "${YELLOW}==================================================${NC}"

# Check if mythril is installed
if ! command -v myth &> /dev/null; then
    echo -e "${RED}Error: Mythril is not installed or not in PATH${NC}"
    exit 1
fi

# Check if config file exists
CONFIG_FILE="mythril-solc-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: $CONFIG_FILE not found${NC}"
    exit 1
fi

# Default parameters
SOLC_VERSION="0.8.25"
OUTPUT_FORMAT="text"
TIMEOUT="300"

# Parse command line arguments
CONTRACT_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            CONTRACT_FILE="$2"
            shift 2
            ;;
        -v|--solc-version)
            SOLC_VERSION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 -f <contract_file> [options]"
            echo "Options:"
            echo "  -f, --file <file>           Solidity contract file to analyze"
            echo "  -v, --solc-version <ver>    Solidity compiler version (default: $SOLC_VERSION)"
            echo "  -o, --output <format>       Output format: text|json|markdown (default: $OUTPUT_FORMAT)"
            echo "  -t, --timeout <seconds>     Analysis timeout (default: $TIMEOUT)"
            echo "  -h, --help                  Show this help message"
            exit 0
            ;;
        *)
            if [ -z "$CONTRACT_FILE" ]; then
                CONTRACT_FILE="$1"
            else
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if contract file is provided
if [ -z "$CONTRACT_FILE" ]; then
    echo -e "${RED}Error: No contract file specified${NC}"
    echo "Use -h for help"
    exit 1
fi

# Check if contract file exists
if [ ! -f "$CONTRACT_FILE" ]; then
    echo -e "${RED}Error: Contract file $CONTRACT_FILE not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Analyzing: $CONTRACT_FILE${NC}"
echo -e "${YELLOW}Solc Version: $SOLC_VERSION${NC}"
echo -e "${YELLOW}Output Format: $OUTPUT_FORMAT${NC}"
echo -e "${YELLOW}Timeout: $TIMEOUT seconds${NC}"
echo ""

# Create log file
LOG_FILE="mythril-analysis-$(basename "$CONTRACT_FILE" .sol)-$(date +%Y%m%d-%H%M%S).log"

echo -e "${YELLOW}Starting Mythril analysis...${NC}"
echo -e "${YELLOW}Log file: $LOG_FILE${NC}"

# Run mythril with proper configuration
echo "Command: myth a --solc-json $CONFIG_FILE --solv $SOLC_VERSION -o $OUTPUT_FORMAT $CONTRACT_FILE" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"
echo "==========================================" >> "$LOG_FILE"

if timeout "$TIMEOUT" myth a \
    --solc-json "$CONFIG_FILE" \
    --solv "$SOLC_VERSION" \
    -o "$OUTPUT_FORMAT" \
    "$CONTRACT_FILE" 2>&1 | tee -a "$LOG_FILE"; then

    echo -e "${GREEN}Analysis completed successfully!${NC}"
    echo -e "${GREEN}Results saved to: $LOG_FILE${NC}"
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo -e "${YELLOW}Analysis timed out after $TIMEOUT seconds${NC}"
    else
        echo -e "${RED}Analysis failed with exit code: $EXIT_CODE${NC}"
    fi
    echo -e "${YELLOW}Partial results may be available in: $LOG_FILE${NC}"
fi

echo ""
echo -e "${YELLOW}Analysis Summary:${NC}"
echo "Contract: $CONTRACT_FILE"
echo "Log file: $LOG_FILE"
echo "Timestamp: $(date)"
