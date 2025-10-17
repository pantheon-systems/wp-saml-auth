#!/usr/bin/env bash
set -euo pipefail

# -------- Config & sanity checks --------
: "${TERMINUS_SITE:?TERMINUS_SITE is required}"
: "${TERMINUS_ENV:?TERMINUS_ENV is required}"
: "${SIMPLESAMLPHP_VERSION:=}"            # Optional; used by tests outside this script
: "${WORDPRESS_ADMIN_USERNAME:=pantheon}" # Optional; used by other steps
: "${WORDPRESS_ADMIN_EMAIL:=no-reply@getpantheon.com}"
: "${WORDPRESS_ADMIN_PASSWORD:=pantheon}"

export PATH="/usr/local/bin:$PATH"

echo "== Behat prepare =="
echo "TERMINUS_SITE=${TERMINUS_SITE}"
echo "TERMINUS_ENV=${TERMINUS_ENV}"
echo "SIMPLESAMLPHP_VERSION=${SIMPLESAMLPHP_VERSION:-<not set>}"

echo "PATH=$(command -v terminus || true)"
echo "Terminus version:"
terminus --version || (echo "ERROR: terminus not found on PATH"; exit 1)

SITE_ENV="${TERMINUS_SITE}.${TERMINUS_ENV}"

# Small helper to show commands as they run
run() { echo "+ $*"; eval "$@"; }

# -------- Ensure Multidev exists --------
echo "Ensuring Multidev environment ${SITE_ENV}"
if ! terminus env:info "${SITE_ENV}" >/dev/null 2>&1; then
  echo "Multidev ${SITE_ENV} does not exist. Creating from dev…"
  # Create from 'dev' (change 'dev' if you need another source)
  run "terminus env:create ${TERMINUS_SITE}.dev ${TERMINUS_ENV}"
else
  echo "Multidev ${SITE_ENV} already exists."
fi

# -------- Basic WordPress sanity check --------
echo "Checking if WordPress is installed on appserver…"
# We don't fail the build if not installed — other steps might handle install.
terminus wp "${SITE_ENV}" -- wp core is-installed || echo "Note: wp core not installed (continuing)"

# -------- (Optional) Stage SimpleSAMLphp for tests --------
if [[ -n "${SIMPLESAMLPHP_VERSION}" ]]; then
  echo "Staging SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} (if required by tests)…"
  # Your pipeline/tooling may do this elsewhere; we just log here.
fi

# -------- Switch to SFTP (on-server dev) so we can write files --------
echo "Switching ${SITE_ENV} to SFTP mode so we can write MU plugins…"
# `connection:set` is idempotent; ignore if already sftp
run "terminus connection:set ${SITE_ENV} sftp || true"

# -------- Write MU plugin that exposes 'username' and 'password' aliases on login --------
# Use a PHP nowdoc (<<<'PHP') so no shell expansion breaks the payload.
echo "Writing MU plugin for Behat login field aliases…"
terminus wp "${SITE_ENV}" -- eval '
$dir = ABSPATH . "wp-content/mu-plugins";
if (!is_dir($dir)) { mkdir($dir, 0775, true); }

$code = <<<'PHP'
<?php
/**
 * Plugin Name: CI - Login Field Aliases
 * Description: Adds username/password aliases on the WP login form for Behat steps.
 */
add_action("login_form", function () {
    ?>
    <script type="text/javascript">
        (function() {
            function ensureAlias(originalSelector, aliasId, aliasName) {
                var orig = document.querySelector(originalSelector);
                if (!orig) return;

                // Create invisible alias input if needed
                var alias = document.getElementById(aliasId);
                if (!alias) {
                    alias = document.createElement("input");
                    alias.type = orig.type || "text";
                    alias.id = aliasId;
                    alias.name = aliasName;
                    alias.autocomplete = orig.autocomplete || "on";
                    alias.style.position = "absolute";
                    alias.style.opacity = "0";
                    alias.style.pointerEvents = "none";
                    alias.tabIndex = -1;
                    orig.parentNode.appendChild(alias);
                }

                // Keep values in sync both ways
                var syncing = false;
                function sync(a, b) {
                    if (syncing) return;
                    syncing = true;
                    if (b.value !== a.value) b.value = a.value;
                    syncing = false;
                }
                orig.addEventListener("input", function(){ sync(orig, alias); });
                alias.addEventListener("input", function(){ sync(alias, orig); });
                // Initialize once
                sync(orig, alias);
            }

            // Map WP core fields to aliases expected by upstream tests
            ensureAlias("#user_login", "username", "username");
            ensureAlias("#user_pass",  "password", "password");
        })();
    </script>
    <?php
});
PHP;

$target = $dir . "/ci-login-field-aliases.php";
file_put_contents($target, $code);
if (!file_exists($target)) {
    fwrite(STDERR, "Failed to write MU plugin to {$target}\n");
    exit(1);
}
echo "Wrote MU plugin: {$target}\n";
'

# -------- Commit & clear cache so the MU plugin activates --------
echo "Committing MU plugin to ${SITE_ENV}…"
# --force ensures a commit even if no changes are detected (idempotent in CI)
run "terminus env:commit ${SITE_ENV} --message='CI: add MU plugin to alias login fields' --force || true"

echo "Clearing environment cache…"
run "terminus env:clear-cache ${SITE_ENV}"

echo "Behat prepare finished."
