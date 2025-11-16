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
#   ./tools.sh startServices
#   ./tools.sh testDeployment
#
# For full command reference:
#   swift run SwiftDeploy --help
# ============================================================================

# ============================================================================
# Deployment Commands
# ============================================================================

# Initial deployment: CDK infrastructure + Lambda code
# Usage:
#   freshDeploy                    # Minimal (no Postgres, no NAT)
#   freshDeploy --with-postgres    # Add database
#   freshDeploy --with-nat-gateway # Add NAT Gateway
function freshDeploy(){
  swift run SwiftDeploy fresh-deploy "$@"
}

# Update CDK infrastructure only (does NOT update Lambda code)
# Usage:
#   deploy                    # Minimal (no Postgres, no NAT)
#   deploy --with-postgres    # Add database
#   deploy --with-nat-gateway # Add NAT Gateway
function deploy(){
  swift run SwiftDeploy deploy "$@"
}

# Update Lambda code only (does NOT update infrastructure)
function updateLambda(){
  swift run SwiftDeploy update-lambda "$@"
}

# Tear down all infrastructure
function deployTearDown(){
  swift run SwiftDeploy tear-down "$@"
}

# Check deployment status
function deployStatus(){
  swift run SwiftDeploy status "$@"
}

# ============================================================================
# Local Development Commands
# ============================================================================

# Copy config file to home directory
function copyConfig(){
  swift run SwiftDeploy local copy-config
}

# Start all local services (PostgreSQL + MinIO)
function startServices(){
  swift run SwiftDeploy local start-services
}

# Stop all local services
function stopServices(){
  swift run SwiftDeploy local stop-services
}

# Start PostgreSQL database
function startDatabase(){
  swift run SwiftDeploy local start-database
}

# Stop PostgreSQL database
function stopDatabase(){
  swift run SwiftDeploy local stop-database
}

# Start MinIO S3 service
function startS3(){
  swift run SwiftDeploy local start-s3
}

# Stop MinIO S3 service
function stopS3(){
  swift run SwiftDeploy local stop-s3
}

# Setup Docker network for Lambda container testing
function setupLambdaNetwork(){
  swift run SwiftDeploy local setup-network
}

# Run Lambda in interactive Linux container
function runLambdaContainer(){
  swift run SwiftDeploy local run-container
}

# Test local Lambda endpoints
# Usage: testLocalLambda [port]
function testLocalLambda(){
  swift run SwiftDeploy local test "$@"
}

# ============================================================================
# AWS Testing Commands
# ============================================================================

# Get API Gateway URL from CloudFormation
function getApiGatewayUrl(){
  swift run SwiftDeploy test get-url
}

# Test S3 file endpoint on deployed Lambda
function testApiFile(){
  swift run SwiftDeploy test file
}

# Test S3 file endpoint with verbose curl output
function testApiFileVerbose(){
  swift run SwiftDeploy test file-verbose
}

# Verify S3 file was created and show content
function verifyS3File(){
  swift run SwiftDeploy test verify-s3
}

# Check Lambda execution logs (last 5 minutes)
function checkLambdaLogs(){
  swift run SwiftDeploy test logs --since 5m
}

# Run all deployment verification tests
function testDeployment(){
  swift run SwiftDeploy test all
}

# ============================================================================
# Legacy Functions (Deprecated - use SwiftDeploy commands instead)
# ============================================================================

# DEPRECATED: Use swift run SwiftDeploy local run-lambda instead
# Run Lambda locally with local server mode
# Usage: runLocalLambda [port] [background]
function runLocalLambda(){
  echo "⚠️  DEPRECATED: This function is deprecated."
  echo "   Use: swift run SwiftLambda directly for local development"
  echo "   Or use Xcode (⌘R) for debugging"
  echo ""

  local port=${1:-8080}
  local bg_mode=${2:-}

  echo "🚀 Starting Lambda locally on port $port..."

  if [ "$bg_mode" = "bg" ]; then
    # Check if binary exists, if not try to build
    if [ ! -f ./.build/debug/SwiftLambda ]; then
      echo "→ Building Lambda..."
      swift build --product SwiftLambda > /dev/null 2>&1 || {
        echo "❌ Build failed. Binary not found. Try running: swift build --product SwiftLambda"
        return 1
      }
    else
      echo "→ Using existing Lambda binary"
    fi

    # Run the pre-built binary
    LOCAL_LAMBDA_SERVER_ENABLED=true \
    MOCK_AWS_CREDENTIALS=true \
    LOCAL_LAMBDA_PORT=$port \
    ./.build/debug/SwiftLambda > /tmp/lambda_local_$port.log 2>&1 &

    local lambda_pid=$!
    echo "→ Lambda started in background (PID: $lambda_pid)"
    echo "→ Logs: /tmp/lambda_local_$port.log"

    echo "✅ Lambda started in background"
    echo "   Run './tools.sh waitForLambda $port' to wait for it to be ready"
    return 0
  else
    LOCAL_LAMBDA_SERVER_ENABLED=true \
    MOCK_AWS_CREDENTIALS=true \
    LOCAL_LAMBDA_PORT=$port \
    swift run SwiftLambda
  fi
}

