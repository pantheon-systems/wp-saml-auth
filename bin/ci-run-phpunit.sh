#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config (env overrides allowed)
# -----------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_VERSION:=latest}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"

# unique-ish DB per run to avoid residuals
RND="${RANDOM}${RANDOM}"
DB_NAME="wp_test_${WP_VERSION//./}_${RND}"

echo ">> Using DB_NAME=${DB_NAME}"

# --------------------------------
# Ensure tools / Composer dev deps
# --------------------------------
echo ">> Ensuring required packages (svn) exist"
if ! command -v svn >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi

echo ">> Ensuring Composer dev deps are installed"
composer install --no-progress --prefer-dist

# ------------------------------
# Create/reset the test database
# ------------------------------
echo ">> Creating/resetting database ${DB_NAME}"
mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# -----------------------------------------
# Download WP core and the wp-phpunit suite
# -----------------------------------------
echo ">> Installing WP test harness (WP ${WP_VERSION})"
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}" || true
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

wp core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --locale=en_US --force
RESOLVED_WP_VERSION="$(wp core version --path="${WP_CORE_DIR}")"

# pull the test suite for the exact version
svn --quiet co "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn --quiet co "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/data/"     "${WP_TESTS_DIR}/data"

# ---------------------------
# Create wp-tests-config.php
# ---------------------------
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

define( 'WP_DEBUG', true );
define( 'ABSPATH', '${WP_CORE_DIR}/' );
PHP

# ----------------------------------------------------
# Sync this plugin into the WP under-test & activate it
# ----------------------------------------------------
PLUGIN_DST="${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth"
echo ">> Syncing plugin into ${PLUGIN_DST}"
rm -rf "${PLUGIN_DST}"
mkdir -p "${PLUGIN_DST}"
rsync -a --delete --exclude=".git" --exclude="vendor" ./ "${PLUGIN_DST}/"

# install plugin Composer deps inside the synced copy (autoload for tests)
echo ">> Installing plugin composer deps"
(
  cd "${PLUGIN_DST}"
  composer install --no-progress --prefer-dist
)

echo ">> Activating plugin wp-saml-auth"
wp plugin activate wp-saml-auth --path="${WP_CORE_DIR}" --quiet || true

# -----------------------------------------------------------------
# Write minimal options so plugin has a clean baseline in test DB
# (Provider will be overridden to 'internal' by the test bootstrap.)
# -----------------------------------------------------------------
echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "connection_type": "internal",
  "provider": "internal",
  "auto_provision": true,
  "permit_wp_login": true
}
JSON
)" --format=json --path="${WP_CORE_DIR}" --quiet || true

echo ">> Test table prefix: wptests_"

# --------------------------------------------------------------------
# Test bootstrap override (NO MU-PLUGIN):
# Force plugin options via the 'wp_saml_auth_option' filter so that the
# provider is 'internal' and tests don't need SimpleSAMLphp/OneLogin.
# --------------------------------------------------------------------
if [ -d "tests/phpunit" ]; then
  echo ">> Patching tests/phpunit/bootstrap.php with provider override"
  cat > tests/phpunit/bootstrap.php <<'PHP'
<?php
/**
 * CI bootstrap for wp-saml-auth on GitHub Actions
 * - Forces provider to 'internal' during tests (no external SAML libs).
 */

require_once dirname( __DIR__, 2 ) . '/vendor/autoload.php';

// Override plugin options at runtime.
// Signature in plugin: apply_filters( 'wp_saml_auth_option', $value, $option )
tests_add_filter( 'wp_saml_auth_option', function( $value, $option ) {
    if ( 'provider' === $option ) {
        return 'internal';
    }
    if ( 'connection_type' === $option ) {
        return 'internal';
    }
    if ( 'permit_wp_login' === $option ) {
        return true;
    }
    // Keep everything else as-is.
    return $value;
}, 10, 2 );

// Load WP and the plugin under test.
require_once getenv( 'WP_TESTS_DIR' ) . '/includes/functions.php';
function _manually_load_plugin() {
    require dirname( __DIR__, 2 ) . '/wp-saml-auth.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );
require getenv( 'WP_TESTS_DIR' ) . '/includes/bootstrap.php';
PHP
fi

# ----------------
# Run the tests 🚦
# ----------------
echo ">> Running PHPUnit"
# Ensure phpunit from plugin vendor is preferred
export PATH="${PLUGIN_DST}/vendor/bin:${PATH}"

# WP core path for any WP-CLI usage inside tests
export WP_CORE_DIR
export WP_TESTS_DIR

# Execute the repo-defined phpunit script if present; else call phpunit directly
if composer run -l | grep -qE '(^| )phpunit( |$)'; then
  composer phpunit
else
  vendor/bin/phpunit
fi
