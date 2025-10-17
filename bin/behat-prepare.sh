#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Pantheon Behat environment prep
# - Ensures Multidev exists
# - (Optionally) checks site responds
# - Switches to SFTP mode
# - Writes MU plugin that aliases #user_login/#user_pass to 'username'/'password'
#   to satisfy upstream Behat steps
# - Uses base64-encoded payload passed as a single arg to `terminus wp ... eval`
# ------------------------------------------------------------------------------

# ------- Required env -------
TERMINUS_SITE="${TERMINUS_SITE:?TERMINUS_SITE is required}"
TERMINUS_ENV="${TERMINUS_ENV:?TERMINUS_ENV is required}"
SIMPLESAMLPHP_VERSION="${SIMPLESAMLPHP_VERSION:-}"
SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

# ------- Logging helper -------
log() { printf '== %s ==\n' "$*"; }

log "Behat prepare"
log "TERMINUS_SITE=${TERMINUS_SITE}"
log "TERMINUS_ENV=${TERMINUS_ENV}"
[[ -n "${SIMPLESAMLPHP_VERSION}" ]] && log "SIMPLESAMLPHP_VERSION=${SIMPLESAMLPHP_VERSION}"

# Make sure terminus is on PATH in GitHub runners
export PATH="/usr/local/bin:/usr/bin:/bin${PATH:+:${PATH}}"

log "== Terminus version: =="
terminus --version

# ------- Ensure Multidev exists -------
log "== Ensuring Multidev environment ${SITE_ENV} =="
if ! terminus env:info "${SITE_ENV}" >/dev/null 2>&1; then
  echo "Multidev ${SITE_ENV} does not exist. Creating from dev…"
  terminus env:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}"
else
  echo "Multidev ${SITE_ENV} already exists."
fi

# ------- Basic health check (HTTP) -------
BASE_URL="$(terminus env:view "${SITE_ENV}" --print | sed -n 's/.*URL: *//p' | tr -d '\r')"
if [[ -n "${BASE_URL}" ]]; then
  if curl -fsS -o /dev/null "${BASE_URL}"; then
    log "OK >> ${BASE_URL} responded"
  else
    echo "Warning: ${BASE_URL} not responding yet (continuing)"
  fi
fi

# ------- We don't rely on remote wp-cli/core being present -------
log "== Checking if WordPress is installed on appserver… =="
if ! terminus wp "${SITE_ENV}" -- core version >/dev/null 2>&1; then
  echo "wp-cli or core not available on appserver; continuing (tests target HTTP)"
fi

# ------- (Optional) Stage SSP fixtures (placeholder) -------
if [[ -n "${SIMPLESAMLPHP_VERSION}" ]]; then
  log "== Staging SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} (if required by tests)… =="
  echo "No files staged (placeholder)."
fi

# ------- Switch to SFTP so we can write MU plugin -------
log "== Switching ${SITE_ENV} to SFTP mode so we can write MU plugins… =="
terminus connection:set "${SITE_ENV}" sftp || true

# ------- Write MU plugin via remote wp eval (base64 single-arg) -------
log "== Writing MU plugin for Behat login field aliases… =="

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

// Map POST fields server-side (works even if JS is stripped)
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

# Base64 (portable between GNU/BSD)
if base64 --help >/dev/null 2>&1; then
  B64="$(printf '%s' "${MU_PLUGIN_PHP}" | base64 -w0 2>/dev/null || printf '%s' "${MU_PLUGIN_PHP}" | base64 | tr -d '\n')"
else
  # Fallback (very rare)
  B64="$(python3 - <<'PY'
import sys, base64
print(base64.b64encode(sys.stdin.read().encode()).decode(), end="")
PY
  <<< "${MU_PLUGIN_PHP}")"
fi

PHP_CODE=$'\n'
PHP_CODE+="\$d=ABSPATH.'wp-content/mu-plugins';"
PHP_CODE+=" if(!is_dir(\$d)){mkdir(\$d,0775,true);}"
PHP_CODE+=" \$c=base64_decode('${B64}');"
PHP_CODE+=" \$t=\$d.'/ci-login-field-aliases.php';"
PHP_CODE+=" if(file_put_contents(\$t,\$c)===false){fwrite(STDERR,'Failed to write MU plugin to '.\$t.PHP_EOL); exit(1);} "
PHP_CODE+=" echo 'Wrote MU plugin: '.\$t.PHP_EOL;"

# Pass as a SINGLE ARG to remote wp-cli to avoid heredoc/escaping pitfalls
terminus wp "${SITE_ENV}" -- eval "${PHP_CODE}"

# Commit and clear cache (kept quiet if already committed)
log "== Committing MU plugin to ${SITE_ENV}… =="
terminus env:commit "${SITE_ENV}" --message="CI: add MU plugin to alias login fields" --force || true

log "== Clearing environment cache… =="
terminus env:clear-cache "${SITE_ENV}"

log "Behat prepare finished."
