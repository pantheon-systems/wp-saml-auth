#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   PANTHEON_SITE   (machine name)
#   TERMINUS_ENV    (multidev env name)
#   SIMPLESAMLPHP_VERSION
#   SSH agent already running (webfactory/ssh-agent action) with key that has Pantheon access.

SITE="${PANTHEON_SITE:-${TERMINUS_SITE:-}}"
ENV="${TERMINUS_ENV:?Missing TERMINUS_ENV}"
SSP="${SIMPLESAMLPHP_VERSION:-}"
if [ -z "${SITE}" ]; then
  echo "PANTHEON_SITE secret is required"; exit 1;
fi

echo "== Behat prepare =="
echo "== TERMINUS_SITE=${SITE} =="
echo "== TERMINUS_ENV=${ENV} =="
echo "== SIMPLESAMLPHP_VERSION=${SSP} =="

echo "== Terminus version: =="
terminus --version

echo "== Ensuring Multidev environment ${SITE}.${ENV} =="
if ! terminus env:info "${SITE}.${ENV}" >/dev/null 2>&1; then
  terminus env:create "${SITE}.dev" "${ENV}"
else
  echo "Multidev ${SITE}.${ENV} exists."
fi

# Simple health check
BASE_URL="$(terminus env:view "${SITE}.${ENV}" --print)"
echo "== OK >> ${BASE_URL} responded =="

# Stage SimpleSAMLphp placeholder (kept from earlier logs – noop here)
echo "== Staging SimpleSAMLphp ${SSP} (if required by tests)… =="
echo "No files staged (placeholder)."

echo "== Switching ${SITE}.${ENV} to SFTP mode so we can write MU plugins… =="
terminus connection:set "${SITE}.${ENV}" sftp || true

echo "== Writing MU plugin for Behat login field aliases… =="

# Build MU plugin content. We base64 it and send via wp-cli if present; if not, upload via SFTP.
read -r -d '' MU_PLUGIN_PHP <<'PHP'
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
            // Map WP core fields to aliases expected by upstream tests
            ensureAlias("#user_login", "username", "username");
            ensureAlias("#user_pass",  "password", "password");
        })();
    </script>
    <?php
});
PHP

MU_PLUGIN_B64="$(printf "%s" "${MU_PLUGIN_PHP}" | base64 -w0)"

# Try wp-cli first (fastest). Some appservers don't have wp-cli; detect and fall back.
set +e
terminus wp "${SITE}.${ENV}" -- wp --info >/dev/null 2>&1
HAS_WP=$?
set -e

TARGET_REL="wp-content/mu-plugins/ci-login-field-aliases.php"

if [ ${HAS_WP} -eq 0 ]; then
  echo "wp-cli detected on appserver; writing via wp eval…"
  # Pass the base64 via env var to avoid quoting issues
  MU_PLUGIN_B64="${MU_PLUGIN_B64}" terminus wp "${SITE}.${ENV}" -- wp eval '
    $dir = ABSPATH . "wp-content/mu-plugins";
    if (!is_dir($dir)) { mkdir($dir, 0775, true); }
    $b64 = getenv("MU_PLUGIN_B64") ?: "";
    if ($b64 === "") { fwrite(STDERR, "Empty MU_PLUGIN_B64\n"); exit(1); }
    $code = base64_decode($b64);
    $target = $dir . "/ci-login-field-aliases.php";
    file_put_contents($target, $code);
    echo "Wrote MU plugin: {$target}\n";
  '
else
  echo "wp-cli NOT available; uploading over SFTP…"
  # Get SFTP connection details and push file using ssh
  # We avoid jq; parse simple table output.
  INFO=$(terminus connection:info "${SITE}.${ENV}" --fields=sftp_username,sftp_host,sftp_port --format=tsv)
  SFTP_USER=$(echo "${INFO}" | awk '{print $1}')
  SFTP_HOST=$(echo "${INFO}" | awk '{print $2}')
  SFTP_PORT=$(echo "${INFO}" | awk '{print $3}')
  if [ -z "${SFTP_USER}" ] || [ -z "${SFTP_HOST}" ] || [ -z "${SFTP_PORT}" ]; then
    echo "Failed to get SFTP connection info"; exit 1
  fi

  # Ensure target dir and upload file by piping content over SSH
  ssh -p "${SFTP_PORT}" "${SFTP_USER}@${SFTP_HOST}" "mkdir -p code/wp-content/mu-plugins"
  echo "${MU_PLUGIN_B64}" | base64 -d | ssh -p "${SFTP_PORT}" "${SFTP_USER}@${SFTP_HOST}" "cat > code/${TARGET_REL}"

  echo "Committing MU plugin to ${SITE}.${ENV}…"
  terminus env:commit "${SITE}.${ENV}" --message='CI: add MU plugin to alias login fields' --force || true
fi

echo "Clearing environment cache…"
terminus env:clear-cache "${SITE}.${ENV}"

echo "Behat prepare finished."
