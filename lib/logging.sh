#!/bin/bash
# Common logging functions for all scripts
# This library provides consistent logging across the codebase

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log info message
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

# Log warning message
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

# Log error message
log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Alternative print functions (for compatibility with existing scripts)
print_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

print_success() {
    echo -e "${GREEN}✓${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

print_error() {
    echo -e "${RED}✗${NC} $*"
}

# Print a header for sections
print_header() {
    local header="$1"
    local width=60
    local padding=$(( (width - ${#header}) / 2 ))
    
    echo ""
    echo "$(printf '%*s' $width | tr ' ' '=')"
    printf "%*s%s\n" $padding "" "$header"
    echo "$(printf '%*s' $width | tr ' ' '=')"
    echo ""
}
