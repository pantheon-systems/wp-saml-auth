# =========================
# WP PHPUnit tests library
# =========================
set -euo pipefail

: "${WP_CORE_DIR:?WP_CORE_DIR not set}"
: "${DB_NAME:?}"
: "${DB_USER:?}"
: "${DB_PASSWORD:?}"
: "${DB_HOST:?}"
export WP_TESTS_DIR="/tmp/wordpress-tests-lib"

# Derive WP_VERSION from the core (works without wp-cli)
WP_VERSION="${WP_VERSION:-$(php -r "include '${WP_CORE_DIR}/wp-includes/version.php'; echo \$wp_version;")}"
TAG_URL="https://develop.svn.wordpress.org/tags/${WP_VERSION}"
TRUNK_URL="https://develop.svn.wordpress.org/trunk"

echo "Preparing WP tests lib in ${WP_TESTS_DIR} (WP ${WP_VERSION})"
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"

# 1) Checkout tests/phpunit from tag; fall back to trunk
if ! svn -q checkout "${TAG_URL}/tests/phpunit" "${WP_TESTS_DIR}"; then
  echo "Tag checkout failed; using trunk tests/phpunit…"
  rm -rf "${WP_TESTS_DIR}"
  svn -q checkout "${TRUNK_URL}/tests/phpunit" "${WP_TESTS_DIR}"
fi

# 2) Export wp-tests-config-sample.php (lives at repo root)
if ! svn -q export "${TAG_URL}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"; then
  echo "Could not export config from tag; using trunk sample…"
  svn -q export "${TRUNK_URL}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"
fi

# 3) Sanity: includes/functions.php must exist
if [[ ! -f "${WP_TESTS_DIR}/includes/functions.php" ]]; then
  echo "ERROR: ${WP_TESTS_DIR}/includes/functions.php missing"
  ls -la "${WP_TESTS_DIR}" || true
  exit 1
fi

# 4) Write wp-tests-config.php
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/youremptytestdbnamehere/${DB_NAME}/" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourusernamehere/${DB_USER}/"        "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourpasswordhere/${DB_PASSWORD}/"    "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s|localhost|${DB_HOST}|"               "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s|/path/to/wordpress/|${WP_CORE_DIR}/|" "${WP_TESTS_DIR}/wp-tests-config.php"

echo "WP tests lib ready:"
ls -l "${WP_TESTS_DIR}/includes/functions.php"
