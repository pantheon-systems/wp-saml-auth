#!/usr/bin/env bash
# Reliable, versioned setup of WordPress Core + WP test library.
# Works for all PHP versions in CI.

set -euo pipefail

# ---- Required envs (already present in your jobs) ---------------------------
: "${WP_VERSION:?WP_VERSION is required (e.g. 6.8.3)}"
: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${DB_HOST:?DB_HOST is required}"
: "${WP_CORE_DIR:?WP_CORE_DIR is required (e.g. /tmp/wordpress/)}"
: "${WP_TESTS_DIR:?WP_TESTS_DIR is required (e.g. /tmp/wordpress-tests-lib)}"

echo "== Ensuring dependencies (svn) =="
if ! command -v svn >/dev/null 2>&1; then
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y subversion >/dev/null
fi

# Clean any previous partial state to avoid "already exists" or stale files
echo "== Cleaning previous temp dirs =="
rm -rf "${WP_CORE_DIR}" "${WP_TESTS_DIR}" /tmp/wp-develop || true
mkdir -p "${WP_CORE_DIR}" "${WP_TESTS_DIR}"

SVN_BASE="https://develop.svn.wordpress.org/tags/${WP_VERSION}"

echo "== Fetching WordPress develop tag ${WP_VERSION} =="
# Export only what we need. This prevents path drift and flaky layouts.
svn export --quiet "${SVN_BASE}/src" "${WP_CORE_DIR}"
svn export --quiet "${SVN_BASE}/tests/phpunit" "${WP_TESTS_DIR}"

echo "== Preparing WP tests lib in ${WP_TESTS_DIR} =="
SAMPLE_CFG="${WP_TESTS_DIR}/wp-tests-config-sample.php"
TARGET_CFG="${WP_TESTS_DIR}/wp-tests-config.php"

if [ ! -f "${SAMPLE_CFG}" ]; then
  echo "Sample config not found in ${WP_TESTS_DIR}"
  exit 1
fi

cp "${SAMPLE_CFG}" "${TARGET_CFG}"

# Update DB constants + ABSPATH in wp-tests-config.php
php -d detect_unicode=0 -r '
$cfgPath = getenv("TARGET_CFG");
$cfg = file_get_contents($cfgPath);

$repls = [
  "/define\\(\\s*\\x27DB_NAME\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" =>
    "define( \x27DB_NAME\x27, \x27".getenv("DB_NAME")."\x27 );",
  "/define\\(\\s*\\x27DB_USER\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" =>
    "define( \x27DB_USER\x27, \x27".getenv("DB_USER")."\x27 );",
  "/define\\(\\s*\\x27DB_PASSWORD\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" =>
    "define( \x27DB_PASSWORD\x27, \x27".getenv("DB_PASSWORD")."\x27 );",
  "/define\\(\\s*\\x27DB_HOST\\x27\\s*,\\s*\\x27.*?\\x27\\s*\\);/" =>
    "define( \x27DB_HOST\x27, \x27".getenv("DB_HOST")."\x27 );",
  "/\\$table_prefix\\s*=\\s*\\x27wptests_\\x27\\s*;/" =>
    "$table_prefix = \x27wptests_\x27;",
  "/define\\(\\s*\\x27ABSPATH\\x27\\s*,\\s*.*?\\);/" =>
    "define( \x27ABSPATH\x27, \x27".rtrim(getenv("WP_CORE_DIR"),"/")."/\x27 );",
];

$cfg = preg_replace(array_keys($repls), array_values($repls), $cfg);
file_put_contents($cfgPath, $cfg);
' 2>/dev/null

echo "== Done: WP core at ${WP_CORE_DIR}, tests at ${WP_TESTS_DIR} =="
