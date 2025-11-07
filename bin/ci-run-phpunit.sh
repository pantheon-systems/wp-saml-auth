#!/usr/bin/env bash
# Strict mode
set -euo pipefail

### -------------------------
### Config & derived values
### -------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"
: "${WP_VERSION:=6.8.3}"

# Repo/plugin root (preserve prior behavior of running in repo)
PLUGIN_DIR="${GITHUB_WORKSPACE:-$PWD}"
REPO_DIR="$PLUGIN_DIR"

# BOOTSTRAP must be a FILE, never a directory (fixes include_once(dir) error)
: "${BOOTSTRAP:=${PLUGIN_DIR}/tests/phpunit/bootstrap.php}"

log() { printf '>> %s\n' "$*"; }
die() { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

### -------------------------
### Preflight
### -------------------------
need php
need curl
need tar
need wp
if ! command -v composer >/dev/null 2>&1; then die "composer is required"; fi

[[ -f "$BOOTSTRAP" ]] || die "Bootstrap not found at $BOOTSTRAP"

### -------------------------
### Install WP core (preserve prior logic)
### -------------------------
log "Installing WP core ${WP_VERSION} into ${WP_CORE_DIR}"
mkdir -p "${WP_CORE_DIR}"
wp core download --path="${WP_CORE_DIR}" --version="${WP_VERSION}" --force

DB_NAME="wp_test_${RANDOM}"
log "Creating database ${DB_NAME}"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

log "Generating wp-config.php"
wp config create --path="${WP_CORE_DIR}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" --dbhost="${DB_HOST}" --skip-check --force

log "Installing WordPress"
wp core install --path="${WP_CORE_DIR}" --url="http://example.com" --title="Test Site" --admin_user="admin" --admin_password="password" --admin_email="admin@example.com"

log "Resolved WP version: $(wp core version --path="${WP_CORE_DIR}")"

### -------------------------
### Prepare WP test suite (no svn; preserve approach)
### -------------------------
log "Preparing WP test suite in ${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"
if [[ ! -f "/tmp/wordpress-develop-${WP_VERSION}.tar.gz" ]]; then
  curl -sSL -o "/tmp/wordpress-develop-${WP_VERSION}.tar.gz" "https://github.com/WordPress/wordpress-develop/archive/refs/tags/${WP_VERSION}.tar.gz"
fi
TMP_EXTRACT="/tmp/wp-develop-${WP_VERSION}"
rm -rf "${TMP_EXTRACT}"; mkdir -p "${TMP_EXTRACT}"
tar -xzf "/tmp/wordpress-develop-${WP_VERSION}.tar.gz" -C "${TMP_EXTRACT}"
DEVELOP_DIR="$(find "${TMP_EXTRACT}" -maxdepth 1 -type d -name "wordpress-develop-*")"
[[ -d "${DEVELOP_DIR}/tests/phpunit" ]] || die "wordpress-develop tests not found"
rm -rf "${WP_TESTS_DIR}"; mkdir -p "${WP_TESTS_DIR}"
cp -R "${DEVELOP_DIR}/tests/phpunit/"* "${WP_TESTS_DIR}/"

cat > "${WP_TESTS_DIR}/wp-tests-config.php" <<PHP
<?php
define( 'DB_NAME', '${DB_NAME}' );
define( 'DB_USER', '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST', '${DB_HOST}' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL', 'admin@example.org' );
define( 'WP_TESTS_TITLE', 'Test Blog' );
\$table_prefix = 'wptests_';
define( 'ABSPATH', '${WP_CORE_DIR}/' );
define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', '${WP_TESTS_PHPUNIT_POLYFILLS_PATH}' );
PHP

### -------------------------
### Sync plugin into WP & install deps (preserve)
### -------------------------
log "Sync plugin into ${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth"
mkdir -p "${WP_CORE_DIR}/wp-content/plugins"
rsync -a --delete --exclude='.git/' --exclude='.github/' --exclude='node_modules/' "${PLUGIN_DIR}/" "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth/"

log "Composer install at repo"
pushd "${REPO_DIR}" >/dev/null
if [[ ! -x "vendor/bin/phpunit" ]]; then
  composer install --no-interaction --no-progress --prefer-dist
fi
popd >/dev/null

log "Composer install at plugin copy"
pushd "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth" >/dev/null
composer install --no-interaction --no-progress --prefer-dist || true
popd >/dev/null

### -------------------------
### Activate plugin & seed options (preserve)
### -------------------------
wp plugin activate wp-saml-auth --path="${WP_CORE_DIR}"

# Minimal options to match previous behavior
wp option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "provider": "test-sp",
  "auto_provision": true,
  "permit_wp_login": true,
  "user_claim": "mail",
  "display_name_mapping": "display_name",
  "map_by_email": true,
  "default_role": "subscriber",
  "attribute_mapping": {
    "user_login": "uid",
    "user_email": "mail",
    "first_name": "givenName",
    "last_name": "sn",
    "display_name": "displayName"
  }
}
JSON
)" --format=json --path="${WP_CORE_DIR}"

### -------------------------
### Run PHPUnit (fix: ensure bootstrap FILE is used)
### -------------------------
PHPUNIT_BIN="vendor/bin/phpunit"
[[ -x "$PHPUNIT_BIN" ]] || PHPUNIT_BIN="${PLUGIN_DIR}/vendor/bin/phpunit"

PHPUNIT_CFG=""
if [[ -f "${PLUGIN_DIR}/phpunit.xml" ]]; then
  PHPUNIT_CFG="-c ${PLUGIN_DIR}/phpunit.xml"
elif [[ -f "${PLUGIN_DIR}/phpunit.xml.dist" ]]; then
  PHPUNIT_CFG="-c ${PLUGIN_DIR}/phpunit.xml.dist"
fi

set -x
"$PHPUNIT_BIN" ${PHPUNIT_CFG:+$PHPUNIT_CFG} --bootstrap "${BOOTSTRAP}" "${PLUGIN_DIR}/tests/phpunit"
set +x
