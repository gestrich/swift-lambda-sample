#!/bin/bash

set -eu
set -o errexit
set -o pipefail
set -o nounset

# Cleanup function to always remove netrc file
cleanup() {
    rm -f netrc 2>/dev/null || true
}
trap cleanup EXIT

# Check parameters
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <build target name> [platform name] [github token]"
    echo ""
    echo "  build target name: Required (e.g., SwiftLambda)"
    echo "  platform name: Optional, defaults to linux/amd64 (matches AWS Lambda x86_64)"
    echo "  github token: Optional, only needed if you have private dependencies"
    echo ""
    echo "Examples:"
    echo "  $0 SwiftLambda"
    echo "  $0 SwiftLambda linux/amd64"
    echo "  $0 SwiftLambda linux/amd64 your-github-token"
    exit 1
fi

PRODUCT="$1"
# Default to linux/amd64 to match AWS Lambda configuration
PLATFORM_NAME="${2:-linux/amd64}"
GITHUB_TOKEN="${3:-dummy}"

echo "========================================="
echo "Building $PRODUCT for platform $PLATFORM_NAME"
echo "AWS Lambda Architecture: x86_64 (amd64)"
if [[ "$PLATFORM_NAME" != "linux/amd64" ]]; then
    echo "⚠️  WARNING: Platform $PLATFORM_NAME may not be compatible with your AWS Lambda!"
    echo "⚠️  Your Lambda is configured for linux/amd64 (x86_64)"
fi
echo "========================================="
echo ""

# Clean up any previous build artifacts
echo "Cleaning up previous build artifacts..."
rm -f lambda.zip 2>/dev/null || true
rm -rf lambda 2>/dev/null || true
rm -f netrc 2>/dev/null || true

# Write Github Token to a Netrc file
./appendNetrc.sh netrc "github.com" user "$GITHUB_TOKEN"
./appendNetrc.sh netrc "api.github.com" user "$GITHUB_TOKEN"

BUILD_DIR=$(pwd)/.aws-sam/build-$PRODUCT

# Build docker image - fetches source dependent swift packages too.
echo "Building Docker image..."
DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 docker build --platform $PLATFORM_NAME --progress=plain --ulimit nofile=65536:65536 --secret id=netrc,src=netrc -f Dockerfile . -t builder

# Clear the .build directory
echo "Clearing build directory..."
# First try normal rm, if that fails use Docker to clean up (handles permission issues on Mac)
if ! rm -rf $BUILD_DIR 2>/dev/null; then
    echo "Using Docker to clean up build directory (permission issues)..."
    docker run --platform $PLATFORM_NAME --rm -v $(pwd)/.aws-sam:/aws-sam -w /aws-sam builder bash -c "rm -rf build-$PRODUCT" || true
fi
# Ensure directory is gone
rm -rf $BUILD_DIR 2>/dev/null || true

# Copy from Docker to build directory
echo "Copying dependencies from Docker..."
# The -p flag preserves permissions but creates parent directories as needed
# The || true allows continuing even if some files already exist or have warnings
docker run --platform $PLATFORM_NAME --rm -v $BUILD_DIR:/build-target -w /build-src builder bash -c "cp -R -n -p /stage/.build/* /build-target 2>/dev/null || echo 'Some copy warnings (normal)'"

# Fix file permissions - Swift needs write access to build files
echo "Fixing file permissions..."
chmod -R u+w $BUILD_DIR 2>/dev/null || true

# Prep local directories
echo "Preparing lambda directory..."
# Try with sudo first (for GitHub Actions), fall back to regular mkdir (for Mac)
if ! mkdir -p $BUILD_DIR/lambda 2>/dev/null; then
    sudo mkdir -p $BUILD_DIR/lambda
fi

# Compile application
echo "Compiling application..."
docker run --platform $PLATFORM_NAME --rm -v $BUILD_DIR:/build-target -v $(pwd):/build-src -w /build-src builder bash -c "swift build --product $PRODUCT -c release --build-path /build-target --disable-automatic-resolution"

# Copy swift dependencies
echo "Copying Swift dependencies..."
docker run --platform $PLATFORM_NAME --rm -v $BUILD_DIR:/build-target -v $(pwd):/build-src -w /build-src builder bash -c "ldd '/build-target/release/$PRODUCT' | grep swift | cut -d' ' -f3 | xargs cp -Lv -t /build-target/lambda"

# Strip debug symbols from binary
echo "Stripping debug symbols from binary..."
docker run --platform $PLATFORM_NAME --rm -v $BUILD_DIR:/build-target builder bash -c "strip /build-target/release/$PRODUCT"

# Copy binary to stage
echo "Copying binary to lambda directory..."
# Try with sudo first (for GitHub Actions), fall back to regular cp (for Mac)
if ! cp $BUILD_DIR/release/$PRODUCT $BUILD_DIR/lambda/bootstrap 2>/dev/null; then
    sudo cp $BUILD_DIR/release/$PRODUCT $BUILD_DIR/lambda/bootstrap
fi

echo ""
echo "Lambda package contents:"
echo "========================"
ls -lh $BUILD_DIR/lambda/ | awk 'NR>1 {printf "  %-50s %10s\n", $9, $5}'
TOTAL_UNCOMPRESSED=$(du -sh $BUILD_DIR/lambda/ | awk '{print $1}')
echo "  ------------------------------------------------"
echo "  Total uncompressed size: $TOTAL_UNCOMPRESSED"
echo ""

echo "Packaging to zip..."
zip --symlinks -j lambda.zip $BUILD_DIR/lambda/*

echo ""
echo "Lambda package size:"
echo "===================="
LAMBDA_ZIP_SIZE=$(ls -lh lambda.zip | awk '{print $5}')
# Try Mac stat first, then Linux stat
LAMBDA_ZIP_BYTES=$(stat -f%z lambda.zip 2>/dev/null || stat -c%s lambda.zip 2>/dev/null)
LAMBDA_LIMIT_BYTES=52428800  # 50 MB in bytes
LAMBDA_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($LAMBDA_ZIP_BYTES / $LAMBDA_LIMIT_BYTES) * 100}")

echo "  lambda.zip: $LAMBDA_ZIP_SIZE ($LAMBDA_ZIP_BYTES bytes)"
echo "  AWS Lambda limit: 50 MB (52428800 bytes)"
echo "  Usage: ${LAMBDA_PERCENT}%"

if [ "$LAMBDA_ZIP_BYTES" -gt "$LAMBDA_LIMIT_BYTES" ]; then
    echo ""
    echo "  ❌ ERROR: Package exceeds AWS Lambda 50MB limit!"
    echo "  Consider using Lambda layers or S3 deployment."
    exit 1
elif [ "$LAMBDA_ZIP_BYTES" -gt $((LAMBDA_LIMIT_BYTES * 80 / 100)) ]; then
    echo "  ⚠️  WARNING: Package is over 80% of AWS Lambda limit"
else
    echo "  ✅ Package size is within AWS Lambda limits"
fi
echo ""

echo "Copying build directory for artifacts..."
cp -r $BUILD_DIR/lambda lambda

echo ""
echo "✅ Build complete!"
echo "Lambda package: $(pwd)/lambda.zip"
echo "Lambda directory: $(pwd)/lambda"
echo ""
echo "To deploy to AWS Lambda:"
echo "  aws lambda update-function-code --function-name swift-lambda-sample --zip-file fileb://lambda.zip --profile production"
echo ""
