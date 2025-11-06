#!/usr/bin/env bash
set -euo pipefail

# -------- Config from env (with sane defaults for GH runners) --------
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
WP_VERSION="${WP_VERSION:-6.8.3}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
WP_TESTS_PHPUNIT_POLYFILLS_PATH="${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-/tmp/phpunit-deps}"

# Unique test DB (avoid collisions on shared runners)
RND="$(date +%s)$RANDOM"
DB_NAME="wp_test_${WP_VERSION//./}_${RND}"

echo ">> Using DB_NAME=${DB_NAME}"

# -------- Ensure required system tools (svn) --------
echo ">> Ensuring required packages (svn) exist"
if ! command -v svn >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi

# -------- Ensure composer dev deps (no-ops if already installed) --------
echo ">> Ensuring Composer dev deps are installed"
/usr/bin/env composer install --no-interaction --no-progress

# -------- Ensure wpunit-helpers installer exists --------
INSTALLER="vendor/pantheon-systems/wpunit-helpers/bin/install-wp-tests.sh"
if [ ! -f "$INSTALLER" ]; then
  echo ">> wpunit-helpers not found; installing (composer require --dev pantheon-systems/wpunit-helpers)"
  composer require --dev pantheon-systems/wpunit-helpers:^2.0 --no-interaction --no-progress
  if [ ! -f "$INSTALLER" ]; then
    echo "Missing ${INSTALLER} after install" >&2
    exit 1
  fi
fi

# -------- Create / reset DB (idempotent) --------
echo ">> Creating/resetting database ${DB_NAME}"
mysql -h "${DB_HOST}" -u "${DB_USER}" "-p${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# -------- Install WordPress core + test suite (correct flags only) --------
echo ">> Installing WP test harness (WP ${WP_VERSION})"
bash "$INSTALLER" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --version="${WP_VERSION}" \
  --tmpdir="/tmp" \
  --skip-db=true

# The installer places WP under /tmp and the test lib under WP_TESTS_DIR.
# WP-CLI needs a path; prefer the one we declared (defaults to /tmp/wordpress).
WP_PATH="${WP_CORE_DIR}"

# -------- Activate the plugin under test --------
echo ">> Syncing plugin into ${WP_PATH}/wp-content/plugins/wp-saml-auth"
# Ensure the plugin directory exists inside the test WP tree (rsync copies your repo there)
mkdir -p "${WP_PATH}/wp-content/plugins/wp-saml-auth"
rsync -a --delete --exclude='.git' --exclude='vendor' ./ "${WP_PATH}/wp-content/plugins/wp-saml-auth/"

echo ">> Installing plugin composer deps"
# Install plugin deps inside the repo workspace (so autoloaders are correct)
composer install --no-interaction --no-progress

echo ">> Activating plugin wp-saml-auth"
wp --path="${WP_PATH}" plugin activate wp-saml-auth

# -------- Write minimal SAML settings directly to options (NO mu-plugins) --------
# Keep provider = onelogin and provide minimal IdP values so OneLogin settings validate.
echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp --path="${WP_PATH}" option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "provider": "onelogin",
  "auto_provision": false,
  "auto_provision_role": "subscriber",
  "permit_wp_login": true,
  "user_login_attribute": "uid",
  "default_username": "email",
  "attribute_mapping": {
    "username": "uid",
    "email": "mail",
    "first_name": "givenName",
    "last_name": "sn",
    "display_name": "displayName"
  },
  "idp": {
    "entityId": "https://idp.example.test/metadata",
    "singleSignOnService": { "url": "https://idp.example.test/sso" },
    "singleLogoutService": { "url": "https://idp.example.test/slo" },
    "x509cert": "MIICszCCAZugAwIBAgIUfakedummypemlineforci..."
  },
  "sp": {
    "entityId": "https://sp.example.test/metadata",
    "assertionConsumerService": { "url": "https://sp.example.test/acs" },
    "singleLogoutService": { "url": "https://sp.example.test/sls" }
  },
  "security": {
    "requestedAuthnContext": false
  }
}
JSON
)"

# Record the tests DB prefix so the script can print it (use default from wpunit-helpers)
TEST_PREFIX="$(php -r 'echo "wptests_";')"
echo ">> Test table prefix: ${TEST_PREFIX}"

# -------- PHPUnit (single-site first; multisite if config exists) --------
echo ">> Running PHPUnit"
if [ -f "phpunit.xml" ] || [ -f "phpunit.xml.dist" ]; then
  vendor/bin/phpunit
else
  vendor/bin/phpunit -c tests/phpunit/single.xml || vendor/bin/phpunit
fi
