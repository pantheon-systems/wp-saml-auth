#!/usr/bin/env bash
set -euo pipefail

# ---- Config (with sane defaults) ----
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-root}"
DB_NAME="${DB_NAME:-wp_test}"
WP_TESTS_DIR="${WP_TESTS_DIR:-/tmp/wordpress-tests-lib}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"

# Make the temp paths unique per job to avoid collisions across matrix runs.
# (Keeps your env overrides if you set them in the workflow.)
if [[ -n "${GITHUB_RUN_ID:-}" && -n "${GITHUB_JOB:-}" ]]; then
  WP_TESTS_DIR="${WP_TESTS_DIR}-${GITHUB_RUN_ID}-${GITHUB_JOB}"
  WP_CORE_DIR="${WP_CORE_DIR}-${GITHUB_RUN_ID}-${GITHUB_JOB}"
fi

# ---- Ensure tools present ----
if ! command -v svn >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "svn not found; installing..."
    sudo apt-get update -y
    sudo apt-get install -y subversion
  else
    echo "svn is required"
    exit 1
  fi
fi

# ---- DB ----
echo "Creating database ${DB_NAME}..."
mysql -h"${DB_HOST}" -u"${DB_USER}" -p"${DB_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"

# ---- WP core ----
echo "Preparing WP core in ${WP_CORE_DIR}..."
rm -rf "${WP_CORE_DIR}"
mkdir -p "${WP_CORE_DIR}"

wp core download --path="${WP_CORE_DIR}" --skip-content --version=latest --force
WP_VERSION="$(wp --path="${WP_CORE_DIR}" core version)"
echo "Resolved WP version: ${WP_VERSION}"

# Minimal single-site install so CLI can resolve paths; harmless for unit tests.
if ! wp --path="${WP_CORE_DIR}" core is-installed >/dev/null 2>&1; then
  wp core config --path="${WP_CORE_DIR}" --dbname="${DB_NAME}" --dbuser="${DB_USER}" --dbpass="${DB_PASSWORD}" --dbhost="${DB_HOST}" --skip-check
  wp core install --path="${WP_CORE_DIR}" --url="http://example.com" --title="Test" --admin_user=admin --admin_password=admin --admin_email=test@example.com || true
fi

# ---- WP tests library ----
echo "Preparing WP tests lib in ${WP_TESTS_DIR}..."
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"

# Pull tests matching the resolved WP version so wp-tests-config-sample.php exists
svn -q checkout "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit/" "${WP_TESTS_DIR}"

# Create wp-tests-config.php if missing
if [[ ! -f "${WP_TESTS_DIR}/wp-tests-config.php" ]]; then
  cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s/youremptytestdbnamehere/${DB_NAME}/" "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s/yourusernamehere/${DB_USER}/" "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s/yourpasswordhere/${DB_PASSWORD}/" "${WP_TESTS_DIR}/wp-tests-config.php"
  sed -i "s|localhost|${DB_HOST}|" "${WP_TESTS_DIR}/wp-tests-config.php"
  # Point ABSPATH to our freshly-downloaded core
  sed -i "s|/path/to/wordpress/|${WP_CORE_DIR}/|" "${WP_TESTS_DIR}/wp-tests-config.php"
fi

echo "/bin files are up to date"
