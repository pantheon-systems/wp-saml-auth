#!/usr/bin/env bash
set -euo pipefail

# ---- Config ----
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
DB_NAME="${DB_NAME:-wp_test}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"

# Make temp paths unique per job to avoid collisions.
if [[ -n "${GITHUB_RUN_ID:-}" && -n "${GITHUB_JOB:-}" ]]; then
  WP_TESTS_DIR="${WP_TESTS_DIR}-${GITHUB_RUN_ID}-${GITHUB_JOB}"
  WP_CORE_DIR="${WP_CORE_DIR}-${GITHUB_RUN_ID}-${GITHUB_JOB}"
fi

# ---- Ensure tools ----
if ! command -v svn >/dev/null 2>&1; then
  echo "svn not found; installing..."
  sudo apt-get update -y
  sudo apt-get install -y subversion
fi

if ! command -v wp >/dev/null 2>&1; then
  echo "wp-cli is required (add it via setup-php tools: composer, wp-cli)."
  exit 1
fi

# ---- DB ----
echo "Creating database ${DB_NAME}..."
mysql -h"${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`" || true

# ---- WP core ----
echo "Preparing WP core in ${WP_CORE_DIR}..."
rm -rf "${WP_CORE_DIR}"
mkdir -p "${WP_CORE_DIR}"
wp core download --path="${WP_CORE_DIR}" --skip-content --version=latest --force
WP_VERSION="$(wp --path="${WP_CORE_DIR}" core version)"
echo "Resolved WP version: ${WP_VERSION}"

# Minimal install so CLI can resolve paths (harmless for unit tests).
if ! wp --path="${WP_CORE_DIR}" core is-installed >/dev/null 2>&1; then
  wp core config --path="${WP_CORE_DIR}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" --dbhost="${DB_HOST}" --skip-check
  wp core install --path="${WP_CORE_DIR}" --url="http://example.com" --title="Test" --admin_user=admin --admin_password=admin --admin_email=test@example.com || true
fi

# ---- WP tests library ----
echo "Preparing WP tests lib in ${WP_TESTS_DIR}..."
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"

TAG_URL="https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit"
TRUNK_URL="https://develop.svn.wordpress.org/trunk/tests/phpunit"

echo "Checking out tests from tag: ${TAG_URL}"
if ! svn -q checkout "${TAG_URL}" "${WP_TESTS_DIR}"; then
  echo "Tag checkout failed, trying trunk..."
  rm -rf "${WP_TESTS_DIR}"
  svn -q checkout "${TRUNK_URL}" "${WP_TESTS_DIR}"
fi

if [[ ! -f "${WP_TESTS_DIR}/wp-tests-config-sample.php" ]]; then
  echo "wp-tests-config-sample.php still missing; trying trunk as fallback..."
  rm -rf "${WP_TESTS_DIR}"
  svn -q checkout "${TRUNK_URL}" "${WP_TESTS_DIR}"
fi

if [[ ! -f "${WP_TESTS_DIR}/wp-tests-config-sample.php" ]]; then
  echo "ERROR: Could not obtain WordPress tests library (config sample missing)."
  ls -la "${WP_TESTS_DIR}" || true
  exit 1
fi

# Create wp-tests-config.php
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/youremptytestdbnamehere/${DB_NAME}/" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourusernamehere/${DB_USER}/" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourpasswordhere/${DB_PASSWORD}/" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s|localhost|${DB_HOST}|" "${WP_TESTS_DIR}/wp-tests-config.php"
# Point ABSPATH to our downloaded core
sed -i "s|/path/to/wordpress/|${WP_CORE_DIR}/|" "${WP_TESTS_DIR}/wp-tests-config.php"

echo "/bin files are up to date"
