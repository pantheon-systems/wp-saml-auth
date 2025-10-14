#!/bin/bash
set -euo pipefail

echo "🚀 Preparing WordPress test environment (Manual Setup)..."

# 1. Ensure target directories exist and are clean
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}" || true
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# 2. Download WordPress core files
echo "Downloading WordPress core with wp-cli..."
wp core download --path="${WP_CORE_DIR}" --version=latest --locale=en_US --force

# 3. Download the WordPress PHPUnit test suite
echo "Downloading WordPress test suite with Subversion..."
WP_VERSION=$(wp core version --path="${WP_CORE_DIR}")
svn co --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn co --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit/data/" "${WP_TESTS_DIR}/data"

# 4. Create wp-tests-config.php with correct credentials
echo "Creating ${WP_TESTS_DIR}/wp-tests-config.php..."
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
// Database settings are sourced from env vars
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );
\$table_prefix = 'wptests_';

// Test environment settings
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'Test Blog' );
define( 'WPLANG', '' );

// Core settings
define( 'ABSPATH', '${WP_CORE_DIR}/' );
define( 'WP_DEBUG', true );
define( 'WP_PHP_BINARY', 'php' );
PHP

# 5. Create SimpleSAMLphp configuration for the test environment
echo "Creating SimpleSAMLphp test configuration..."
SSP_CONFIG_DIR="vendor/simplesamlphp/simplesamlphp/config"
SSP_METADATA_DIR="vendor/simplesamlphp/simplesamlphp/metadata"
mkdir -p "$SSP_CONFIG_DIR"
mkdir -p "$SSP_METADATA_DIR"

# Create config.php
cat > "$SSP_CONFIG_DIR/config.php" <<PHP
<?php
\$config = [
    'baseurlpath' => 'http://localhost/simplesaml/', 'certdir' => 'cert/',
    'loggingdir' => 'log/', 'datadir' => 'data/',
    'tempdir' => '/tmp/simplesaml', 'technicalcontact_name' => 'Administrator',
    'technicalcontact_email' => 'na@example.org', 'timezone' => 'UTC',
    'secretsalt' => 'defaultsecretsalt', 'auth.adminpassword' => 'admin',
    'admin.protectindexpage' => false, 'admin.protectmetadata' => false,
    'store.type' => 'phpsession',
];
PHP

# Create authsources.php
cat > "$SSP_CONFIG_DIR/authsources.php" <<PHP
<?php
\$config = [
    'default-sp' => [
        'saml:SP',
        'entityID' => 'wp-saml',
        'idp' => 'http://localhost/simplesaml/saml2/idp/metadata.php',
        'discoURL' => null,
    ],
];
PHP

# Create remote IdP metadata so the library can initialize
cat > "$SSP_METADATA_DIR/saml20-idp-remote.php" <<'PHP'
<?php
/**
 * SAML 2.0 IdP remote metadata for the tests.
 */
$metadata['http://localhost/simplesaml/saml2/idp/metadata.php'] = [
    'entityid' => 'http://localhost/simplesaml/saml2/idp/metadata.php',
    'SingleSignOnService' => [
        [
            'Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
            'Location' => 'http://localhost/simplesaml/saml2/idp/SSOService.php',
        ],
    ],
    'certFingerprint' => 'c99b251e63d86f2b7f00f860551a362b5b32f915',
];
PHP

# 6. Create a bootstrap file to load ALL autoloaders and the plugin itself.
if [ -d "tests/phpunit" ]; then
    echo "Creating PHPUnit bootstrap file..."
    cat > tests/phpunit/bootstrap.php <<'PHP'
<?php
/**
 * PHPUnit bootstrap file.
 */

// FIX: Set up a fake server environment for SimpleSAMLphp before it's loaded.
$_SERVER['SERVER_NAME'] = 'localhost';
$_SERVER['SERVER_PORT'] = 80;
$_SERVER['REQUEST_URI'] = '/';

// 1. Load the Composer autoloader.
require_once dirname( __DIR__, 2 ) . '/vendor/autoload.php';

// 2. Load the SimpleSAMLphp autoloader.
if ( file_exists( dirname( __DIR__, 2 ) . '/vendor/simplesamlphp/simplesamlphp/lib/_autoload.php' ) ) {
    require_once dirname( __DIR__, 2 ) . '/vendor/simplesamlphp/simplesamlphp/lib/_autoload.php';
}

// 3. Load the WordPress test functions.
require_once getenv( 'WP_TESTS_DIR' ) . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 */
function _manually_load_plugin() {
    require dirname( __DIR__, 2 ) . '/wp-saml-auth.php';
}
// Add a filter to load the plugin before the tests run.
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

// 5. Load the WordPress test environment.
require getenv( 'WP_TESTS_DIR' ) . '/includes/bootstrap.php';
PHP
else
    echo "Skipping bootstrap file creation: tests/phpunit directory not found."
fi

# 7. Ensure Composer dependencies are installed
echo "Installing Composer dependencies..."
composer install --prefer-dist --no-progress

echo "✅ Environment ready."
echo ""
echo "=========================================================================="
echo "Running PHPUnit Tests..."
echo "=========================================================================="

# 8. Run the tests
composer phpunit