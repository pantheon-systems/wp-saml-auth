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
# ---- WP tests library (deterministic path) ----
echo "Preparing WP tests lib in ${WP_TESTS_DIR}..."
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"

BASE_TAG="https://develop.svn.wordpress.org/tags/${WP_VERSION}"
BASE_TRUNK="https://develop.svn.wordpress.org/trunk"

echo "Checking out phpunit tests from tag: ${BASE_TAG}/tests/phpunit"
if ! svn -q checkout "${BASE_TAG}/tests/phpunit" "${WP_TESTS_DIR}"; then
  echo "Tag checkout failed, trying trunk..."
  rm -rf "${WP_TESTS_DIR}"
  svn -q checkout "${BASE_TRUNK}/tests/phpunit" "${WP_TESTS_DIR}"
fi

# config sample is stored at repo root, not under tests/phpunit
if ! svn -q export "${BASE_TAG}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"; then
  echo "Tag did not have wp-tests-config-sample.php, trying trunk..."
  svn -q export "${BASE_TRUNK}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"
fi

if [[ ! -f "${WP_TESTS_DIR}/includes/functions.php" ]]; then
  echo "ERROR: tests lib is missing includes/functions.php"
  find "${WP_TESTS_DIR}" -maxdepth 2 -type f -name functions.php | sed 's/^/ -> /'
  exit 1
fi

cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/youremptytestdbnamehere/${DB_NAME}/" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourusernamehere/${DB_USER}/" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourpasswordhere/${DB_PASSWORD}/" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s|localhost|${DB_HOST}|" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s|/path/to/wordpress/|${WP_CORE_DIR}/|" "${WP_TESTS_DIR}/wp-tests-config.php"

echo "WP tests lib ready at ${WP_TESTS_DIR}"
ls -l "${WP_TESTS_DIR}/includes/functions.php" || true

echo "/bin files are up to date"
