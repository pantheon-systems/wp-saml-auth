#!/usr/bin/env bash
# bin/behat-prepare.sh
#
# Prepares a Pantheon Multidev for Behat:
# - Ensures/creates the Multidev
# - (Optionally) stages SimpleSAMLphp version marker (tests read it)
# - Switches to SFTP so we can write code
# - Writes a server-rendered MU plugin that exposes "username" & "password"
#   fields for Behat (no JS required)
# - Commits and clears cache
#
# Expects these env vars (set by CI):
#   TERMINUS_SITE, TERMINUS_ENV, SIMPLESAMLPHP_VERSION
#   WORDPRESS_ADMIN_USERNAME, WORDPRESS_ADMIN_EMAIL, WORDPRESS_ADMIN_PASSWORD
#
# Notes:
# - We avoid JS because Mink/Goutte doesn’t execute it.
# - We use a PHP nowdoc in `wp eval` to avoid heredoc parsing issues.
# - We do NOT fail if WP-CLI is unavailable on the appserver; tests that need
#   it run against the public site URLs instead.

set -euo pipefail

# ------------------- Config & sanity -------------------
: "${TERMINUS_SITE:?TERMINUS_SITE is required}"
: "${TERMINUS_ENV:?TERMINUS_ENV is required}"
: "${SIMPLESAMLPHP_VERSION:=1.18.0}"

# Make sure Terminus is on PATH (GitHub Actions images usually have this already)
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

log() { printf '== %s ==\n' "$*" ; }
note() { printf '[notice] %s\n' "$*" ; }
warn() { printf '[warning] %s\n' "$*" >&2 ; }
die() { printf '[error] %s\n' "$*" >&2 ; exit 1 ; }

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

log "Behat prepare"
echo "TERMINUS_SITE=${TERMINUS_SITE}"
echo "TERMINUS_ENV=${TERMINUS_ENV}"
echo "SIMPLESAMLPHP_VERSION=${SIMPLESAMLPHP_VERSION}"

# ------------------- Terminus status -------------------
if ! command -v terminus >/dev/null 2>&1; then
  die "Terminus CLI not found on PATH"
fi

log "Terminus version:"
terminus --version || true
echo

# ------------------- Ensure Multidev exists -------------------
log "Ensuring Multidev environment ${SITE_ENV}"
if ! terminus env:info "${SITE_ENV}" >/dev/null 2>&1; then
  note "Multidev ${SITE_ENV} does not exist. Creating from dev…"
  terminus env:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}"
else
  note "Multidev ${SITE_ENV} already exists."
fi

# Small site check
if terminus env:view "${SITE_ENV}" --print > /dev/null 2>&1; then
  note "OK >> $(terminus env:view "${SITE_ENV}" --print) responded"
fi

# ------------------- (Optional) WordPress presence check -------------------
log "Checking if WordPress is installed on appserver…"
# On some Pantheon upstreams the appserver doesn't ship with wp-cli. That's OK.
if ! terminus wp "${SITE_ENV}" -- 'core is-installed' >/dev/null 2>&1; then
  warn "wp-cli or core not available on appserver; continuing (tests target HTTP)"
else
  note "Command: ${SITE_ENV} -- wp core is-installed"
fi

# ------------------- SimpleSAMLphp staging hint (no-op placeholder) -------------------
log "Staging SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} (if required by tests)…"
# If your tests require dropping assets/config into files/ or code/,
# add that logic here (rsync/terminus:drush/etc). We only log for now.
note "No files staged (placeholder)."

# ------------------- Switch to SFTP so we can write MU plugins -------------------
log "Switching ${SITE_ENV} to SFTP mode so we can write MU plugins…"
terminus connection:set "${SITE_ENV}" sftp || true

# ------------------- Write server-rendered MU plugin -------------------
# We write via wp eval on the appserver, which writes to /code (Git mode).
log "Writing MU plugin for Behat login field aliases…"

terminus wp "${SITE_ENV}" -- 'eval' <<'PHP'
<?php
$dir = ABSPATH . "wp-content/mu-plugins";
if (!is_dir($dir)) { mkdir($dir, 0775, true); }

$code = <<<'PLUGIN'
<?php
/**
 * Plugin Name: CI - Login Field Aliases (server-rendered)
 * Description: Adds hidden 'username' and 'password' inputs and maps them to core fields for Behat (no JS required).
 * Author: CI
 */

add_action('login_form', function () {
    ?>
    <style>.ci-alias{position:absolute;left:-9999px;opacity:0;pointer-events:none;}</style>
    <p class="ci-alias">
        <label for="username">Username</label>
        <input type="text" name="username" id="username" autocomplete="username">
    </p>
    <p class="ci-alias">
        <label for="password">Password</label>
        <input type="password" name="password" id="password" autocomplete="current-password">
    </p>
    <?php
});

/**
 * Copy alias fields into the keys WP expects ('log'/'pwd' or 'user_login'/'user_pass')
 * before authentication runs.
 */
add_filter('authenticate', function ($user) {
    if (empty($_POST['log']) && !empty($_POST['username'])) {
        $_POST['log'] = $_POST['username'];
        $_POST['user_login'] = $_POST['username'];
    }
    if (empty($_POST['pwd']) && !empty($_POST['password'])) {
        $_POST['pwd'] = $_POST['password'];
        $_POST['user_pass'] = $_POST['password'];
    }
    return $user;
}, 0);
PLUGIN;

$target = $dir . "/ci-login-field-aliases.php";
if (false === file_put_contents($target, $code)) {
    fwrite(STDERR, "Failed to write MU plugin to {$target}\n");
    exit(1);
}
echo "Wrote MU plugin: {$target}\n";
PHP

# ------------------- Commit & clear cache -------------------
log "Committing MU plugin to ${SITE_ENV}…"
terminus env:commit "${SITE_ENV}" --message="CI: add MU plugin to alias login fields" --force || true

log "Clearing environment cache…"
terminus env:clear-cache "${SITE_ENV}"

log "Behat prepare finished."
