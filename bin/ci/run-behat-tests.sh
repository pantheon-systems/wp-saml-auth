#!/bin/bash
set -euo pipefail

# Check if a version argument was provided
if [ -z "$1" ]; then
  echo "Error: SimpleSAMLphp version must be provided as the first argument."
  exit 1
fi

SIMPLESAMLPHP_VERSION="$1"

echo ""
echo "=========================================================================="
echo "Running Behat on https://${SITE_ENV}.pantheonsite.io/wp-login.php"
echo "with SimpleSAMLphp version ${SIMPLESAMLPHP_VERSION}"
echo "=========================================================================="
echo ""

# Prepare fixture environment for tests based on version.
if [ "${SIMPLESAMLPHP_VERSION}" != "1.18.0" ]; then
  ./bin/behat-prepare.sh
else
  # Use the specific script for the older version
  ./bin/1.18/behat-prepare-simplesaml1.18.0.sh
fi

# Run the tests
./bin/behat-test.sh --strict
