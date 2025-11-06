#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- Defaults (overridable) --------------------------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_VERSION:=latest}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"

# Unique DB each run
if [[ -z "${DB_NAME:-}" ]]; then
  ts="$(date +%s%N | cut -b1-11)"
  DB_NAME="wp_test_${WP_VERSION//./}_${RANDOM}_${ts}_"
fi
echo ">> Using DB_NAME=${DB_NAME}"

# ---------- Ensure wpunit-helpers present -------------------------------------
need_helpers=false
[[ ! -f "bin/install-wp-tests.sh" ]] && need_helpers=true
[[ ! -f "bin/phpunit-test.sh"     ]] && need_helpers=true
if $need_helpers; then
  echo ">> wpunit-helpers not found; installing (composer require --dev pantheon-systems/wpunit-helpers)"
  composer require --dev pantheon-systems/wpunit-helpers --no-interaction --no-ansi
fi

# Locate installer & wrapper (priority order)
INSTALLER=""
for p in \
  "bin/install-wp-tests.sh" \
  "vendor/pantheon-systems/wpunit-helpers/bin/install-wp-tests.sh" \
  "vendor/bin/install-wp-tests.sh"
do
  [[ -f "$p" ]] && { INSTALLER="$p"; break; }
done
[[ -n "$INSTALLER" ]] || { echo "Missing install-wp-tests.sh after install"; exit 1; }

PHPUNIT_WRAPPER=""
for p in \
  "bin/phpunit-test.sh" \
  "vendor/pantheon-systems/wpunit-helpers/bin/phpunit-test.sh" \
  "vendor/bin/phpunit-test.sh"
do
  [[ -f "$p" ]] && { PHPUNIT_WRAPPER="$p"; break; }
done
[[ -n "$PHPUNIT_WRAPPER" ]] || { echo "Missing phpunit-test.sh after install"; exit 1; }

chmod +x "$INSTALLER" "$PHPUNIT_WRAPPER"

# ---------- DB reset (best-effort) --------------------------------------------
echo ">> Creating/resetting database ${DB_NAME}"
mysqladmin -h "${DB_HOST}" -u "${DB_USER}" --password="${DB_PASSWORD}" drop   "${DB_NAME}" --force >/dev/null 2>&1 || true
mysqladmin -h "${DB_HOST}" -u "${DB_USER}" --password="${DB_PASSWORD}" create "${DB_NAME}" || true

# ---------- Install WP core & tests harness -----------------------------------
echo ">> Installing WP test harness (WP ${WP_VERSION})"
bash "$INSTALLER" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --version="${WP_VERSION}" \
  --tmpdir="/tmp" \
  --skip-db=true

WP_PATH="${WP_CORE_DIR%/}"

# ---------- Sync plugin & install its deps ------------------------------------
echo ">> Syncing plugin into ${WP_PATH}/wp-content/plugins/wp-saml-auth"
rsync -a --delete --exclude ".git" ./ "${WP_PATH}/wp-content/plugins/wp-saml-auth/"

echo ">> Installing plugin composer deps"
( cd "${WP_PATH}/wp-content/plugins/wp-saml-auth" && composer install --no-interaction --no-progress )

# ---------- Ensure WP installed & activate plugin ------------------------------
if ! wp core is-installed --path="${WP_PATH}" >/dev/null 2>&1; then
  wp core install \
    --path="${WP_PATH}" \
    --url="http://example.test" \
    --title="Test" \
    --admin_user="admin" \
    --admin_password="password" \
    --admin_email="admin@example.test" \
    --skip-email
fi

echo ">> Activating plugin wp-saml-auth"
wp plugin activate wp-saml-auth --path="${WP_PATH}" --quiet || true

# ---------- Force INTERNAL (OneLogin) provider early via MU-plugin ------------
MU_DIR="${WP_PATH}/wp-content/mu-plugins"
mkdir -p "${MU_DIR}"
BOOT_FILE="${MU_DIR}/00-wpsa-force-internal.php"

cat > "${BOOT_FILE}" <<'PHP'
<?php
/**
 * Force WP SAML Auth internal provider for tests and supply minimal config.
 */
if (!function_exists('add_filter')) { return; }

// Always use internal (OneLogin) provider to avoid SimpleSAMLphp autoloader.
add_filter('wp_saml_auth_provider', static function($provider) {
    return 'internal';
}, 999);

// Provide minimal, valid internal config to satisfy OneLogin validators.
add_filter('wp_saml_auth_option', static function($value, $key) {
    if ($key !== 'internal_config') { return $value; }
    return array(
        'strict' => true,
        'debug'  => false,
        'baseurl' => 'http://example.test',
        'sp' => array(
            'entityId' => 'urn:example',
            'assertionConsumerService' => array('url' => 'http://example.test/wp-login.php'),
        ),
        'idp' => array(
            'entityId' => 'urn:dummy-idp',
            'singleSignOnService'  => array('url' => 'https://idp.invalid/sso'),
            'singleLogoutService'  => array('url' => 'https://idp.invalid/slo'),
            // Fingerprint format accepted by onelogin/php-saml.
            'certFingerprint' => '00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33',
        ),
    );
}, 10, 2);

// Default settings: allow username/password in tests unless explicitly blocked.
add_filter('wp_saml_auth_default_settings', static function($defaults) {
    $defaults['connection_type'] = 'internal';
    $defaults['permit_wp_login'] = true;
    return $defaults;
});
PHP

echo ">> MU-plugin installed at ${BOOT_FILE}"

# As an extra safety, write the full settings blob into options as well.
OPT_KEY="$(wp option list --search='wp_saml_auth_%' --field=option_name --path="${WP_PATH}" | head -n1 || true)"
[[ -z "${OPT_KEY}" ]] && OPT_KEY="wp_saml_auth_settings"
tmpjson="$(mktemp)"
cat > "${tmpjson}" <<'JSON'
{
  "connection_type": "internal",
  "permit_wp_login": true,
  "internal_config": {
    "strict": true,
    "debug": false,
    "baseurl": "http://example.test",
    "sp": { "entityId": "urn:example", "assertionConsumerService": { "url": "http://example.test/wp-login.php" } },
    "idp": {
      "entityId": "urn:dummy-idp",
      "singleSignOnService": { "url": "https://idp.invalid/sso" },
      "singleLogoutService": { "url": "https://idp.invalid/slo" },
      "certFingerprint": "00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33"
    }
  }
}
JSON
echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
wp option update "${OPT_KEY}" "$(cat "${tmpjson}")" --path="${WP_PATH}" --quiet
rm -f "${tmpjson}"

echo ">> Test table prefix: $(wp db prefix --path="${WP_PATH}")"

# ---------- Run PHPUnit via helper (single-site first) -------------------------
echo ">> Running PHPUnit"
bash "$PHPUNIT_WRAPPER" --skip-nightly