# Wait for local Lambda to be ready on specified port
function waitForLambda(){
  local port=${1:-8080}

  echo "⏳ Waiting for Lambda on port $port to be ready..."
  local max_attempts=120  # 2 minutes
  local attempt=0
  while [ $attempt -lt $max_attempts ]; do
    if lsof -i :$port > /dev/null 2>&1; then
      echo "✅ Lambda is ready on port $port"
      return 0
    fi

    # Show progress every 10 seconds
    if [ $((attempt % 10)) -eq 0 ] && [ $attempt -gt 0 ]; then
      echo "   Still waiting... ($attempt seconds elapsed)"
    fi

    sleep 1
    attempt=$((attempt + 1))
  done

  echo "❌ Lambda failed to start within $max_attempts seconds"
  echo "   Check logs: /tmp/lambda_local_$port.log"
  return 1
}

# Stop local Lambda running on specified port
function stopLocalLambda(){
  local port=${1:-8080}

  echo "🛑 Stopping Lambda on port $port..."

  local pids=$(lsof -t -i :$port 2>/dev/null || true)

  if [ -z "$pids" ]; then
    echo "→ No Lambda process found on port $port"
    return 0
  fi

  echo "$pids" | while read -r pid; do
    echo "→ Killing process $pid"
    kill "$pid" 2>/dev/null || true
  done

  sleep 2

  # Force kill if still running
  pids=$(lsof -t -i :$port 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "→ Force killing remaining processes..."
    echo "$pids" | while read -r pid; do
      kill -9 "$pid" 2>/dev/null || true
    done
  fi

  echo "✅ Lambda stopped"
}

# DEPRECATED: Use AWS CLI directly
# Tail Lambda logs (production)
function tailLogs(){
  echo "⚠️  DEPRECATED: Use checkLambdaLogs instead"
  echo ""

  export AWS_PROFILE="production";
  groupPrefix="Sugar"

  group="$(aws logs  describe-log-groups --log-group-name-prefix "/aws/lambda/$groupPrefix" | jq -r  ".logGroups[0].logGroupName")";
  aws logs tail "$group" --follow
}

# Kill local server on port 7000
function killServer(){
  # Use lsof to find processes that are listening on localhost port 7000
  PIDS=$(lsof -i :7000 | grep "TCP localhost" | awk '{print $2}')

  if [ -z "$PIDS" ]; then
      echo "No processes found on localhost port 7000."
  else
      # Use a while loop to read each line (PID) and kill the process
      echo "$PIDS" | while read -r PID; do
          echo "Killing process with PID: $PID on localhost port 7000"
          kill "$PID"
      done
  fi
}

# Start DynamoDB local (not currently used)
function startDynamoDB(){
  docker run -p 8000:8000 amazon/dynamodb-local
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
  echo "All logic is implemented in SwiftDeploy (Swift CLI tool)."
  echo "This script provides short aliases for common commands."
  echo ""
  echo "📚 Full Documentation:"
  echo "   swift run SwiftDeploy --help"
  echo ""
  echo "🚀 Deployment Commands:"
  echo "   freshDeploy [--with-postgres] [--with-nat-gateway]"
  echo "   deploy [--with-postgres] [--with-nat-gateway]"
  echo "   updateLambda"
  echo "   deployStatus"
  echo "   deployTearDown"
  echo ""
  echo "🔧 Local Development Commands:"
  echo "   copyConfig              - Copy config to ~/.swiftSampleDemo/"
  echo "   startServices           - Start PostgreSQL + MinIO"
  echo "   stopServices            - Stop all services"
  echo "   startDatabase           - Start PostgreSQL only"
  echo "   stopDatabase            - Stop PostgreSQL only"
  echo "   startS3                 - Start MinIO only"
  echo "   stopS3                  - Stop MinIO only"
  echo "   setupLambdaNetwork      - Setup Docker network"
  echo "   runLambdaContainer      - Run Lambda in Linux container"
  echo "   testLocalLambda [port]  - Test local Lambda"
  echo ""
  echo "☁️  AWS Testing Commands:"
  echo "   testDeployment          - Run all verification tests"
  echo "   testApiFile             - Test S3 file endpoint"
  echo "   testApiFileVerbose      - Test with verbose output"
  echo "   verifyS3File            - Verify S3 file creation"
  echo "   checkLambdaLogs         - Show Lambda logs (5 min)"
  echo "   getApiGatewayUrl        - Get API Gateway URL"
  echo ""
  echo "Available Functions:"
  typeset -f | awk '!/^main[ (]/ && /^[^ {}]+ *\(\)/ { gsub(/[()]/, "", $1); print "  - " $1}'
  exit 1
fi
