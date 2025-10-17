#!/usr/bin/env bash
set -euo pipefail

# Required env (already provided by your workflow)
: "${DB_HOST:?}" "${DB_USER:?}" "${DB_PASSWORD:?}" "${DB_NAME:?}"
WP_CORE_DIR="${WP_CORE_DIR:-/tmp/wordpress}"
WP_TESTS_DIR="/tmp/wordpress-tests-lib"

echo "Ensuring dependencies..."
if ! command -v svn >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y subversion unzip
fi

# 1) Ensure WordPress core is present
if [[ ! -f "${WP_CORE_DIR}/wp-includes/version.php" ]]; then
  echo "Downloading WordPress core into ${WP_CORE_DIR}..."
  rm -rf "${WP_CORE_DIR}" /tmp/wordpress.zip /tmp/wordpress
  curl -fsSL -o /tmp/wordpress.zip https://wordpress.org/latest.zip
  unzip -q /tmp/wordpress.zip -d /tmp
  mkdir -p "$(dirname "${WP_CORE_DIR}")"
  mv /tmp/wordpress "${WP_CORE_DIR}"
fi

# 2) Detect WP version from core (guaranteed to exist now)
WP_VERSION="$(php -r "include '${WP_CORE_DIR}/wp-includes/version.php'; echo \$wp_version;")" || WP_VERSION="trunk"
echo "Detected WP ${WP_VERSION}"

# 3) Fetch WP tests library (tag first, then trunk)
TAG_URL="https://develop.svn.wordpress.org/tags/${WP_VERSION}"
TRUNK_URL="https://develop.svn.wordpress.org/trunk"

echo "Preparing WP tests lib in ${WP_TESTS_DIR}..."
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"

echo "• Trying tests/phpunit from tag: ${WP_VERSION}"
if ! svn -q export "${TAG_URL}/tests/phpunit" "${WP_TESTS_DIR}"; then
  echo "Tag export failed; using trunk tests/phpunit…"
  rm -rf "${WP_TESTS_DIR}"
  svn -q export "${TRUNK_URL}/tests/phpunit" "${WP_TESTS_DIR}"
fi

echo "• Getting wp-tests-config-sample.php..."
if ! svn -q export "${TAG_URL}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"; then
  echo "Sample export from tag failed; using trunk sample…"
  svn -q export "${TRUNK_URL}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config-sample.php"
fi

# 4) Sanity check
test -f "${WP_TESTS_DIR}/includes/functions.php" || { echo "ERROR: includes/functions.php missing"; exit 1; }

# 5) Write wp-tests-config.php pointing to your env/Core dir
cp "${WP_TESTS_DIR}/wp-tests-config-sample.php" "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/youremptytestdbnamehere/${DB_NAME}/"                "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourusernamehere/${DB_USER}/"                       "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s/yourpasswordhere/${DB_PASSWORD}/"                   "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s|localhost|${DB_HOST}|"                              "${WP_TESTS_DIR}/wp-tests-config.php"
sed -i "s|/path/to/wordpress/|${WP_CORE_DIR}/|"               "${WP_TESTS_DIR}/wp-tests-config.php"

echo "WP tests lib ready: ${WP_TESTS_DIR}/includes/functions.php"
