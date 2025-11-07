#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config (env overrides allowed)
# -----------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_VERSION:=6.8.3}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_URL:=http://example.org}"
: "${WP_TITLE:=Test Blog}"
: "${WP_ADMIN_USER:=admin}"
: "${WP_ADMIN_PASS:=password}"
: "${WP_ADMIN_EMAIL:=admin@example.org}"

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
# Download WP core, create wp-config, install
# -----------------------------------------
echo ">> Installing WP core (${WP_VERSION})"
rm -rf "${WP_CORE_DIR}" || true
mkdir -p "${WP_CORE_DIR}"

wp core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --locale=en_US --force

echo ">> Creating wp-config.php"
wp config create \
  --path="${WP_CORE_DIR}" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --dbprefix="wptests_" \
  --skip-check

echo ">> Installing WordPress"
wp core install \
  --path="${WP_CORE_DIR}" \
  --url="${WP_URL}" \
  --title="${WP_TITLE}" \
  --admin_user="${WP_ADMIN_USER}" \
  --admin_password="${WP_ADMIN_PASS}" \
  --admin_email="${WP_ADMIN_EMAIL}" \
  --skip-email

RESOLVED_WP_VERSION="$(wp core version --path="${WP_CORE_DIR}")"
echo ">> Resolved WP version: ${RESOLVED_WP_VERSION}"

# -----------------------------------------
# Fetch the WP PHPUnit test suite for version
# -----------------------------------------
echo ">> Preparing WP test suite"
rm -rf "${WP_TESTS_DIR}" || true
mkdir -p "${WP_TESTS_DIR}"
svn --quiet co "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn --quiet co "https://develop.svn.wordpress.org/tags/${RESOLVED_WP_VERSION}/tests/phpunit/data/"     "${WP_TESTS_DIR}/data"

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

echo ">> Installing plugin composer deps"
(
  cd "${PLUGIN_DST}"
  composer install --no-progress --prefer-dist
)

echo ">> Activating plugin wp-saml-auth"
wp plugin activate wp-saml-auth --path="${WP_CORE_DIR}" --quiet

echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "connection_type": "internal",
  "provider": "internal",
  "auto_provision": true,
  "permit_wp_login": true
}
JSON
)" --format=json --path="${WP_CORE_DIR}" --quiet

echo ">> Test table prefix: wptests_"

# --------------------------------------------------------------------
# Test bootstrap override (NO MU-PLUGIN)
# Ensure we load WP test helpers BEFORE tests_add_filter() usage.
# Force provider to 'internal' so no SimpleSAMLphp is required.
# --------------------------------------------------------------------
if [ -d "tests/phpunit" ]; then
  echo ">> Patching tests/phpunit/bootstrap.php with provider override"
  cat > tests/phpunit/bootstrap.php <<'PHP'
<?php
/**
 * CI bootstrap for wp-saml-auth on GitHub Actions
 * - Forces provider to 'internal' during tests (no external SAML libs).
 */

require_once getenv( 'WP_TESTS_DIR' ) . '/includes/functions.php';

// Override plugin options at runtime.
// In plugin: apply_filters( 'wp_saml_auth_option', $value, $option )
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
    return $value;
}, 10, 2 );

// Load the plugin under test.
function _manually_load_plugin() {
    require dirname( __DIR__, 2 ) . '/wp-saml-auth.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

// Finally, boot WP tests.
require getenv( 'WP_TESTS_DIR' ) . '/includes/bootstrap.php';
PHP
fi

# ----------------
# Run the tests 🚦
# ----------------
echo ">> Running PHPUnit"
export WP_CORE_DIR
export WP_TESTS_DIR

# Prefer the plugin's vendor/bin in PATH if present
export PATH="${PLUGIN_DST}/vendor/bin:${PATH}"

if composer run -l | grep -qE '(^| )phpunit( |$)'; then
  composer phpunit
else
  vendor/bin/phpunit
fi
