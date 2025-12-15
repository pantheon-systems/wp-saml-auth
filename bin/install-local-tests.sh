#!/usr/bin/env bash
set -e

# shellcheck disable=SC1091
echo "DEBUG: About to source helpers.sh from $(dirname "$0")"
source "$(dirname "$0")/helpers.sh"
echo "DEBUG: Successfully sourced helpers.sh"

main() {
  # Initialize variables with default values (check env vars first)
  local TMPDIR="${TMPDIR:-/tmp}"
  local DB_NAME="${DB_NAME:-wordpress_test}"
  local DB_USER="${DB_USER:-root}"
  local DB_PASS="${DB_PASSWORD:-}"
  local DB_HOST="${DB_HOST:-127.0.0.1}"
  local WP_VERSION="${WP_VERSION:-latest}"
  local SKIP_DB=""

  # Parse command-line arguments
  for i in "$@"; do
    case $i in
      --dbname=*)
      DB_NAME="${i#*=}"
      ;;
      --dbuser=*)
      DB_USER="${i#*=}"
      ;;
      --dbpass=*)
      DB_PASS="${i#*=}"
      ;;
      --dbhost=*)
      DB_HOST="${i#*=}"
      ;;
      --version=*)
      WP_VERSION="${i#*=}"
      ;;
      --skip-db=*)
      SKIP_DB="true"
      ;;
      --tmpdir=*)
      TMPDIR="${i#*=}"
      ;;
      *)
      # unknown option
      echo "Unknown option: $i. Usage: ./bin/install-local-tests.sh --dbname=wordpress_test --dbuser=root --dbpass=root --dbhost=localhost --version=latest --tmpdir=/tmp --skip-db=true"
      exit 1
      ;;
    esac
  done

  # Run install-wp-tests.sh
  echo "Installing local tests into ${TMPDIR}"
  echo "Using WordPress version: ${WP_VERSION}"
  echo "DEBUG: DB_PASSWORD env var: '${DB_PASSWORD}'"
  echo "DEBUG: DB_PASS value: '${DB_PASS}'"

  ARGS=(--version="$WP_VERSION" --tmpdir="$TMPDIR" --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="$DB_HOST")

  if [ -n "$SKIP_DB" ]; then
    echo "Skipping database creation"
    ARGS=("${ARGS[@]}" --skip-db=true)
  fi

  bash "$(dirname "$0")/install-wp-tests.sh" "${ARGS[@]}"

  # Run PHPUnit
  echo "Running PHPUnit"
  composer phpunit
}

main "$@"