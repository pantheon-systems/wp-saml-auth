#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Pantheon Behat environment prep
# - Ensures Multidev exists
# - Switches to SFTP
# - Writes MU plugin that aliases #user_login/#user_pass to 'username'/'password'
#   (first try: `wp eval`; fallback: `wp eval --skip-wordpress` to /code/)
# - Single-argument base64 payload to avoid heredoc/escaping issues
# ------------------------------------------------------------------------------

# ------- Required env -------
TERMINUS_SITE="${TERMINUS_SITE:?TERMINUS_SITE is required}"
TERMINUS_ENV="${TERMINUS_ENV:?TERMINUS_ENV is required}"
SIMPLESAMLPHP_VERSION="${SIMPLESAMLPHP_VERSION:-}"
SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

log(){ printf '== %s ==\n' "$*"; }

log "Behat prepare"
log "TERMINUS_SITE=${TERMINUS_SITE}"
log "TERMINUS_ENV=${TERMINUS_ENV}"
[[ -n "${SIMPLESAMLPHP_VERSION}" ]] && log "SIMPLESAMLPHP_VERSION=${SIMPLESAMLPHP_VERSION}"

export PATH="/usr/local/bin:/usr/bin:/bin${PATH:+:${PATH}}"

log "== Terminus version: =="
terminus --version

# ------- Ensure Multidev -------
log "== Ensuring Multidev environment ${SITE_ENV} =="
if ! terminus env:info "${SITE_ENV}" >/dev/null 2>&1; then
  echo "Multidev ${SITE_ENV} does not exist. Creating from dev…"
  terminus env:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}"
else
  echo "Multidev ${SITE_ENV} already exists."
fi

# ------- Optional fixtures banner -------
if [[ -n "${SIMPLESAMLPHP_VERSION}" ]]; then
  log "== Staging SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} (if required by tests)… =="
  echo "No files staged (placeholder)."
fi

# ------- Switch to SFTP so we can write MU plugin -------
log "== Switching ${SITE_ENV} to SFTP mode so we can write MU plugins… =="
terminus connection:set "${SITE_ENV}" sftp || true

# ------- MU plugin payload -------
read -r -d '' MU_PLUGIN_PHP <<'PHP'
<?php
/**
 * Plugin Name: CI - Login Field Aliases (server-rendered)
 * Description: Adds hidden 'username' and 'password' inputs and maps them to core fields for Behat.
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
    <script type="text/javascript">
      (function() {
        function mapAlias(origSel, aliasId) {
          var orig = document.querySelector(origSel);
          var alias = document.getElementById(aliasId);
          if (!orig || !alias) return;
          var syncing = false;
          function sync(a, b) {
            if (syncing) return;
            syncing = true;
            if (b.value !== a.value) b.value = a.value;
            syncing = false;
          }
          sync(orig, alias);
          orig.addEventListener('input', function(){ sync(orig, alias); });
          alias.addEventListener('input', function(){ sync(alias, orig); });
        }
        mapAlias('#user_login', 'username');
        mapAlias('#user_pass',  'password');
      })();
    </script>
    <?php
});

// Server-side POST mapping (works even if JS is stripped)
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

# Base64 payload as single argument
if base64 --help >/dev/null 2>&1; then
  B64="$(printf '%s' "${MU_PLUGIN_PHP}" | base64 -w0 2>/dev/null || printf '%s' "${MU_PLUGIN_PHP}" | base64 | tr -d '\n')"
else
  B64="$(python3 - <<'PY'
import sys, base64
print(base64.b64encode(sys.stdin.read().encode()).decode(), end="")
PY
  <<< "${MU_PLUGIN_PHP}")"
fi

# First attempt: wp eval with WordPress loaded (ABSPATH available)
PHP_WP=$'\n'
PHP_WP+="\$d=ABSPATH.'wp-content/mu-plugins';"
PHP_WP+=" if(!is_dir(\$d)){mkdir(\$d,0775,true);}"
PHP_WP+=" \$c=base64_decode('${B64}');"
PHP_WP+=" \$t=\$d.'/ci-login-field-aliases.php';"
PHP_WP+=" if(file_put_contents(\$t,\$c)===false){fwrite(STDERR,'Failed to write MU plugin to '.\$t.PHP_EOL); exit(1);} "
PHP_WP+=" echo 'Wrote MU plugin: '.\$t.PHP_EOL;"

set +e
terminus wp "${SITE_ENV}" -- eval "${PHP_WP}"
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  # Fallback: wp eval --skip-wordpress and write to /code/ (Pantheon docroot)
  PHP_SKIP=$'\n'
  PHP_SKIP+="\$d='/code/wp-content/mu-plugins';"
  PHP_SKIP+=" if(!is_dir(\$d)){mkdir(\$d,0775,true);}"
  PHP_SKIP+=" \$c=base64_decode('${B64}');"
  PHP_SKIP+=" \$t=\$d.'/ci-login-field-aliases.php';"
  PHP_SKIP+=" if(file_put_contents(\$t,\$c)===false){fwrite(STDERR,'Failed to write MU plugin to '.\$t.PHP_EOL); exit(1);} "
  PHP_SKIP+=" echo 'Wrote MU plugin: '.\$t.PHP_EOL;"

  terminus wp "${SITE_ENV}" -- eval --skip-wordpress "${PHP_SKIP}"
fi

# Commit and clear cache
log "== Committing MU plugin to ${SITE_ENV}… =="
terminus env:commit "${SITE_ENV}" --message="CI: add MU plugin to alias login fields" --force || true

log "== Clearing environment cache… =="
terminus env:clear-cache "${SITE_ENV}"

log "Behat prepare finished."
