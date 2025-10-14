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

# 5. Create a bootstrap file to load the Composer autoloader
#    This is the critical step to make PHPUnit aware of your project's classes.
if [ -d "tests/phpunit" ]; then
    echo "Creating PHPUnit bootstrap file..."
    cat > tests/phpunit/bootstrap.php <<PHP
<?php
/**
 * PHPUnit bootstrap file.
 */

// 1. Load the Composer autoloader.
require_once dirname( __DIR__, 2 ) . '/vendor/autoload.php';

// 2. Load the WordPress test environment's bootstrap file.
require_once getenv( 'WP_TESTS_DIR' ) . '/includes/bootstrap.php';
PHP
else
    echo "Skipping bootstrap file creation: tests/phpunit directory not found."
fi


# 6. Ensure Composer dependencies are installed
echo "Installing Composer dependencies..."
composer install --prefer-dist --no-progress

echo "✅ Environment ready."
echo ""
echo "=========================================================================="
echo "Running PHPUnit Tests..."
echo "=========================================================================="

# 7. Run the tests
composer phpunit