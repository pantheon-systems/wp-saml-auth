#!/usr/bin/env bash
# bin/ci-run-phpunit.sh
# One-shot CI runner for WordPress PHPUnit using wpunit-helpers + WP SAML Auth internal provider.
# No MU-plugins, no repo edits; only temp files under /tmp.
#
# Env you may set (all have sane defaults):
#   DB_HOST (default: 127.0.0.1)
#   DB_USER (default: root)
#   DB_PASSWORD (default: "")
#   DB_NAME (dynamic if not set)
#   WP_VERSION (default: latest)
#   WP_CORE_DIR (default: /tmp/wordpress)
#   WP_TESTS_DIR (default: /tmp/wordpress-tests-lib)
#   PLUGIN_SLUG (default: basename of repo dir)
#
# Usage:
#   bin/ci-run-phpunit.sh [-- any extra phpunit args...]
set -euo pipefail

# Detect wpunit-helpers install script in common locations
INSTALLER=""
for p in \
  "bin/install-wp-tests.sh" \
  "vendor/pantheon-systems/wpunit-helpers/bin/install-wp-tests.sh" \
  "vendor/bin/install-wp-tests.sh"
do
  if [ -f "$p" ]; then INSTALLER="$p"; break; fi
done

if [ -z "$INSTALLER" ]; then
  echo "install-wp-tests.sh not found.
Install wpunit-helpers first: composer require --dev pantheon-systems/wpunit-helpers" >&2
  exit 1
fi
chmod +x "$INSTALLER"


### Defaults
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
WP_VERSION="${WP_VERSION:-latest}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
PLUGIN_SLUG="${PLUGIN_SLUG:-$(basename "$(pwd)")}"

### Helpers
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 127; }; }
log() { printf '>> %s\n' "$*"; }

require_cmd php
require_cmd mysql
require_cmd rsync
require_cmd wp

# Composer is optional: only used if plugin has composer.json
if [ -f composer.json ]; then require_cmd composer; fi

### 0) DB name (dynamic if not provided)
if [ -z "${DB_NAME:-}" ]; then
  PHPV="$(php -r 'echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;')"   # e.g., 83
  RUNID="${GITHUB_RUN_ID:-0}"
  SHORTSHA="${GITHUB_SHA:-nosha}"; SHORTSHA="${SHORTSHA:0:7}"
  RAW="wp_test_${PHPV}_${RUNID}_${SHORTSHA}"
  DB_NAME="$(echo "$RAW" | tr -c '[:alnum:]_' '_' | cut -c1-63)"
  export DB_NAME
fi
log "Using DB_NAME=$DB_NAME"

### 1) Create/reset DB (idempotent)
log "Creating/resetting database $DB_NAME"
MYSQL_PWD="${DB_PASSWORD}" mysql -h "${DB_HOST}" -u "${DB_USER}" -e \
  "DROP DATABASE IF EXISTS \`${DB_NAME}\`; CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

### 2) Install WP test harness (skip touching DB again)
log "Installing WP test harness (WP ${WP_VERSION})"
set +e
# Try wpunit-helpers flavor first (--wpversion), then classic (--version)
bash "$INSTALLER" \
  --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" --wpversion="${WP_VERSION}" --skip-db=true
RC=$?
if [ $RC -ne 0 ]; then
  bash "$INSTALLER" \
    --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" \
    --dbhost="${DB_HOST}" --version="${WP_VERSION}" --skip-db=true
  RC=$?
fi
set -e
[ $RC -eq 0 ] || { echo "install-wp-tests.sh failed" >&2; exit $RC; }

### 3) Copy plugin-under-test into test site & activate
PLUG_DIR="${WP_CORE_DIR%/}/wp-content/plugins/${PLUGIN_SLUG}"
log "Syncing plugin into ${PLUG_DIR}"
mkdir -p "$PLUG_DIR"
rsync -a --delete ./ "$PLUG_DIR/" \
  --exclude .git --exclude .github --exclude node_modules --exclude vendor/.cache

if [ -f "$PLUG_DIR/composer.json" ]; then
  log "Installing plugin composer deps"
  ( cd "$PLUG_DIR" && composer install --no-interaction --no-progress --prefer-dist )
