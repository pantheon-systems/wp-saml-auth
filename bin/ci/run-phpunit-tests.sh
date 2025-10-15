#!/bin/bash
set -euo pipefail

echo "🚀 Preparing WordPress test environment (Manual Setup)..."

# 1. Create directories
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}" || true
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# 2. Download WordPress and the test suite
echo "Downloading WordPress core & test suite..."
wp core download --path="${WP_CORE_DIR}" --version=latest --locale=en_US --force
WP_VERSION=$(wp core version --path="${WP_CORE_DIR}")
svn co --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn co --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit/data/" "${WP_TESTS_DIR}/data"

# 3. Create wp-tests-config.php
echo "Creating ${WP_TESTS_DIR}/wp-tests-config.php..."
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );
\$table_prefix = 'wptests_';
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'Test Blog' );
define( 'WPLANG', '' );
define( 'ABSPATH', '${WP_CORE_DIR}/' );
define( 'WP_DEBUG', true );
define( 'WP_PHP_BINARY', 'php' );
PHP

# 4. Create an ISOLATED SimpleSAMLphp configuration
echo "Creating isolated SimpleSAMLphp test configuration..."
SSP_TEMP_CONFIG_DIR="/tmp/simplesamlphp-config"
rm -rf "$SSP_TEMP_CONFIG_DIR" # Ensure it's clean on every run
SSP_METADATA_DIR="$SSP_TEMP_CONFIG_DIR/metadata"
mkdir -p "$SSP_TEMP_CONFIG_DIR" "$SSP_METADATA_DIR"

cat > "$SSP_TEMP_CONFIG_DIR/config.php" <<PHP
<?php
\$config = [
    'baseurlpath' => 'https://localhost/simplesaml/', 'certdir' => 'cert/',
    'loggingdir' => 'log/', 'datadir' => 'data/', 'tempdir' => '/tmp/simplesaml',
    'technicalcontact_name' => 'Admin', 'technicalcontact_email' => 'na@example.org',
    'timezone' => 'UTC', 'secretsalt' => 'defaultsecretsalt',
    'auth.adminpassword' => 'admin', 'admin.protectindexpage' => false,
    'admin.protectmetadata' => false, 'store.type' => 'phpsession',
];
PHP

cat > "$SSP_TEMP_CONFIG_DIR/authsources.php" <<PHP
<?php
\$config = [ 'default-sp' => [
    'saml:SP', 'entityID' => 'wp-saml',
    'idp' => 'https://localhost/simplesaml/saml2/idp/metadata.php', 'discoURL' => null,
]];
PHP

cat > "$SSP_METADATA_DIR/saml20-idp-remote.php" <<'PHP'
<?php
$metadata['https://localhost/simplesaml/saml2/idp/metadata.php'] = [
    'entityid' => 'https://localhost/simplesaml/saml2/idp/metadata.php',
    'SingleSignOnService' => [
        ['Binding' => 'urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect',
         'Location' => 'https://localhost/simplesaml/saml2/idp/SSOService.php'],
    ],
    'certFingerprint' => 'c99b251e63d86f2b7f00f860551a362b5b32f915',
];
PHP

# 5. Create the PHPUnit bootstrap file with a more complete server mock
if [ -d "tests/phpunit" ]; then
    echo "Creating PHPUnit bootstrap file..."
    cat > tests/phpunit/bootstrap.php <<'PHP'
<?php
/**
 * PHPUnit bootstrap file.
 */

// FIX: Create a more complete fake server environment before any other code loads.
$_SERVER['SERVER_NAME']      = 'localhost';
$_SERVER['HTTP_HOST']        = 'localhost';
$_SERVER['SERVER_PORT']      = 443;
$_SERVER['REQUEST_URI']      = '/';
$_SERVER['HTTPS']            = 'on';
$_SERVER['SCRIPT_NAME']      = '/index.php';
$_SERVER['PHP_SELF']         = '/index.php';
$_SERVER['SCRIPT_FILENAME']  = '/var/www/html/index.php';

// 1. Load Composer and SimpleSAMLphp autoloaders.
require_once dirname( __DIR__, 2 ) . '/vendor/autoload.php';
if ( file_exists( dirname( __DIR__, 2 ) . '/vendor/simplesamlphp/simplesamlphp/lib/_autoload.php' ) ) {
    require_once dirname( __DIR__, 2 ) . '/vendor/simplesamlphp/simplesamlphp/lib/_autoload.php';
}

// 2. Load WordPress test environment.
require_once getenv( 'WP_TESTS_DIR' ) . '/includes/functions.php';
function _manually_load_plugin() {
    require dirname( __DIR__, 2 ) . '/wp-saml-auth.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );
require getenv( 'WP_TESTS_DIR' ) . '/includes/bootstrap.php';
PHP
else
    echo "Skipping bootstrap file creation: tests/phpunit directory not found."
fi

# 6. Install dependencies
echo "Installing Composer dependencies..."
composer install --prefer-dist --no-progress

echo "✅ Environment ready."
echo ""
echo "=========================================================================="
echo "Running PHPUnit Tests..."
echo "=========================================================================="

# 7. Run the tests
# Point SimpleSAMLphp to the isolated, non-cached config directory.
export SIMPLESAMLPHP_CONFIG_DIR="$SSP_TEMP_CONFIG_DIR"
composer phpunit
