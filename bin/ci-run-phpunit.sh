#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------
# Config (overridable via env)
# -----------------------------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${DB_NAME_PREFIX:=wp_test_}"
: "${WP_VERSION:=6.8.3}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_TESTS_PHPUNIT_POLYFILLS_PATH:=/tmp/phpunit-deps}"

# Unique DB per run
SUFFIX="${RANDOM}${RANDOM}"
DB_NAME="${DB_NAME_PREFIX}${WP_VERSION//./}_${SUFFIX}_$(date +%s%N | cut -b1-11)"

echo ">> Using DB_NAME=${DB_NAME}"

# -----------------------------
# Ensure tools we need
# -----------------------------
echo ">> Ensuring required packages (svn) exist"
if ! command -v svn >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi

echo ">> Ensuring Composer dev deps are installed"
composer install --no-interaction --no-progress

if ! test -x vendor/bin/phpunit; then
  echo "!! vendor/bin/phpunit not found after composer install"
  exit 1
fi

# -----------------------------
# Ensure wpunit-helpers v2
# -----------------------------
if ! test -x vendor/pantheon-systems/wpunit-helpers/bin/install-wp-tests.sh; then
  echo ">> wpunit-helpers not found; installing..."
  composer require --dev pantheon-systems/wpunit-helpers:^2 --no-interaction --no-progress
fi

INSTALLER="vendor/pantheon-systems/wpunit-helpers/bin/install-wp-tests.sh"
if ! test -x "$INSTALLER"; then
  echo "!! Missing $INSTALLER after install"
  exit 1
fi

# -----------------------------
# (Re)create DB
# -----------------------------
echo ">> Creating/resetting database ${DB_NAME}"
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" || true
mysql --host="${DB_HOST}" --user="${DB_USER}" --password="${DB_PASSWORD}" -e "CREATE DATABASE \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# -----------------------------
# Install WP core + test suite
# -----------------------------
echo ">> Installing WP test harness (WP ${WP_VERSION})"
bash "$INSTALLER" \
  --dbname="${DB_NAME}" \
  --dbuser="${DB_USER}" \
  --dbpass="${DB_PASSWORD}" \
  --dbhost="${DB_HOST}" \
  --version="${WP_VERSION}" \
  --tmpdir="/tmp" \
  --skip-db=false \
  --core_dir="${WP_CORE_DIR}" \
  --tests_dir="${WP_TESTS_DIR}"

# -----------------------------
# Sync plugin into the test WP
# -----------------------------
PLUGIN_SLUG="wp-saml-auth"
PLUGIN_DIR="${PWD}"
TARGET_DIR="${WP_CORE_DIR}/wp-content/plugins/${PLUGIN_SLUG}"

echo ">> Syncing plugin into ${TARGET_DIR}"
rm -rf "${TARGET_DIR}"
mkdir -p "$(dirname "${TARGET_DIR}")"
rsync -a --delete --exclude '.git' --exclude 'vendor' --exclude 'node_modules' "${PLUGIN_DIR}/" "${TARGET_DIR}/"

# Composer deps for the plugin (inside the synced copy)
if [ -f "${TARGET_DIR}/composer.json" ]; then
  echo ">> Installing plugin composer deps"
  (cd "${TARGET_DIR}" && composer install --no-interaction --no-progress)
fi

# -----------------------------
# Activate plugin
# -----------------------------
echo ">> Activating plugin ${PLUGIN_SLUG}"
wp --path="${WP_CORE_DIR}" plugin activate "${PLUGIN_SLUG}"

# -----------------------------
# Force INTERNAL provider (DB options only — NO MU PLUGINS)
# and write minimal OneLogin settings with signatures not required
# -----------------------------
echo ">> Writing minimal SAML settings into wp_options"
wp --path="${WP_CORE_DIR}" eval '
  $opt_key = "wp_saml_auth_settings";
  $settings = get_option($opt_key, []);

  // Force OneLogin internal provider only.
  $settings["connection_type"] = "internal";

  // Minimal OneLogin IdP settings (dummy but structurally valid).
  // We also disable signature requirements to avoid cert errors in tests.
  $settings["internal"] = [
    "strict"   => false,
    "debug"    => false,
    "security" => [
      "requestedAuthnContext" => false,
      "wantMessagesSigned"    => false,
      "wantAssertionsSigned"  => false,
    ],
    "idp" => [
      "entityId" => "https://example-idp.local/entity",
      "singleSignOnService" => [ "url" => "https://example-idp.local/sso" ],
      // No cert needed when wants*Signed=false
      "x509cert" => "",
    ],
    // SP can be mostly defaults; not used by unit tests.
  ];

  update_option($opt_key, $settings, true);

  // Ensure plugin is using our option (not SimpleSAMLphp).
  // If any legacy keys exist that would hint SimpleSAMLphp, neutralize them.
  $legacy = ["simplesamlphp_autoload", "authsource", "simplesaml", "simplesamlphp"];
  foreach ($legacy as $k) {
    if (isset($settings[$k])) { unset($settings[$k]); }
  }
  update_option($opt_key, $settings, true);

  // Show what we ended up with for debugging.
  echo "connection_type=" . ($settings["connection_type"] ?? "n/a") . PHP_EOL;
'

# -----------------------------
# Sanity dump of option to logs
# -----------------------------
echo ">> Current wp_saml_auth_settings (JSON)"
wp --path="${WP_CORE_DIR}" option get wp_saml_auth_settings --format=json || true

# -----------------------------
# Run PHPUnit (single site)
# -----------------------------
echo ">> Running PHPUnit (single site)"
export WP_CORE_DIR WP_TESTS_DIR WP_TESTS_PHPUNIT_POLYFILLS_PATH
export DB_HOST DB_USER DB_PASSWORD
vendor/bin/phpunit -c "${TARGET_DIR}/phpunit.xml.dist" || EXIT_CODE=$?

# -----------------------------
# If multisite config exists, run it, otherwise skip
# -----------------------------
if [ -f "${TARGET_DIR}/tests/phpunit/multisite.xml" ]; then
  echo ">> Running PHPUnit (multisite)"
  vendor/bin/phpunit -c "${TARGET_DIR}/tests/phpunit/multisite.xml" || EXIT_CODE=${EXIT_CODE:-0}
else
  echo ">> Multisite config not found; skipping multisite run"
fi

exit ${EXIT_CODE:-0}