fi

log "Activating plugin ${PLUGIN_SLUG}"
wp plugin activate "$PLUGIN_SLUG" --path="$WP_CORE_DIR" >/dev/null

# --- Write minimal SAML settings into the TEST DB (not the site DB) ---
log "Writing minimal SAML settings into TEST DB (${DB_NAME})"

# Detect the test table prefix from wp-tests-config.php (defaults to 'wp_')
TEST_CFG="${WP_TESTS_DIR%/}/wp-tests-config.php"
TABLE_PREFIX="$(grep -E "^\s*\$table_prefix\s*=" "$TEST_CFG" | sed -E "s/.*'([^']+)'.*/\1/")"
[ -z "$TABLE_PREFIX" ] && TABLE_PREFIX="wp_"

# Build the PHP array and get its serialized form for WordPress options
SERIALIZED="$(php -r '
  $c = [
    "connection_type" => "internal",
    "internal_config" => [
      "strict"  => true,
      "debug"   => false,
      "baseurl" => "http://example.test",
      "sp" => [
        "entityId" => "urn:wp-saml-auth:test-sp",
        "assertionConsumerService" => ["url" => "http://example.test/wp-login.php"],
        "singleLogoutService"      => ["url" => "http://example.test/?sls"],
      ],
      "idp" => [
        "entityId" => "urn:dummy-idp",
        "singleSignOnService" => ["url" => "https://idp.invalid/sso"],
        "singleLogoutService" => ["url" => "https://idp.invalid/slo"],
        // Provide either x509cert OR certFingerprint; fingerprint is simplest for tests.
        "certFingerprint" => "00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33",
      ],
    ],
  ];
  echo addslashes(serialize($c));
')"

# Determine test prefix (fallback to wp_)
TEST_CFG="${WP_TESTS_DIR%/}/wp-tests-config.php"
TABLE_PREFIX="$(grep -E "^\s*\$table_prefix\s*=" "$TEST_CFG" | sed -E "s/.*'([^']+)'.*/\1/")"
[ -z "$TABLE_PREFIX" ] && TABLE_PREFIX="wp_"
log "Test table prefix: ${TABLE_PREFIX}"

