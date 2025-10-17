#!/usr/bin/env bash
set -euo pipefail

# Required:
#   TERMINUS_SITE (Pantheon site machine name) via secret PANTHEON_SITE
#   TERMINUS_ENV  (raw; we'll sanitize)
#   SIMPLESAMLPHP_VERSION
#   Terminus installed; PHP >= 8.2 already set by workflow
#   SSH agent loaded with PANTHEON_SSH_PRIVATE_KEY

SITE="${TERMINUS_SITE:-${PANTHEON_SITE:-}}"
RAW_ENV="${TERMINUS_ENV:?Missing TERMINUS_ENV}"
SSP="${SIMPLESAMLPHP_VERSION:-}"

if [ -z "${SITE}" ]; then
  echo "TERMINUS_SITE / PANTHEON_SITE is empty. Set the secret PANTHEON_SITE."; exit 1
fi

# Sanitize multidev to [a-z0-9-], <= 11 chars, starts with letter
ENV_SANITIZED="$(printf "%s" "${RAW_ENV}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
ENV_SANITIZED="${ENV_SANITIZED//./}"
ENV_SANITIZED="${ENV_SANITIZED//_/}"
[[ "${ENV_SANITIZED}" =~ ^[a-z] ]] || ENV_SANITIZED="ci${ENV_SANITIZED}"
ENV_SANITIZED="$(echo -n "${ENV_SANITIZED}" | cut -c1-11)"

echo "== Behat prepare =="
echo "== TERMINUS_SITE=${SITE} =="
echo "== TERMINUS_ENV(raw)=${RAW_ENV} -> ${ENV_SANITIZED} =="
echo "== SIMPLESAMLPHP_VERSION=${SSP} =="

echo "== Terminus version: =="
terminus --version

echo "== Ensuring Multidev ${SITE}.${ENV_SANITIZED} =="
if ! terminus env:info "${SITE}.${ENV_SANITIZED}" >/dev/null 2>&1; then
  terminus env:create "${SITE}.dev" "${ENV_SANITIZED}"
else
  echo "Multidev exists."
fi

BASE_URL="$(terminus env:view "${SITE}.${ENV_SANITIZED}" --print)"
echo "== OK >> ${BASE_URL} responded =="

echo "== Staging SimpleSAMLphp ${SSP} (placeholder)… =="
echo "No files staged."

echo "== Switching to SFTP to write MU plugin… =="
terminus connection:set "${SITE}.${ENV_SANITIZED}" sftp || true

echo "== Writing MU plugin for Behat login field aliases… =="

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
            ensureAlias("#user_login", "username", "username");
            ensureAlias("#user_pass",  "password", "password");
        })();
    </script>
    <?php
});
PHP

MU_PLUGIN_B64="$(printf "%s" "${MU_PLUGIN_PHP}" | base64 -w0)"
TARGET_REL="wp-content/mu-plugins/ci-login-field-aliases.php"

set +e
terminus wp "${SITE}.${ENV_SANITIZED}" -- wp --info >/dev/null 2>&1
HAS_WP=$?
set -e

if [ ${HAS_WP} -eq 0 ]; then
  echo "wp-cli available; writing via wp eval…"
  MU_PLUGIN_B64="${MU_PLUGIN_B64}" terminus wp "${SITE}.${ENV_SANITIZED}" -- wp eval '
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
  INFO=$(terminus connection:info "${SITE}.${ENV_SANITIZED}" --fields=sftp_username,sftp_host,sftp_port --format=tsv)
  SFTP_USER=$(echo "${INFO}" | awk '{print $1}')
  SFTP_HOST=$(echo "${INFO}" | awk '{print $2}')
  SFTP_PORT=$(echo "${INFO}" | awk '{print $3}')
  if [ -z "${SFTP_USER}" ] || [ -z "${SFTP_HOST}" ] || [ -z "${SFTP_PORT}" ]; then
    echo "Failed to get SFTP connection info"; exit 1
  fi
  ssh -p "${SFTP_PORT}" "${SFTP_USER}@${SFTP_HOST}" "mkdir -p code/wp-content/mu-plugins"
  echo "${MU_PLUGIN_B64}" | base64 -d | ssh -p "${SFTP_PORT}" "${SFTP_USER}@${SFTP_HOST}" "cat > code/${TARGET_REL}"
  echo "Committing MU plugin to ${SITE}.${ENV_SANITIZED}…"
  terminus env:commit "${SITE}.${ENV_SANITIZED}" --message='CI: add MU plugin to alias login fields' --force || true
fi

echo "Clearing environment cache…"
terminus env:clear-cache "${SITE}.${ENV_SANITIZED}"

echo "Behat prepare finished."
