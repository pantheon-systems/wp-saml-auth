#!/usr/bin/env bash
set -euo pipefail

: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"
: "${WP_VERSION:=6.8.3}"

REPO_DIR="${GITHUB_WORKSPACE:-$PWD}"
: "${BOOTSTRAP:=${REPO_DIR}/tests/phpunit/bootstrap.php}"

log(){ printf '>> %s\n' "$*"; }
die(){ echo "Error: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

need php; need curl; need tar; need wp
command -v composer >/dev/null 2>&1 || die "composer is required"
[[ -f "$BOOTSTRAP" ]] || die "Bootstrap not found: $BOOTSTRAP"

DB_NAME="wp_test_${RANDOM}"

log "Installing WP core $WP_VERSION to $WP_CORE_DIR"
mkdir -p "$WP_CORE_DIR"
wp core download --path="$WP_CORE_DIR" --version="$WP_VERSION" --force

log "Reset DB $DB_NAME"
mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
mysql --host="$DB_HOST" --user="$DB_USER" --password="$DB_PASSWORD" -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

log "wp-config.php"
wp config create --path="$WP_CORE_DIR" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASSWORD" --dbhost="$DB_HOST" --skip-check --force

log "Install WP"
wp core install --path="$WP_CORE_DIR" --url="http://example.com" --title="Test Site" --admin_user="admin" --admin_password="password" --admin_email="admin@example.com"

log "Prepare WP tests in $WP_TESTS_DIR"
mkdir -p "$WP_TESTS_DIR"
tgz="/tmp/wordpress-develop-${WP_VERSION}.tar.gz"
if [[ ! -f "$tgz" ]]; then
  curl -sSL -o "$tgz" "https://github.com/WordPress/wordpress-develop/archive/refs/tags/${WP_VERSION}.tar.gz"
fi
tmp="/tmp/wp-develop-${WP_VERSION}"; rm -rf "$tmp"; mkdir -p "$tmp"
tar -xzf "$tgz" -C "$tmp"
develop_dir="$(find "$tmp" -maxdepth 1 -type d -name "wordpress-develop-*")"
[[ -d "$develop_dir/tests/phpunit" ]] || die "wordpress-develop tests not found"
rm -rf "$WP_TESTS_DIR"; mkdir -p "$WP_TESTS_DIR"
cp -R "$develop_dir/tests/phpunit/"* "$WP_TESTS_DIR/"

cat > "$WP_TESTS_DIR/wp-tests-config.php" <<PHP
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

log "Sync plugin to WP"
mkdir -p "$WP_CORE_DIR/wp-content/plugins"
rsync -a --delete --exclude='.git/' --exclude='.github/' --exclude='node_modules/' "$REPO_DIR/" "$WP_CORE_DIR/wp-content/plugins/wp-saml-auth/"

log "Composer install (repo)"
pushd "$REPO_DIR" >/dev/null
[[ -x vendor/bin/phpunit ]] || composer install --no-interaction --no-progress --prefer-dist
popd >/dev/null

log "Composer install (plugin copy)"
pushd "$WP_CORE_DIR/wp-content/plugins/wp-saml-auth" >/dev/null
composer install --no-interaction --no-progress --prefer-dist || true
popd >/dev/null

log "Activate plugin"
wp plugin activate wp-saml-auth --path="$WP_CORE_DIR"

log "Seed minimal options"
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
)" --format=json --path="$WP_CORE_DIR"

PHPUNIT_BIN="$REPO_DIR/vendor/bin/phpunit"
PHPUNIT_CFG=""
[[ -f "$REPO_DIR/phpunit.xml" ]] && PHPUNIT_CFG="-c $REPO_DIR/phpunit.xml"
[[ -z "$PHPUNIT_CFG" && -f "$REPO_DIR/phpunit.xml.dist" ]] && PHPUNIT_CFG="-c $REPO_DIR/phpunit.xml.dist"

[[ -x "$PHPUNIT_BIN" ]] || die "phpunit not found at $PHPUNIT_BIN"
[[ -f "$BOOTSTRAP" ]] || die "bootstrap file missing at $BOOTSTRAP"

set -x
"$PHPUNIT_BIN" ${PHPUNIT_CFG:+$PHPUNIT_CFG} --bootstrap "$BOOTSTRAP"
set +x
