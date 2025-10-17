#!/usr/bin/env bash
# Sets up WordPress core and the WordPress tests library for local PHPUnit runs.

set -euo pipefail

# Required env (provided by CI)
: "${WP_CORE_DIR:?WP_CORE_DIR is required}"          # e.g. /tmp/wordpress/
: "${WP_TESTS_DIR:?WP_TESTS_DIR is required}"        # e.g. /tmp/wordpress-tests-lib
: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${DB_HOST:?DB_HOST is required}"

# Defaults
WP_VERSION="${WP_VERSION:-latest}"

log(){ printf '== %s ==\n' "$*"; }

log "Ensuring dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq unzip subversion >/dev/null

# ---------------- WordPress core ----------------
# Always start clean to avoid "move to a subdir of itself" errors
log "Downloading WordPress core into ${WP_CORE_DIR}..."
rm -rf "${WP_CORE_DIR}"
mkdir -p "${WP_CORE_DIR}"

# Determine the exact version (optional, but useful for logs)
if [[ "${WP_VERSION}" == "latest" ]]; then
  ZIP_URL="https://wordpress.org/latest.zip"
else
  ZIP_URL="https://wordpress.org/wordpress-${WP_VERSION}.zip"
fi

TMPDIR="$(mktemp -d)"
curl -fsSL "${ZIP_URL}" -o "${TMPDIR}/wp.zip"
unzip -q "${TMPDIR}/wp.zip" -d "${TMPDIR}"
# The zip expands to "${TMPDIR}/wordpress"
mv "${TMPDIR}/wordpress"/* "${WP_CORE_DIR}/"
rm -rf "${TMPDIR}"

# Get runtime WP version (for logging)
WP_VER_IN_CORE="$(php -r "include '${WP_CORE_DIR%/}/wp-includes/version.php'; echo \$wp_version;")" || WP_VER_IN_CORE="${WP_VERSION}"
log "  WP_VERSION=${WP_VER_IN_CORE}"

# ---------------- WP tests lib ----------------
log "Preparing WP tests lib in ${WP_TESTS_DIR} (WP ${WP_VER_IN_CORE})"
rm -rf "${WP_TESTS_DIR}"
mkdir -p "${WP_TESTS_DIR}"

# Prefer a tag that matches core, fall back to trunk
SVN_BASE="https://develop.svn.wordpress.org"
if svn ls "${SVN_BASE}/tags/${WP_VER_IN_CORE}/tests/phpunit" >/dev/null 2>&1; then
  SVN_PATH="${SVN_BASE}/tags/${WP_VER_IN_CORE}/tests/phpunit"
else
  echo "Tag not found; using trunk tests/phpunit…"
  SVN_PATH="${SVN_BASE}/trunk/tests/phpunit"
fi

# Export the whole tests/phpunit dir so we get wp-tests-config-sample.php
svn export -q "${SVN_PATH}" "${WP_TESTS_DIR}"

# ---------------- wp-tests-config.php ----------------
log "Creating wp-tests-config.php"
CONFIG_SAMPLE="${WP_TESTS_DIR}/wp-tests-config-sample.php"
CONFIG_DEST="${WP_TESTS_DIR}/wp-tests-config.php"

# Some older snapshots may miss the sample; generate if needed.
if [[ ! -f "${CONFIG_SAMPLE}" ]]; then
  cat > "${CONFIG_SAMPLE}" <<'PHP'
<?php
/* Path to the WordPress codebase you'd like to test. Add a trailing slash. */
define( 'ABSPATH', getenv('WP_CORE_DIR') . '/' );

/* Database settings */
define( 'DB_NAME',     getenv('DB_NAME') );
define( 'DB_USER',     getenv('DB_USER') );
define( 'DB_PASSWORD', getenv('DB_PASSWORD') );
define( 'DB_HOST',     getenv('DB_HOST') );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );

/* Authentication Unique Keys and Salts. */
define( 'AUTH_KEY',         'put your unique phrase here' );
define( 'SECURE_AUTH_KEY',  'put your unique phrase here' );
define( 'LOGGED_IN_KEY',    'put your unique phrase here' );
define( 'NONCE_KEY',        'put your unique phrase here' );
define( 'AUTH_SALT',        'put your unique phrase here' );
define( 'SECURE_AUTH_SALT', 'put your unique phrase here' );
define( 'LOGGED_IN_SALT',   'put your unique phrase here' );
define( 'NONCE_SALT',       'put your unique phrase here' );

$table_prefix = 'wptests_';
define( 'WP_DEBUG', true );
PHP
fi

cp "${CONFIG_SAMPLE}" "${CONFIG_DEST}"

# Replace values in config (keep this simple/safe)
php -r '
$cfg = getenv("WP_TESTS_DIR") . "/wp-tests-config.php";
$c = file_get_contents($cfg);
$c = preg_replace("/define\(\s*'\''DB_NAME'\''\s*,\s*.*?\);/", "define( '\''DB_NAME'\'', getenv('\''DB_NAME'\''));", $c);
$c = preg_replace("/define\(\s*'\''DB_USER'\''\s*,\s*.*?\);/", "define( '\''DB_USER'\'', getenv('\''DB_USER'\''));", $c);
$c = preg_replace("/define\(\s*'\''DB_PASSWORD'\''\s*,\s*.*?\);/", "define( '\''DB_PASSWORD'\'', getenv('\''DB_PASSWORD'\''));", $c);
$c = preg_replace("/define\(\s*'\''DB_HOST'\''\s*,\s*.*?\);/", "define( '\''DB_HOST'\'', getenv('\''DB_HOST'\''));", $c);
$c = preg_replace("/define\(\s*'\''ABSPATH'\''\s*,\s*.*?\);/", "define( '\''ABSPATH'\'', rtrim(getenv('\''WP_CORE_DIR'\''), '\''/'\'') . '\''/'\'' );", $c);
file_put_contents($cfg, $c);
'

log "Done."
