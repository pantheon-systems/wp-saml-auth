#!/usr/bin/env bash
set -euo pipefail

# ------- Inputs / defaults -------
: "${DB_HOST:=127.0.0.1}"
: "${DB_USER:=root}"
: "${DB_PASSWORD:=root}"
: "${DB_NAME:=wp_test}"
: "${WP_VERSION:=6.8.3}"
: "${WP_CORE_DIR:=/tmp/wordpress}"
: "${WP_TESTS_DIR:=/tmp/wordpress-tests-lib}"
: "${WP_DEBUG:=1}"

# Required by the WP test suite
export WP_PHP_BINARY="${WP_PHP_BINARY:-"$(command -v php)"}"

echo "== Ensuring dependencies... =="

# Clean up partial/invalid installs only (don’t nuke good caches)
ensure_clean_dir() {
  local path="$1"
  local marker="$2"
  if [ -d "$path" ] && [ ! -f "$path/$marker" ]; then
    rm -rf "$path"
  fi
}

# 1) WordPress core -----------------------------------------------------------
ensure_clean_dir "$WP_CORE_DIR" ".wp-installed.ok"
if [ ! -f "$WP_CORE_DIR/.wp-installed.ok" ]; then
  echo "== Downloading WordPress core into $WP_CORE_DIR... =="
  tmpcore="$(mktemp -d)"
  curl -fsSL "https://wordpress.org/wordpress-${WP_VERSION}.tar.gz" -o "${tmpcore}/wp.tgz"
  mkdir -p "$WP_CORE_DIR"
  tar -xzf "${tmpcore}/wp.tgz" -C "${tmpcore}"
  # Extracted into ${tmpcore}/wordpress — move atomically
  rsync -a --delete "${tmpcore}/wordpress/" "$WP_CORE_DIR/"
  touch "$WP_CORE_DIR/.wp-installed.ok"
  rm -rf "$tmpcore"
  echo "==   WP_VERSION=${WP_VERSION} =="
fi

# 2) WP tests library ---------------------------------------------------------
ensure_clean_dir "$WP_TESTS_DIR" ".wp-tests.ok"
if [ ! -f "$WP_TESTS_DIR/.wp-tests.ok" ]; then
  echo "== Preparing WP tests lib in $WP_TESTS_DIR (WP ${WP_VERSION}) =="
  mkdir -p "$WP_TESTS_DIR"

  # Pull test suite from develop.svn.wordpress.org
  #   Includes: includes/, data/, etc.
  svn export --quiet "https://develop.svn.wordpress.org/tags/${WP_VERSION}/tests/phpunit" "$WP_TESTS_DIR"

  # We also need the sample config file (outside tests/phpunit)
  curl -fsSL "https://develop.svn.wordpress.org/tags/${WP_VERSION}/wp-tests-config-sample.php" \
    -o "$WP_TESTS_DIR/wp-tests-config-sample.php"

  # Create wp-tests-config.php from scratch (avoids “cannot stat” issues)
  cat > "$WP_TESTS_DIR/wp-tests-config.php" <<PHP
<?php
// ** MySQL settings ** //
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASSWORD}' );
define( 'DB_HOST',     '${DB_HOST}' );
define( 'DB_CHARSET',  'utf8' );
define( 'DB_COLLATE',  '' );

// WP test suite required constants
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL',  'admin@example.org' );
define( 'WP_TESTS_TITLE',  'Test Blog' );
define( 'WP_PHP_BINARY',   '${WP_PHP_BINARY}' );

// Misc
\$table_prefix = 'wptests_';
define( 'WP_DEBUG', ${WP_DEBUG} );

// Path to the WordPress codebase under test.
define( 'ABSPATH', '${WP_CORE_DIR}/' );
PHP

  touch "$WP_TESTS_DIR/.wp-tests.ok"
fi

echo "== Done PHPUnit bootstrap =="
