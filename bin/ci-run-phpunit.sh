#!/usr/bin/env bash
set -Eeuo pipefail

# ---- Defaults (overridable via env) ------------------------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${WP_VERSION:=latest}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"

# Random per-run DB to avoid cross-run collisions
if [[ -z "${DB_NAME:-}" ]]; then
  ts="$(date +%s%N | cut -b1-11)"
  DB_NAME="wp_test_${WP_VERSION//./}_${RANDOM}_${ts}_"
fi

echo ">> Using DB_NAME=${DB_NAME}"

# ---- Ensure wpunit-helpers present (gives us install-wp-tests & phpunit wrapper)
if [[ ! -x "bin/install-wp-tests.sh" ]] || [[ ! -x "bin/phpunit-test.sh" ]]; then
  echo ">> wpunit-helpers not found; installing (composer require --dev pantheon-systems/wpunit-helpers)"
  composer require --dev pantheon-systems/wpunit-helpers --no-interaction --no-ansi
fi

# Re-check after composer
[[ -x "bin/install-wp-tests.sh" ]] || { echo "Missing bin/install-wp-tests.sh after install"; exit 1; }
[[ -x "bin/phpunit-test.sh"     ]] || { echo "Missing bin/phpunit-test.sh after install"; exit 1; }

# ---- DB reset (best-effort; tests will create what they need)
echo ">> Creating/resetting database ${DB_NAME}"
mysqladmin -h "${DB_HOST}" -u "${DB_USER}" --password="${DB_PASSWORD}" drop    "${DB_NAME}" --force >/dev/null 2>&1 || true
mysqladmin -h "${DB_HOST}" -u "${DB_USER}" --password="${DB_PASSWORD}" create  "${DB_NAME}"

# ---- Install WP core & the WP tests harness
echo ">> Installing WP test harness (WP ${WP_VERSION})"
# NOTE: the helper's flag is --version (not --wpversion)
bash bin/install-wp-tests.sh \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --version="${WP_VERSION}" \
  --tmpdir="/tmp" \
  --skip-db=true

# At this point core lives in ${WP_CORE_DIR}
WP_PATH="${WP_CORE_DIR%/}"

# ---- Sync plugin into the test site and install deps
echo ">> Syncing plugin into ${WP_PATH}/wp-content/plugins/wp-saml-auth"
rsync -a --delete --exclude ".git" ./ "${WP_PATH}/wp-content/plugins/wp-saml-auth/"

echo ">> Installing plugin composer deps"
( cd "${WP_PATH}/wp-content/plugins/wp-saml-auth" && composer install --no-interaction --no-progress )

# ---- Activate plugin
echo ">> Activating plugin wp-saml-auth"
wp plugin activate wp-saml-auth --path="${WP_PATH}" --quiet || {
  # If activation fails because site not installed, make a minimal install quickly
  wp core install \
    --path="${WP_PATH}" \
    --url="http://example.test" \
    --title="Test" \
    --admin_user="admin" \
    --admin_password="password" \
    --admin_email="admin@example.test" \
    --skip-email
  wp plugin activate wp-saml-auth --path="${WP_PATH}" --quiet
}
echo "Plugin 'wp-saml-auth' activated."

# ---- Seed minimal SAML settings so OneLogin validators stop complaining
# Pick option key: prefer existing wp_saml_auth_* option or fall back to common keys
OPT_KEY="$(wp option list --search='wp_saml_auth_%' --field=option_name --path="${WP_PATH}" | head -n1 || true)"
if [[ -z "${OPT_KEY}" ]]; then
  # Known keys in the wild: wp_saml_auth_settings, wp_saml_auth_options
  if wp option get wp_saml_auth_settings --path="${WP_PATH}" >/dev/null 2>&1; then
    OPT_KEY="wp_saml_auth_settings"
  else
    OPT_KEY="wp_saml_auth_options"
  fi
fi

echo ">> Writing minimal SAML settings into TEST DB (${DB_NAME})"
tmpjson="$(mktemp)"
cat > "${tmpjson}" <<'JSON'
{
  "connection_type": "internal",
  "internal_config": {
    "strict": true,
    "debug": false,
    "baseurl": "http://example.test",
    "sp": {
      "entityId": "urn:example",
      "assertionConsumerService": {
        "url": "http://example.test/wp-login.php"
      }
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

# Update the option value (no eval, no heredoc to PHP)
wp option update "${OPT_KEY}" "$(cat "${tmpjson}")" --path="${WP_PATH}" --quiet
rm -f "${tmpjson}"

# Show table prefix to help debugging (non-fatal)
echo ">> Test table prefix: $(wp db prefix --path="${WP_PATH}")"

# ---- Run the tests (single-site by default; your suite controls xmls/groups)
echo ">> Running PHPUnit"
# Use the helper wrapper which prepares env & paths
bash bin/phpunit-test.sh --skip-nightly

# End
