#!/bin/bash
set -euo pipefail

echo " Preparing WordPress test environment..."

# Ensure target directories exist and are clean
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}" || true
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

# --- FIX IS HERE ---
# Create the config file FIRST. The install script will find and use it.
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

# 1. Install WordPress Core & Test Suite via composer script
# This should now succeed because the config file provides the DB credentials.
echo "Attempting to install WP test suite via 'composer test:install'..."
if ! timeout 8m composer test:install; then
  echo "Composer install script failed or timed out. Proceeding with manual setup..."

  # 2. Fallback: Ensure WordPress core files are present
  if [ ! -f "${WP_CORE_DIR}/wp-includes/version.php" ]; then
    echo "WordPress core not found; downloading with wp-cli..."
    wp core download --path="${WP_CORE_DIR}" --version=latest --locale=en_US --force
  fi

  # 3. Fallback: Ensure the WordPress PHPUnit test suite is present
  if [ ! -f "${WP_TESTS_DIR}/includes/functions.php" ]; then
    echo "WordPress test suite not found; downloading with Subversion..."
    WP_VERSION=$(wp core version --path="${WP_CORE_DIR}" 2>/dev/null || echo "trunk")
    SVN_BASE="https://develop.svn.wordpress.org"
    SVN_PATH="${SVN_BASE}/tags/${WP_VERSION}"

    if ! svn ls "${SVN_PATH}/" >/dev/null 2>&1; then
      echo "Tag ${WP_VERSION} not found on SVN; using trunk for tests."
      SVN_PATH="${SVN_BASE}/trunk"
    fi
    echo "Fetching test suite from ${SVN_PATH}..."
    svn co --quiet "${SVN_PATH}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
    svn co --quiet "${SVN_PATH}/tests/phpunit/data/" "${WP_TESTS_DIR}/data"
  fi
fi

echo " Environment ready."
echo ""
echo "=========================================================================="
echo "Running PHPUnit Tests..."
echo "=========================================================================="
composer phpunit