# Ensure `${prefix}options` exists so we can write config before PHPUnit schema install
DDL="
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE TABLE IF NOT EXISTS \`${DB_NAME}\`.\`${TABLE_PREFIX}options\` (
  option_id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  option_name varchar(191) NOT NULL DEFAULT '',
  option_value longtext NOT NULL,
  autoload varchar(20) NOT NULL DEFAULT 'yes',
  PRIMARY KEY  (option_id),
  UNIQUE KEY option_name (option_name)
) DEFAULT CHARSET=utf8mb4;
"
MYSQL_PWD="${DB_PASSWORD}" mysql -h "${DB_HOST}" -u "${DB_USER}" -e "$DDL"

# Upsert into both legacy and current option names to be safe
SQL="
REPLACE INTO \`${DB_NAME}\`.\`${TABLE_PREFIX}options\` (option_name, option_value, autoload)
VALUES
  ('wp_saml_auth_settings', '${SERIALIZED}', 'no'),
  ('wp_saml_auth_options',  '${SERIALIZED}', 'no');
"

MYSQL_PWD="${DB_PASSWORD}" mysql -h "${DB_HOST}" -u "${DB_USER}" -e "$SQL"
# --- End SAML settings into TEST DB ---

log "Writing minimal WP SAML Auth settings into options table"
# Detect the option key used by the plugin (old vs new)
OPT_KEY="$(wp option list --search=wp_saml_auth_ --field=option_name --path="$WP_CORE_DIR" | head -n1 || echo '')"
[ -z "$OPT_KEY" ] && OPT_KEY="wp_saml_auth_settings"   # sensible default

# Build a minimal, valid internal_config for OneLogin validator
SETTINGS_JSON="$(php -r '
  $c = [];
  $c["connection_type"] = "internal";
  $c["internal_config"] = [
    "strict"  => true,
    "debug"   => false,
    "baseurl" => "http://example.test",
    "sp" => [
      "entityId" => "urn:wp-saml-auth:test-sp",
      "assertionConsumerService" => ["url" => "http://example.test/wp-login.php"],
      "singleLogoutService"      => ["url" => "http://example.test/?sls"],
    ],
    "idp" => [
      "entityId" => "urn:dummy-idp",
      "singleSignOnService" => ["url" => "https://idp.invalid/sso"],
      "singleLogoutService" => ["url" => "https://idp.invalid/slo"],
      // OneLogin requires either x509cert OR certFingerprint; fingerprint is simplest.
      "certFingerprint" => "00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33",
    ],
  ];
  echo json_encode($c, JSON_UNESCAPED_SLASHES);
')"

wp option update "$OPT_KEY" "$SETTINGS_JSON" --format=json --path="$WP_CORE_DIR" >/dev/null

# (Optional) sanity check
wp option get "$OPT_KEY" --format=json --path="$WP_CORE_DIR" | grep -q '"connection_type":"internal"'

### 4) PHPUnit bootstrap injection: force SAML "internal" + minimal IdP/SP config
log "Injecting bootstrap to force internal provider w/ minimal OneLogin config"
CI_BOOT="/tmp/ci-wpsaml-bootstrap.php"
cat > "$CI_BOOT" <<'PHP'
<?php
// Loaded by WP's PHPUnit bootstrap; run before regular plugins load.
if (function_exists('tests_add_filter')) {
  tests_add_filter('muplugins_loaded', function () {
    // Force OneLogin internal provider
    add_filter('wp_saml_auth_option', function ($value, $name) {
      return ($name === 'connection_type') ? 'internal' : $value;
    }, 10, 2);

    // Minimal internal_config required by OneLogin validator
    add_filter('wp_saml_auth_option', function ($value, $name) {
      if ($name !== 'internal_config') { return $value; }
      $cfg = is_array($value) ? $value : [];
      $cfg['strict']  = $cfg['strict']  ?? true;
      $cfg['debug']   = $cfg['debug']   ?? false;
      $cfg['baseurl'] = $cfg['baseurl'] ?? 'http://example.test';

      $cfg['sp'] = $cfg['sp'] ?? [];
      $cfg['sp']['entityId'] = $cfg['sp']['entityId'] ?? 'urn:wp-saml-auth:test-sp';
      $cfg['sp']['assertionConsumerService']['url'] =
        $cfg['sp']['assertionConsumerService']['url'] ?? 'http://example.test/wp-login.php';
      $cfg['sp']['singleLogoutService']['url'] =
        $cfg['sp']['singleLogoutService']['url'] ?? 'http://example.test/?sls';

      $cfg['idp'] = $cfg['idp'] ?? [];
      $cfg['idp']['entityId'] = $cfg['idp']['entityId'] ?? 'urn:dummy-idp';
      $cfg['idp']['singleSignOnService']['url'] =
        $cfg['idp']['singleSignOnService']['url'] ?? 'https://idp.invalid/sso';
      $cfg['idp']['singleLogoutService']['url'] =
        $cfg['idp']['singleLogoutService']['url'] ?? 'https://idp.invalid/slo';
      // Provide either x509cert OR certFingerprint; fingerprint is simplest for tests.
      $cfg['idp']['certFingerprint'] =
        $cfg['idp']['certFingerprint'] ?? '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33';

      return $cfg;
    }, 10, 2);
  });
}
PHP

CFG="${WP_TESTS_DIR%/}/wp-tests-config.php"
grep -q "ci-wpsaml-bootstrap.php" "$CFG" || \
  printf "\n// CI: force WP SAML Auth internal provider + minimal OneLogin config\nrequire '%s';\n" "$CI_BOOT" >> "$CFG"

### 5) Run PHPUnit (pass through any args after --)
log "Running PHPUnit"
# Split args after a standalone "--"
PHPUNIT_ARGS=()
seen_ddash="no"
for a in "$@"; do
  if [ "$a" = "--" ]; then seen_ddash="yes"; continue; fi
  if [ "$seen_ddash" = "yes" ]; then PHPUNIT_ARGS+=("$a"); fi
done

exec vendor/bin/phpunit --do-not-cache-result "${PHPUNIT_ARGS[@]}"
