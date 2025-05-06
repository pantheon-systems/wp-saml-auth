#!/bin/bash

###
# Test WP SAML Auth with all three SimpleSAMLphp versions
# This script runs all three test scripts in sequence
###

set -ex

# Make all test scripts executable
chmod +x bin/test-simplesamlphp-1.19.0.sh
chmod +x bin/test-simplesamlphp-2.0.0.sh
chmod +x bin/test-simplesamlphp-2.3.7.sh

# Run unit tests first
echo "Running unit tests..."
./vendor/bin/phpunit

# Test with SimpleSAMLphp 1.19.0 (vulnerable version)
echo "==================================================================="
echo "Testing with SimpleSAMLphp 1.19.0 (vulnerable version)"
echo "==================================================================="
./bin/test-simplesamlphp-1.19.0.sh

# Pause for manual verification
echo "Press Enter to continue to the next test..."
read

# Test with SimpleSAMLphp 2.0.0 (secure but not recommended version)
echo "==================================================================="
echo "Testing with SimpleSAMLphp 2.0.0 (secure but not recommended version)"
echo "==================================================================="
./bin/test-simplesamlphp-2.0.0.sh

# Pause for manual verification
echo "Press Enter to continue to the next test..."
read

# Test with SimpleSAMLphp 2.3.7 (recommended version)
echo "==================================================================="
echo "Testing with SimpleSAMLphp 2.3.7 (recommended version)"
echo "==================================================================="
./bin/test-simplesamlphp-2.3.7.sh

echo "==================================================================="
echo "All tests completed!"
echo "==================================================================="
echo "Please verify the behavior for each version according to the testing guide:"
echo ""
echo "1. Vulnerable Version (< 2.0.0)"
echo "   - Critical error notice in admin"
echo "   - Authentication blocked"
echo "   - Settings page shows critical warning"
echo ""
echo "2. Secure but Not Recommended (>= 2.0.0, < 2.3.7)"
echo "   - Warning notice in admin"
echo "   - Authentication allowed"
echo "   - Settings page shows recommendation warning"
echo ""
echo "3. Recommended Version (>= 2.3.7)"
echo "   - No warnings"
echo "   - Authentication allowed"
echo "   - Settings page shows no warnings"
