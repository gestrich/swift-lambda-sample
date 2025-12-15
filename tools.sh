#!/bin/zsh

set -eu
set -o errexit
set -o pipefail
set -o nounset

# ============================================================================
# tools.sh - Thin wrapper for feature-deploy-cli
# ============================================================================
#
# This script is a simple delegator that passes all arguments directly to
# the feature-deploy-cli tool. It provides a shorter command prefix for
# convenience: ./tools.sh instead of swift run feature-deploy-cli
#
# Usage:
#   ./tools.sh [command] [args...]
#
# Examples:
#   ./tools.sh aws deploy
#   ./tools.sh aws fresh-deploy --with-postgres
#   ./tools.sh local services start-all
#   ./tools.sh aws test all
#
# For help:
#   ./tools.sh --help
#   ./tools.sh aws --help
#   ./tools.sh local --help
# ============================================================================

# Pass all arguments directly to feature-deploy-cli
swift run feature-deploy-cli "$@"
