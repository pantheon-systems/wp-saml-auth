#!/usr/bin/env bash
set -euo pipefail
set -x

: "${TERMINUS_SITE:?TERMINUS_SITE not set}"
: "${TERMINUS_ENV:?TERMINUS_ENV not set}"
: "${SIMPLESAMLPHP_VERSION:=2.4.0}"
: "${WORDPRESS_ADMIN_USERNAME:=pantheon}"
: "${WORDPRESS_ADMIN_EMAIL:=no-reply@getpantheon.com}"
: "${WORDPRESS_ADMIN_PASSWORD:=pantheon}"

BASE_URL="http://${TERMINUS_ENV}-${TERMINUS_SITE}.pantheonsite.io"

retry() { n=0; until "$@" || [ $n -ge 3 ]; do n=$((n+1)); sleep $((2*n)); done; }

terminus --version
terminus auth:whoami

# Create multidev if it doesn't exist
if ! terminus env:info "${TERMINUS_SITE}.${TERMINUS_ENV}" >/dev/null 2>&1; then
  retry terminus multidev:create "${TERMINUS_SITE}.dev" "${TERMINUS_ENV}" --yes
fi

# Ensure SFTP mode to allow file ops during setup
# Ensure SFTP mode (so we can write files)
terminus connection:set "$TERMINUS_SITE.$TERMINUS_ENV" sftp || true

# Write a small MU plugin that mirrors #user_login/#user_pass to alias fields "username"/"password"
terminus wp "$TERMINUS_SITE.$TERMINUS_ENV" -- eval '
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
                var syncing = false;
                function sync(a, b) {
                    if (syncing) return;
                    syncing = true;
                    if (b.value !== a.value) b.value = a.value;
                    syncing = false;
                }
                orig.addEventListener("input", function(){ sync(orig, alias); });
                alias.addEventListener("input", function(){ sync(alias, orig); });
                sync(orig, alias);
            }
            ensureAlias("#user_login", "username", "username");
            ensureAlias("#user_pass",  "password", "password");
        })();
    </script>
    <?php
});
PHP;

file_put_contents($dir . "/ci-login-field-aliases.php", $code);
echo "Wrote MU plugin: {$dir}/ci-login-field-aliases.php\n";
'

# Commit & clear cache so it goes live
terminus env:commit "$TERMINUS_SITE.$TERMINUS_ENV" --message="CI: add MU plugin to alias login fields" --force
terminus env:clear-cache "$TERMINUS_SITE.$TERMINUS_ENV"

echo "Behat environment prepared at ${BASE_URL}"
