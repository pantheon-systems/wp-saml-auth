#!/bin/bash
set -euo pipefail

# Check if a version argument was provided
if [ -z "$1" ]; then
  echo "Error: SimpleSAMLphp version must be provided as the first argument."
  exit 1
fi

SIMPLESAMLPHP_VERSION="$1"

# Sanitize the version string (e.g., "2.4.0" -> "240") for the env name
VERSION_SLUG=$(echo "${SIMPLESAMLPHP_VERSION}" | tr -d '.')

# Create the unique environment name using the GitHub run number
UNIQUE_ENV_NAME="ci${CIRCLE_BUILD_NUM}${VERSION_SLUG}"
SITE_ENV="${TERMINUS_SITE}.${UNIQUE_ENV_NAME}"

# Generate a temporary password
WORDPRESS_ADMIN_PASSWORD=$(openssl rand -hex 8)

# Export variables for subsequent steps
{
  echo "TERMINUS_ENV=${UNIQUE_ENV_NAME}"
  echo "SITE_ENV=${SITE_ENV}"
  echo "WORDPRESS_ADMIN_USERNAME=pantheon"
  echo "WORDPRESS_ADMIN_EMAIL=no-reply@getpantheon.com"
  echo "WORDPRESS_ADMIN_PASSWORD=${WORDPRESS_ADMIN_PASSWORD}"
  echo "SIMPLESAMLPHP_VERSION=${SIMPLESAMLPHP_VERSION}"
} >> "$GITHUB_ENV"

# Save the environment name to a file for the cleanup job
echo "${SITE_ENV}" > "/tmp/site_env.txt"

echo "✅ Behat environment variables configured for ${SITE_ENV}"
