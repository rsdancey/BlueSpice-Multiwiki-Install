#!/bin/bash
# Common logging functions for all scripts
# This library provides consistent logging across the codebase

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
# shellcheck disable=SC2034  # May be used by external scripts
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
