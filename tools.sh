#!/bin/zsh

set -eu
set -o errexit
set -o pipefail
set -o nounset

# ============================================================================
# tools.sh - Convenience wrapper for SwiftDeploy CLI
# ============================================================================
#
# This script provides short aliases for common SwiftDeploy commands.
# All logic is implemented in the SwiftDeploy Swift CLI tool.
#
# Usage:
#   ./tools.sh <function-name> [args]
#
# Examples:
#   ./tools.sh deploy --with-postgres
#   ./tools.sh local-start-all
#   ./tools.sh aws-test-all
#
# For full command reference:
#   swift run SwiftDeploy --help
# ============================================================================

# ============================================================================
# AWS Deployment Commands
# ============================================================================

# Initial deployment: CDK infrastructure + Lambda code
function aws-fresh-deploy(){
  swift run SwiftDeploy fresh-deploy "$@"
}

# Update CDK infrastructure only (does NOT update Lambda code)
function aws-deploy(){
  swift run SwiftDeploy deploy "$@"
}

# Update Lambda code only (does NOT update infrastructure)
function aws-update-lambda(){
  swift run SwiftDeploy update-lambda "$@"
}

# Tear down all infrastructure
function aws-tear-down(){
  swift run SwiftDeploy tear-down "$@"
}

# Check deployment status
function aws-status(){
  swift run SwiftDeploy status "$@"
}

# Show Lambda CloudWatch logs
function aws-logs(){
  swift run SwiftDeploy test logs "$@"
}

# Get API Gateway URL from CloudFormation
function aws-get-url(){
  swift run SwiftDeploy test get-url
}

# ============================================================================
# AWS Testing Commands
# ============================================================================

# Run all deployment verification tests
function aws-test(){
  swift run SwiftDeploy test all
}

# Test S3 file endpoint on deployed Lambda
function aws-test-file(){
  swift run SwiftDeploy test file
}

# Test S3 file endpoint with verbose curl output
function aws-test-file-verbose(){
  swift run SwiftDeploy test file-verbose
}

# Verify S3 file was created and show content
function aws-verify-s3(){
  swift run SwiftDeploy test verify-s3
}

# ============================================================================
# Local Development Commands
# ============================================================================

# Copy config file to home directory
function local-copy-config(){
  swift run SwiftDeploy local copy-config
}

# Start all local services (PostgreSQL + MinIO)
function local-start-all(){
  swift run SwiftDeploy local start-services
}

# Stop all local services
function local-stop-all(){
  swift run SwiftDeploy local stop-services
}

# Start PostgreSQL database
function local-start-db(){
  swift run SwiftDeploy local start-database
}

# Stop PostgreSQL database
function local-stop-db(){
  swift run SwiftDeploy local stop-database
}

# Start MinIO S3 service
function local-start-s3(){
  swift run SwiftDeploy local start-s3
}

# Stop MinIO S3 service
function local-stop-s3(){
  swift run SwiftDeploy local stop-s3
}

# Setup Docker network for Lambda container testing
function local-setup-network(){
  swift run SwiftDeploy local setup-network
}

# Run Lambda in interactive Linux container
function local-run-container(){
  swift run SwiftDeploy local run-container
}

# Test local Lambda endpoints
function local-test(){
  swift run SwiftDeploy local test "$@"
}

# ============================================================================
# Main Entry Point
# ============================================================================

# Check if function exists and execute it
if [ $# -gt 0 ]; then
  "$@"
else
  # Show available functions
  echo "============================================================================"
  echo "SwiftDeploy CLI - Convenience Wrapper"
  echo "============================================================================"
  echo ""
  echo "🚀 AWS Deployment:"
  echo "   aws-fresh-deploy    - Initial deployment (CDK + Lambda)"
  echo "   aws-deploy          - Update infrastructure only"
  echo "   aws-update-lambda   - Update Lambda code only"
  echo "   aws-tear-down       - Destroy all infrastructure"
  echo "   aws-status          - Check deployment status"
  echo "   aws-logs [--since]  - Show Lambda CloudWatch logs"
  echo "   aws-get-url         - Get API Gateway URL"
  echo ""
  echo "☁️  AWS Testing:"
  echo "   aws-test            - Run all verification tests"
  echo "   aws-test-file       - Test S3 file endpoint"
  echo "   aws-test-file-verbose - Test with verbose output"
  echo "   aws-verify-s3       - Verify S3 file was created"
  echo ""
  echo "🔧 Local Development:"
  echo "   local-start-all     - Start PostgreSQL + MinIO"
  echo "   local-stop-all      - Stop all services"
  echo "   local-start-db      - Start PostgreSQL only"
  echo "   local-stop-db       - Stop PostgreSQL only"
  echo "   local-start-s3      - Start MinIO only"
  echo "   local-stop-s3       - Stop MinIO only"
  echo "   local-run-container - Run Lambda in Linux container"
  echo "   local-test [port]   - Test local Lambda endpoints"
  echo "   local-copy-config   - Copy config files"
  echo "   local-setup-network - Setup Docker network"
  echo ""
  echo "📖 Full Documentation:"
  echo "   swift run SwiftDeploy --help"
  exit 1
fi
