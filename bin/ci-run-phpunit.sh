#!/usr/bin/env bash
set -euo pipefail

# --- Config (env overrides allowed) ---
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"

# Safer unique DB name (alnum + underscores only)
_rnd="$(printf '%04d' $(( ${RANDOM:-0} % 10000 )))"
DB_NAME="${DB_NAME:-wp_test_$(date +%j)_${_rnd}_$(date +%s)_}"

WP_VERSION="${WP_VERSION:-latest}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
WP_TESTS_PHPUNIT_POLYFILLS_PATH="${WP_TESTS_PHPUNIT_POLYFILLS_PATH:-/tmp/phpunit-deps}"

echo ">> Using DB_NAME=${DB_NAME}"

# --- Ensure wpunit-helpers is available (provides install-wp-tests.sh & helpers) ---
if ! test -f "vendor/pantheon-systems/wpunit-helpers/bin/install-wp-tests.sh"; then
  echo ">> wpunit-helpers not found; installing (composer require --dev pantheon-systems/wpunit-helpers)"
  composer require --no-interaction --no-progress --dev pantheon-systems/wpunit-helpers:^2.0
fi

INSTALLER="vendor/pantheon-systems/wpunit-helpers/bin/install-wp-tests.sh"
if ! test -f "$INSTALLER"; then
  echo "Missing $INSTALLER after install"
  exit 1
fi

# --- Create/reset DB ---
echo ">> Creating/resetting database ${DB_NAME}"
mysql --protocol=tcp -h "${DB_HOST}" -u "${DB_USER}" -p"${DB_PASSWORD}" \
  -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; CREATE DATABASE \`${DB_NAME}\`;"

# --- Install WP core + test harness ---
echo ">> Installing WP test harness (WP ${WP_VERSION})"
bash "$INSTALLER" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --version="${WP_VERSION}" \
  --tmpdir="/tmp" \
  --skip-db=true

# --- Sync plugin into test site & install composer deps (if any) ---
echo ">> Syncing plugin into ${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth"
rsync -a --delete --exclude .git --exclude vendor ./ "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth/"

echo ">> Installing plugin composer deps"
( cd "${WP_CORE_DIR}/wp-content/plugins/wp-saml-auth" && composer install --no-interaction --no-progress )

# --- Activate the plugin in the test WP install ---
echo ">> Activating plugin wp-saml-auth"
wp --path="${WP_CORE_DIR}" plugin activate wp-saml-auth --quiet || true

# --- Seed minimal settings in the WP options table (optional safeguard) ---
echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp --path="${WP_CORE_DIR}" option update wp_saml_auth_settings "$(cat <<'JSON'
{
  "connection_type": "internal",
  "permit_wp_login": true,
  "internal_config": {
    "strict": true,
    "debug": false,
    "baseurl": "http://example.test",
    "sp": {
      "entityId": "urn:example",
      "assertionConsumerService": { "url": "http://example.test/wp-login.php" }
    },
    "idp": {
      "entityId": "urn:dummy-idp",
      "singleSignOnService": { "url": "https://idp.invalid/sso" },
      "singleLogoutService": { "url": "https://idp.invalid/slo" },
      "certFingerprint": "00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33"
    }
  }
}
JSON
)" --format=json --quiet || true

# --- NO MU PLUGIN: use auto_prepend_file to force internal provider during tests ---
OVERRIDE_FILE="/tmp/wpsa-force-internal.php"
cat > "${OVERRIDE_FILE}" <<'PHP'
<?php
// Ensures tests always use the internal provider without touching repo files.
// Loaded before everything via -d auto_prepend_file.

if (function_exists('add_filter')) {
    add_filter('pre_option_wp_saml_auth_settings', static function () {
        return array(
            'connection_type' => 'internal',
            'permit_wp_login' => true,
            'internal_config' => array(
                'strict'  => true,
                'debug'   => false,
                'baseurl' => 'http://example.test',
                'sp' => array(
                    'entityId' => 'urn:example',
                    'assertionConsumerService' => array('url' => 'http://example.test/wp-login.php'),
                ),
                'idp' => array(
                    'entityId' => 'urn:dummy-idp',
                    'singleSignOnService' => array('url' => 'https://idp.invalid/sso'),
                    'singleLogoutService' => array('url' => 'https://idp.invalid/slo'),
                    'certFingerprint' => '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33',
                ),
            ),
        );
    }, 9999);

    add_filter('wp_saml_auth_option', static function ($value, $key) {
        if ($key === 'connection_type') {
            return 'internal';
        }
        if ($key === 'internal_config') {
            return array(
                'strict'  => true,
                'debug'   => false,
                'baseurl' => 'http://example.test',
                'sp' => array(
                    'entityId' => 'urn:example',
                    'assertionConsumerService' => array('url' => 'http://example.test/wp-login.php'),
                ),
                'idp' => array(
                    'entityId' => 'urn:dummy-idp',
                    'singleSignOnService' => array('url' => 'https://idp.invalid/sso'),
                    'singleLogoutService' => array('url' => 'https://idp.invalid/slo'),
                    'certFingerprint' => '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33',
                ),
            );
        }
        return $value;
    }, 9999, 2);

    add_filter('wp_saml_auth_default_settings', static function ($defaults) {
        $defaults['connection_type'] = 'internal';
        $defaults['permit_wp_login'] = true;
        return $defaults;
    }, 9999);
}
PHP

echo ">> Running PHPUnit"
exec vendor/bin/phpunit --do-not-cache-result -d "auto_prepend_file=${OVERRIDE_FILE}"
