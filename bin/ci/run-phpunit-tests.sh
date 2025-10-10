#!/bin/bash
set -euo pipefail

echo "🚀 Preparing WordPress test environment..."

# Ensure target directories exist and are clean
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}" || true
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# 1. Install WordPress Core & Test Suite via composer script
# We run this first but allow it to fail, as we will self-heal below.
echo "Attempting to install WP test suite via 'composer test:install'..."
timeout 8m composer test:install || echo "Composer install script failed or timed out. Proceeding with manual setup..."

# 2. Ensure WordPress core files are present
if [ ! -f "${WP_CORE_DIR}/wp-includes/version.php" ]; then
  echo "WordPress core not found; downloading with wp-cli..."
  wp core download --path="${WP_CORE_DIR}" --version=latest --locale=en_US --force
fi

# 3. Force-create or update wp-config.php with correct DB constants
echo "Configuring ${WP_CORE_DIR}/wp-config.php..."
wp config create --path="${WP_CORE_DIR}" \
  --dbname="${DB_NAME}" --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" --dbhost="${DB_HOST}" \
  --skip-check --force

# Sanity check: ensure wp-cli can connect to the database now
echo "Checking DB connection with wp-cli..."
wp --path="${WP_CORE_DIR}" db check

# 4. Ensure the WordPress PHPUnit test suite is present
if [ ! -f "${WP_TESTS_DIR}/includes/functions.php" ]; then
  echo "WordPress test suite not found; downloading with Subversion..."
  WP_VERSION=$(wp core version --path="${WP_CORE_DIR}" 2>/dev/null || echo "trunk")
  SVN_BASE="https://develop.svn.wordpress.org"
  SVN_PATH="${SVN_BASE}/tags/${WP_VERSION}"

  # Check if the tag exists; if not, fall back to trunk
  if ! svn ls "${SVN_PATH}/" >/dev/null 2>&1; then
    echo "Tag ${WP_VERSION} not found on SVN; using trunk for tests."
    SVN_PATH="${SVN_BASE}/trunk"
  fi

  echo "Fetching test suite from ${SVN_PATH}..."
  svn co --quiet "${SVN_PATH}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
  svn co --quiet "${SVN_PATH}/tests/phpunit/data/" "${WP_TESTS_DIR}/data"
fi

# 5. Ensure wp-tests-config.php exists and is configured correctly
echo "Creating ${WP_TESTS_DIR}/wp-tests-config.php..."
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
// Database settings
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

echo "✅ Environment ready."
echo ""
echo "=========================================================================="
echo "Running PHPUnit Tests..."
echo "=========================================================================="
composer phpunit
