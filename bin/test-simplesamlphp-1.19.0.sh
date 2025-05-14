#!/bin/bash

###
# Test WP SAML Auth with SimpleSAMLphp 1.19.0 (vulnerable version)
# This script installs SimpleSAMLphp 1.19.0 and tests the security warnings and authentication blocking
###

set -ex

# Define the SimpleSAMLphp version to test
SIMPLESAMLPHP_VERSION="1.19.0"
echo "Testing with SimpleSAMLphp version $SIMPLESAMLPHP_VERSION (vulnerable version)"

# Create a temporary directory for testing
TEST_DIR="/tmp/wp-saml-auth-test-$SIMPLESAMLPHP_VERSION"
rm -rf $TEST_DIR
mkdir -p $TEST_DIR

# Download and extract SimpleSAMLphp
echo "Downloading SimpleSAMLphp $SIMPLESAMLPHP_VERSION"
wget https://github.com/simplesamlphp/simplesamlphp/releases/download/v$SIMPLESAMLPHP_VERSION/simplesamlphp-$SIMPLESAMLPHP_VERSION.tar.gz -O $TEST_DIR/simplesamlphp-$SIMPLESAMLPHP_VERSION.tar.gz
tar -zxvf $TEST_DIR/simplesamlphp-$SIMPLESAMLPHP_VERSION.tar.gz -C $TEST_DIR
mv $TEST_DIR/simplesamlphp-$SIMPLESAMLPHP_VERSION $TEST_DIR/simplesamlphp
rm $TEST_DIR/simplesamlphp-$SIMPLESAMLPHP_VERSION.tar.gz

# Copy SimpleSAMLphp to the plugin directory
echo "Copying SimpleSAMLphp to the plugin directory"
PLUGIN_DIR=$(pwd)
rm -rf $PLUGIN_DIR/simplesamlphp
cp -r $TEST_DIR/simplesamlphp $PLUGIN_DIR/

# Basic SimpleSAMLphp configuration
echo "Configuring SimpleSAMLphp"
cp $PLUGIN_DIR/bin/fixtures/config.php $PLUGIN_DIR/simplesamlphp/config/config.php
cp $PLUGIN_DIR/bin/fixtures/authsources.php $PLUGIN_DIR/simplesamlphp/config/authsources.php

# Generate a certificate SimpleSAMLphp uses for encryption
echo "Generating SSL certificate for SimpleSAMLphp"
openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes -out $PLUGIN_DIR/simplesamlphp/cert/saml.crt -keyout $PLUGIN_DIR/simplesamlphp/cert/saml.pem -batch

# Run the tests
echo "Running tests to verify security warnings and authentication blocking"
echo "Expected behavior:"
echo "- Critical error notice in admin"
echo "- Authentication blocked"
echo "- Settings page shows critical warning"
echo ""
echo "Please check the admin interface at http://localhost/wp-admin/ to verify the warnings"
echo "Please try to authenticate with SAML to verify authentication is blocked"
echo ""
echo "SimpleSAMLphp $SIMPLESAMLPHP_VERSION has been installed and configured."
