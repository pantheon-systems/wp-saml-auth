#!/usr/bin/env bash
# CI helper to run WordPress unit tests for wp-saml-auth without MU plugins.
# - Installs/updates the WP unit test harness
# - Syncs the plugin into the test WP instance
# - Activates the plugin
# - Writes minimal SAML settings straight into the *test* DB options table
# - Forces internal SAML provider via options (no SimpleSAMLphp required)
# - Runs PHPUnit

set -euo pipefail

log() { printf '>> %s\n' "$*"; }
err() { printf '!! %s\n' "$*" >&2; }

# -------------------------
# Inputs & sensible defaults
# -------------------------
WP_VERSION="${WP_VERSION:-6.8.3}"

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"

# Dynamically generate DB_NAME per run if not provided
if [[ "${DB_NAME:-}" == "" ]]; then
  # shorten version string like 6.8.3 -> 683
  _vshort="$(echo "$WP_VERSION" | tr -d '.')"
  DB_NAME="wp_test_${_vshort}_$(date +%s%N | tail -c 11)_${GITHUB_RUN_ID:-$RANDOM}_"
fi

# Paths for the harness
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
export WP_CORE_DIR WP_TESTS_DIR

log "Using DB_NAME=${DB_NAME}"

# -------------------------------------------------------
# Ensure wpunit-helpers is available (bin/install scripts)
# -------------------------------------------------------
if [[ ! -x "bin/install-wp-tests.sh" || ! -x "bin/phpunit-test.sh" ]]; then
  log "wpunit-helpers not found; installing (composer require --dev pantheon-systems/wpunit-helpers)"
  composer require --no-ansi --no-interaction --no-progress --dev pantheon-systems/wpunit-helpers || {
    err "Failed to install pantheon-systems/wpunit-helpers"; exit 1;
  }
fi

# ----------------------------------
# Create/reset the test database name
# ----------------------------------
log "Creating/resetting database ${DB_NAME}"
MYSQL_PWD="${DB_PASSWORD}" mysql -h "${DB_HOST}" -u "${DB_USER}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; CREATE DATABASE \`${DB_NAME}\`;" || {
  err "Cannot create/reset database ${DB_NAME}"; exit 1;
}

# ---------------------------------------------------------
# Install WP core + tests harness (use --version, not --wpversion)
# ---------------------------------------------------------
log "Installing WP test harness (WP ${WP_VERSION})"
bash bin/install-wp-tests.sh \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --version="${WP_VERSION}" \
  --tmpdir="/tmp" \
  --skip-db=true

# (bin/install-wp-tests.sh also downloads/sets up WP core at $WP_CORE_DIR)

# -------------------------------------------
# Sync the plugin into the test WP plugin dir
# -------------------------------------------
PLUGIN_SLUG="wp-saml-auth"
PLUGIN_DST="${WP_CORE_DIR%/}/wp-content/plugins/${PLUGIN_SLUG}"

log "Syncing plugin into ${PLUGIN_DST}"
mkdir -p "$(dirname "${PLUGIN_DST}")"
rsync -a --delete --exclude='.git/' --exclude='.github/' --exclude='vendor/' ./ "${PLUGIN_DST}/"

# Install plugin composer deps in-place (the tests expect autoload ready)
log "Installing plugin composer deps"
(
  cd "${PLUGIN_DST}"
  composer install --no-ansi --no-interaction --no-progress
)

# -------------------------
# Activate the plugin in WP
# -------------------------
log "Activating plugin ${PLUGIN_SLUG}"
wp plugin activate "${PLUGIN_SLUG}" --path="${WP_CORE_DIR}" || {
  err "Failed to activate ${PLUGIN_SLUG}"; exit 1;
}

# -------------------------------------------------
# Write minimal SAML settings directly into test DB
# (prevents OneLogin complaining about missing IdP)
# -------------------------------------------------
log "Writing minimal SAML settings into TEST DB (${DB_NAME})"

# Find test table prefix from wp-tests-config.php safely; fallback to wp_
TEST_CFG="${WP_TESTS_DIR%/}/wp-tests-config.php"
TABLE_PREFIX="$({ grep -E "^\s*\$table_prefix\s*=" "$TEST_CFG" 2>/dev/null || true; } \
  | sed -E "s/.*'([^']+)'.*/\1/")"
[[ -z "${TABLE_PREFIX}" ]] && TABLE_PREFIX="wp_"
log "Test table prefix: ${TABLE_PREFIX}"

# Minimal-but-valid settings (internal provider + dummy IdP fingerprint)
# NOTE: We upsert *both* historical keys the plugin may check.
read -r -d '' PHP_SETTINGS <<'PHPJSON' || true
<?php
$c = [
  "connection_type" => "internal",
  "internal_config" => [
    "strict"  => true,
    "debug"   => false,
    "baseurl" => "http://example.test",
    "sp" => [
      "entityId" => "urn:example",
      "assertionConsumerService" => [ "url" => "http://example.test/wp-login.php" ]
    ],
    "idp" => [
      "entityId" => "urn:dummy-idp",
      "singleSignOnService"  => [ "url" => "https://idp.invalid/sso" ],
      "singleLogoutService"  => [ "url" => "https://idp.invalid/slo" ],
      // 20-byte SHA1 fingerprint format (dummy but syntactically valid)
      "x509cert" => "",
      "certFingerprint" => "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD"
    ]
  ]
];
echo addslashes(serialize($c));
PHPJSON

SERIALIZED="$(php -r "$PHP_SETTINGS")"

DDL="
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE TABLE IF NOT EXISTS \`${DB_NAME}\`.\`${TABLE_PREFIX}options\` (
  option_id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  option_name varchar(191) NOT NULL DEFAULT '',
  option_value longtext NOT NULL,
  autoload varchar(20) NOT NULL DEFAULT 'yes',
  PRIMARY KEY (option_id),
  UNIQUE KEY option_name (option_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"
MYSQL_PWD="${DB_PASSWORD}" mysql -h "${DB_HOST}" -u "${DB_USER}" -e "$DDL" || {
  err "Failed to create options table in ${DB_NAME}"; exit 1;
}

UPSERT="
REPLACE INTO \`${DB_NAME}\`.\`${TABLE_PREFIX}options\` (option_name, option_value, autoload)
VALUES
  ('wp_saml_auth_settings', '${SERIALIZED}', 'no'),
  ('wp_saml_auth_options',  '${SERIALIZED}', 'no');
"
MYSQL_PWD="${DB_PASSWORD}" mysql -h "${DB_HOST}" -u "${DB_USER}" -e "$UPSERT" || {
  err "Failed to upsert minimal SAML settings into ${DB_NAME}.${TABLE_PREFIX}options"; exit 1;
}

# -------------------------------------------------
# Finally, run PHPUnit from the project under test
# -------------------------------------------------
log "Running PHPUnit"
vendor/bin/phpunit --do-not-cache-result
