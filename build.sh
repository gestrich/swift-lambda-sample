#!/bin/bash

set -eu
set -o errexit
set -o pipefail
set -o nounset

# Check parameters
if [ "$#" -ne 3 ]; then
    echo "Usage: <build target name> <platform name> <github token>"
    exit 1
fi

PRODUCT="$1"
PLATFORM_NAME="$2"
GITHUB_TOKEN="$3"

# Write Github Token to a Netrc file
./appendNetrc.sh netrc "github.com" user "$GITHUB_TOKEN"
./appendNetrc.sh netrc "api.github.com" user "$GITHUB_TOKEN"

BUILD_DIR=$(pwd)/.aws-sam/build-$PRODUCT

# Build docker image - fetches source dependent swift packages too.
DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 docker build --platform $PLATFORM_NAME --progress=plain --ulimit nofile=65536:65536 --secret id=netrc,src=netrc -f Dockerfile . -t builder

# Clear the .build directory
rm -rf $BUILD_DIR

# Copy from Docker to build directory
# The || was added for this strange error: cp: cannot create directory '/build-target/checkouts/soto/models/apis/guardduty': File exists
docker run --platform $PLATFORM_NAME --rm -v $BUILD_DIR:/build-target -w /build-src builder bash -c "cp -R -n -p /stage/.build/* /build-target || echo 'error'"

# Prep local directories
sudo mkdir -p $BUILD_DIR/lambda

# Compile application
docker run --platform $PLATFORM_NAME --rm -v $BUILD_DIR:/build-target -v $(pwd):/build-src -w /build-src builder bash -c "swift build --product $PRODUCT -c release --build-path /build-target --skip-update --disable-automatic-resolution"

# Copy swift dependencies
docker run --platform $PLATFORM_NAME --rm -v $BUILD_DIR:/build-target -v $(pwd):/build-src -w /build-src builder bash -c "ldd '/build-target/release/$PRODUCT' | grep swift | cut -d' ' -f3 | xargs cp -Lv -t /build-target/lambda"

# Copy binary to stage
sudo cp $BUILD_DIR/release/$PRODUCT $BUILD_DIR/lambda/bootstrap

echo ""
echo "Lambda package contents:"
echo "========================"
ls -lh $BUILD_DIR/lambda/ | awk 'NR>1 {printf "  %-50s %10s\n", $9, $5}'
TOTAL_UNCOMPRESSED=$(du -sh $BUILD_DIR/lambda/ | awk '{print $1}')
echo "  ------------------------------------------------"
echo "  Total uncompressed size: $TOTAL_UNCOMPRESSED"
echo ""

echo "Packaging to zip"
zip --symlinks -j lambda.zip $BUILD_DIR/lambda/*

echo ""
echo "Lambda package size:"
echo "===================="
LAMBDA_ZIP_SIZE=$(ls -lh lambda.zip | awk '{print $5}')
LAMBDA_ZIP_BYTES=$(stat -c%s lambda.zip 2>/dev/null || stat -f%z lambda.zip 2>/dev/null)
LAMBDA_LIMIT_BYTES=52428800  # 50 MB in bytes
LAMBDA_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($LAMBDA_ZIP_BYTES / $LAMBDA_LIMIT_BYTES) * 100}")

echo "  lambda.zip: $LAMBDA_ZIP_SIZE ($LAMBDA_ZIP_BYTES bytes)"
echo "  AWS Lambda limit: 50 MB (52428800 bytes)"
echo "  Usage: ${LAMBDA_PERCENT}%"

if [ "$LAMBDA_ZIP_BYTES" -gt "$LAMBDA_LIMIT_BYTES" ]; then
    echo ""
    echo "  ERROR: Package exceeds AWS Lambda 50MB limit!"
    echo "  Consider using Lambda layers or S3 deployment."
    exit 1
elif [ "$LAMBDA_ZIP_BYTES" -gt $((LAMBDA_LIMIT_BYTES * 80 / 100)) ]; then
    echo "  WARNING: Package is over 80% of AWS Lambda limit"
else
    echo "  Package size is within AWS Lambda limits"
fi
echo ""

echo "Copy build directory to directory for Github action artifacts to upload"
cp -r $BUILD_DIR/lambda lambda
