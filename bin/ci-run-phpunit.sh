#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- Config / Inputs ----------
: "${DB_HOST:?DB_HOST required}"
: "${DB_USER:?DB_USER required}"
: "${DB_PASSWORD:?DB_PASSWORD required}"
: "${WP_CORE_DIR:?WP_CORE_DIR required}"           # e.g. /tmp/wordpress
: "${WP_TESTS_DIR:?WP_TESTS_DIR required}"         # e.g. /tmp/wordpress-tests-lib
: "${WP_VERSION:?WP_VERSION required}"             # e.g. 6.8.3

REPO_DIR="$(pwd)"
PLUGIN_SLUG="wp-saml-auth"
WP_PATH="${WP_CORE_DIR}"
PLUGIN_DST="${WP_PATH}/wp-content/plugins/${PLUGIN_SLUG}"
TABLE_PREFIX="wptests_"
DB_NAME="${DB_NAME:-wp_test_${WP_VERSION//./}_${RANDOM}${RANDOM}}"

echo ">> Using DB_NAME=${DB_NAME}"

# ---------- System prerequisites ----------
echo ">> Ensuring required packages (svn) exist"
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends subversion

# ---------- Composer (dev) deps for this repo ----------
echo ">> Ensuring Composer dev deps are installed"
composer install --no-interaction --no-progress --prefer-dist

# ---------- Database ----------
echo ">> Creating/resetting database ${DB_NAME}"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# ---------- WordPress core ----------
echo ">> Installing WP core (${WP_VERSION})"
wp core download --path="${WP_PATH}" --version="${WP_VERSION}" --locale=en_US --force
echo ">> Creating wp-config.php"
wp config create \
  --path="${WP_PATH}" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --dbprefix="${TABLE_PREFIX}" \
  --skip-check \
  --force
echo ">> Installing WordPress"
wp core install \
  --path="${WP_PATH}" \
  --url="http://example.test" \
  --title="Test Blog" \
  --admin_user="admin" \
  --admin_password="password" \
  --admin_email="admin@example.org" \
  --skip-email

# ---------- WP test suite (manual, version-matched) ----------
echo ">> Resolved WP version: $(wp core version --path="${WP_PATH}")"
echo ">> Preparing WP test suite"
mkdir -p "${WP_TESTS_DIR}/includes" "${WP_TESTS_DIR}/data"

svn co --quiet "https://develop.svn.wordpress.org/tags/$(wp core version --path="${WP_PATH}")/tests/phpunit/includes/" "${WP_TESTS_DIR}/includes"
svn co --quiet "https://develop.svn.wordpress.org/tags/$(wp core version --path="${WP_PATH}")/tests/phpunit/data/" "${WP_TESTS_DIR}/data"

echo ">> Writing ${WP_TESTS_DIR}/wp-tests-config.php"
cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );
\$table_prefix = '${TABLE_PREFIX}';
define( 'WP_DEBUG', true );
define( 'ABSPATH', '${WP_PATH}/' );
define( 'WP_PHP_BINARY', 'php' );
define( 'WP_TESTS_DOMAIN', 'example.test' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'Test Blog' );
PHP

# ---------- Sync plugin into WP and install plugin deps (inside plugin copy) ----------
echo ">> Syncing plugin into ${PLUGIN_DST}"
rm -rf "${PLUGIN_DST}"
mkdir -p "$(dirname "${PLUGIN_DST}")"
rsync -a --delete --exclude ".git" --exclude ".github" --exclude "node_modules" --exclude ".cache" "${REPO_DIR}/" "${PLUGIN_DST}/"

echo ">> Installing plugin composer deps"
pushd "${PLUGIN_DST}" >/dev/null
composer install --no-interaction --no-progress --prefer-dist
popd >/dev/null

# ---------- Activate plugin & write minimal settings ----------
echo ">> Activating plugin ${PLUGIN_SLUG}"
wp plugin activate "${PLUGIN_SLUG}" --path="${WP_PATH}"

echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
# IMPORTANT: use OneLogin provider to avoid SimpleSAMLphp autoloader in CI.
wp option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "provider": "onelogin",
  "strict": false,
  "auto_provision": true,
  "auto_provision_email": "mail",
  "auto_provision_first_name": "first_name",
  "auto_provision_last_name": "last_name",
  "name": "name",
  "email": "mail",
  "external_user_login": "uid",
  "default_role": "subscriber",
  "get_user_by": "email",
  "prevent_reauth": false,
  "require_domain": "",
  "append_domain": "",
  "use_wp_login_form": true,
  "debug": false
}
JSON
)" --format=json --path="${WP_PATH}"

# ---------- PHPUnit config (root-level) ----------
ROOT_XML="phpunit.xml.dist"
if [[ ! -f "${ROOT_XML}" ]]; then
  echo "ERROR: ${ROOT_XML} not found at repo root."
  exit 1
fi

echo ">> Test table prefix: ${TABLE_PREFIX}"
echo ">> Running PHPUnit"
# Make sure the env WP_TESTS_DIR & WP_CORE_DIR are visible to the test bootstrap.
export WP_TESTS_DIR
export WP_CORE_DIR="${WP_PATH}"

# Run from repo root, use root phpunit.xml.dist
composer run -- phpunit -c "${ROOT_XML}"
