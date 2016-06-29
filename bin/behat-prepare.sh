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
BASH_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SIMPLESAMLPHP_VERSION='1.14.4'

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
yes | terminus site code commit --message="Include WP Native Sessions and testing child theme"

###
# Switch to git mode for pushing the rest of the files up
###
terminus site set-connection-mode --mode=git
git clone $PANTHEON_GIT_URL $PREPARE_DIR

###
# Add SimpleSAML PHP to the environment
###
rm -rf $PREPARE_DIR/private
mkdir $PREPARE_DIR/private
wget -O $PREPARE_DIR/simplesamlphp.tar.gz https://simplesamlphp.org/res/downloads/simplesamlphp-$SIMPLESAMLPHP_VERSION.tar.gz
tar -zxvf $PREPARE_DIR/simplesamlphp.tar.gz -C $PREPARE_DIR/private
mv $PREPARE_DIR/private/simplesamlphp-$SIMPLESAMLPHP_VERSION $PREPARE_DIR/private/simplesamlphp
rm $PREPARE_DIR/simplesamlphp.tar.gz

###
# Configure SimpleSAML PHP for the environment
###
cat $BASH_DIR/fixtures/authsources.php.additions >> $PREPARE_DIR/private/simplesamlphp/config/authsources.php
cat $BASH_DIR/fixtures/config.php.additions      >> $PREPARE_DIR/private/simplesamlphp/config/config.php

cp $BASH_DIR/fixtures/saml20-idp-hosted.php  $PREPARE_DIR/private/simplesamlphp/metadata/saml20-idp-hosted.php
cp $BASH_DIR/fixtures/shib13-idp-hosted.php  $PREPARE_DIR/private/simplesamlphp/metadata/shib13-idp-hosted.php

touch $PREPARE_DIR/private/simplesamlphp/modules/exampleauth/enable

openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes -out $PREPARE_DIR/private/simplesamlphp/cert/saml.crt -keyout $PREPARE_DIR/private/simplesamlphp/cert/saml.pem -batch

sed -i  -- "s/<button/<button id='submit'/g" $PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.php

ln -s $PREPARE_DIR/private/simplesamlphp/www $PREPARE_DIR/simplesamlphp

###
# Push files to the environment
###
cd $PREPARE_DIR
git add private
git config user.email "wp-saml-auth@getpantheon.com"
git config user.name "Pantheon"
git commit -m "Include SimpleSAML PHP and its configuration files"
git push origin $TERMINUS_ENV
