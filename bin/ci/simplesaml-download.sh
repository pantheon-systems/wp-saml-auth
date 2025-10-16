#!/usr/bin/env bash
set -euo pipefail

: "${SIMPLESAMLPHP_VERSION:?}"
: "${WP_TESTS_DIR:?}"

INSTALL_DIR="${WP_TESTS_DIR}/simplesamlphp"
mkdir -p "${INSTALL_DIR}"

if [[ "${SIMPLESAMLPHP_VERSION}" == "1.18.0" ]]; then
  URL="https://github.com/simplesamlphp/simplesamlphp/releases/download/v1.18.0/simplesamlphp-1.18.0.tar.gz"
else
  # 2.x sometimes publishes only the non -full tarball; prefer the plain tarball
  URL="https://github.com/simplesamlphp/simplesamlphp/releases/download/v${SIMPLESAMLPHP_VERSION}/simplesamlphp-${SIMPLESAMLPHP_VERSION}.tar.gz"
fi

echo "Downloading SimpleSAMLphp ${SIMPLESAMLPHP_VERSION} from ${URL}"
curl -fsSL "${URL}" | tar -zxf - --strip-components=1 -C "${INSTALL_DIR}"

# Ensure config dir exists for tests
mkdir -p "${INSTALL_DIR}/config"
: > "${INSTALL_DIR}/config/config.php"

# Legacy 1.x autoloader check (for sanity)
if [[ "${SIMPLESAMLPHP_VERSION}" == "1.18.0" ]]; then
  test -f "${INSTALL_DIR}/lib/_autoload.php"
fi
