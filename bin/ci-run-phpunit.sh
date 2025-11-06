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

# Detect wpunit-helpers install script
if [ ! -x bin/install-wp-tests.sh ]; then
  echo "bin/install-wp-tests.sh not found. Install wpunit-helpers first: composer require --dev pantheon-systems/wpunit-helpers" >&2
  exit 1
fi

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
bash bin/install-wp-tests.sh \
  --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" --wpversion="${WP_VERSION}" --skip-db=true
RC=$?
if [ $RC -ne 0 ]; then
  bash bin/install-wp-tests.sh \
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

### 4) PHPUnit bootstrap injection: force SAML "internal" + minimal IdP/SP config
log "Injecting bootstrap to force internal provider w/ minimal OneLogin config"
CI_BOOT="/tmp/ci-wpsaml-bootstrap.php"
cat > "$CI_BOOT" <<'PHP'
<?php
// Loaded by WP's PHPUnit bootstrap; register filters before plugins complete init.
if (function_exists('tests_add_filter')) {
  tests_add_filter('plugins_loaded', function () {
    // Force OneLogin internal provider
    add_filter('wp_saml_auth_option', function ($value, $name) {
      if ($name === 'connection_type') {
        return 'internal';
      }
      return $value;
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
