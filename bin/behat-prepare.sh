#!/usr/bin/env bash
# Prepares a Pantheon Multidev for Behat and installs a server-rendered MU plugin
# that exposes "username" & "password" fields for tests (no JS required).

set -euo pipefail

: "${TERMINUS_SITE:?TERMINUS_SITE is required}"
: "${TERMINUS_ENV:?TERMINUS_ENV is required}"
: "${SIMPLESAMLPHP_VERSION:=1.18.0}"

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

log(){ printf '== %s ==\n' "$*"; }
note(){ printf 'Notice:  %s\n' "$*"; }
warn(){ printf 'Warning: %s\n' "$*" >&2; }

log "Behat prepare"
echo "TERMINUS_SITE=${TERMINUS_SITE}"
echo "TERMINUS_ENV=${TERMINUS_ENV}"
echo "SIMPLESAMLPHP_VERSION=${SIMPLESAMLPHP_VERSION}"

log "== Terminus version: =="
terminus --version || true
echo

log "== Ensuring Multidev environment ${SITE_ENV} =="
if ! terminus env:info "${SITE_ENV}" >/dev/null 2>&1; then
  note "Multidev ${SITE_ENV} does not exist. Creating from dev…"
  terminus env:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}"
else
  note "Multidev ${SITE_ENV} already exists."
fi

if terminus env:view "${SITE_ENV}" --print >/dev/null 2>&1; then
  note "OK >> $(terminus env:view "${SITE_ENV}" --print) responded"
fi

log "== Checking if WordPress is installed on appserver… =="
if ! terminus wp "${SITE_ENV}" -- 'core is-installed' >/dev/null 2>&1; then
  warn "wp-cli or core not available on appserver; continuing (tests target HTTP)"
fi

log "== Staging SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} (if required by tests)… =="
note "No files staged (placeholder)."

log "== Switching ${SITE_ENV} to SFTP mode so we can write MU plugins… =="
terminus connection:set "${SITE_ENV}" sftp || true

# ---------------- MU plugin (Base64 inline payload) ----------------
log "== Writing MU plugin for Behat login field aliases… =="

read -r -d '' MU_PLUGIN_PHP <<'PHP'
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
PHP

# Encode once, inline to wp-cli
B64="$(printf '%s' "${MU_PLUGIN_PHP}" | base64 -w0 || base64 <<<"${MU_PLUGIN_PHP}" | tr -d '\n')"

# Use a single-line eval so wp-cli receives the PHP as an argument (stdin is ignored by wp eval)
terminus wp "${SITE_ENV}" -- "eval \"\
\$dir = ABSPATH . 'wp-content/mu-plugins'; \
if (!is_dir(\$dir)) { mkdir(\$dir, 0775, true); } \
\$code = base64_decode('${B64}'); \
\$target = \$dir . '/ci-login-field-aliases.php'; \
if (file_put_contents(\$target, \$code) === false) { \
    fwrite(STDERR, 'Failed to write MU plugin to ' . \$target . PHP_EOL); \
    exit(1); \
} \
echo 'Wrote MU plugin: ' . \$target . PHP_EOL; \
\""

log "== Committing MU plugin to ${SITE_ENV}… =="
terminus env:commit "${SITE_ENV}" --message="CI: add MU plugin to alias login fields" --force || true

log "== Clearing environment cache… =="
terminus env:clear-cache "${SITE_ENV}"

log "Behat prepare finished."
