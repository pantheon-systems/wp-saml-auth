#!/bin/bash

set -ex

if [ -z "$TERMINUS_SITE" ] || [ -z "$TERMINUS_ENV" ]; then
	echo "TERMINUS_SITE and TERMINUS_ENV environment variables must be set"
	exit 1
fi

###
# Create a new environment for this particular test run.
###
terminus site create-env --to-env=$TERMINUS_ENV --from-env=dev
yes | terminus site wipe

###
# Get all necessary environment details.
###
PANTHEON_GIT_URL=$(terminus site connection-info --field=git_url)
PANTHEON_SITE_URL="$TERMINUS_ENV-$TERMINUS_SITE.pantheonsite.io"
PREPARE_DIR="/tmp/$TERMINUS_ENV-$TERMINUS_SITE"

###
# Ensure environment is in SFTP mode for installing plugins
###
terminus site set-connection-mode --mode=sftp

###
# Set up WordPress and plugins for the test run
###
terminus wp "core install --title=$TERMINUS_ENV-$TERMINUS_SITE --url=$PANTHEON_SITE_URL --admin_user=pantheon --admin_email=wp-saml-auth@getpantheon.com --admin_password=pantheon"
terminus wp "plugin install wp-native-php-sessions --activate"
terminus wp "scaffold child-theme $TERMINUS_SITE --parent_theme=twentysixteen --activate"
yes | terminus site code commit --message="Set up WP Native Sessions and child theme for testing"

###
# Switch to git mode for pushing the rest of the files up
###

###
# Push requisite files to the environment
###
