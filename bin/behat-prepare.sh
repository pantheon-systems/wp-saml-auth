#!/bin/bash

###
# Prepare a Pantheon site environment for the Behat test suite, by installing
# and configuring the plugin for the environment. This script is architected
# such that it can be run a second time if a step fails.
###

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
# Switch to git mode for pushing the files up
###
terminus site set-connection-mode --mode=git
rm -rf $PREPARE_DIR
git clone -b $TERMINUS_ENV $PANTHEON_GIT_URL $PREPARE_DIR

###
# Add WP Native PHP Sessions and child theme to environment
###
rm -rf $PREPARE_DIR/wp-content/themes/$TERMINUS_SITE
# Create a child theme that includes WP SAML Auth configuration details
mkdir $PREPARE_DIR/wp-content/themes/$TERMINUS_SITE
cp $BASH_DIR/fixtures/functions.php  $PREPARE_DIR/wp-content/themes/$TERMINUS_SITE/functions.php
cp $BASH_DIR/fixtures/style.css  $PREPARE_DIR/wp-content/themes/$TERMINUS_SITE/style.css

rm -rf $PREPARE_DIR/wp-content/plugins/wp-native-php-sessions
# Download the latest WP Native PHP sessions release from WordPress.org
wget -O $PREPARE_DIR/wp-native-php-sessions.zip https://downloads.wordpress.org/plugin/wp-native-php-sessions.zip
unzip $PREPARE_DIR/wp-native-php-sessions.zip -d $PREPARE_DIR
mv $PREPARE_DIR/wp-native-php-sessions $PREPARE_DIR/wp-content/plugins/
rm $PREPARE_DIR/wp-native-php-sessions.zip

###
# Add the copy of this plugin itself to the environment
###
cd $BASH_DIR/..
rsync -av --exclude='vendor/' --exclude='node_modules/' --exclude='simplesamlphp/' --exclude='tests/' ./* $PREPARE_DIR/wp-content/plugins/wp-saml-auth
rm -rf $PREPARE_DIR/wp-content/plugins/wp-saml-auth/.git

###
# Add SimpleSAMLphp to the environment
# SimpleSAMLphp is installed to ~/code/private, and then symlinked into the
# web root
###
rm -rf $PREPARE_DIR/private
mkdir $PREPARE_DIR/private
wget -O $PREPARE_DIR/simplesamlphp.tar.gz https://simplesamlphp.org/res/downloads/simplesamlphp-$SIMPLESAMLPHP_VERSION.tar.gz
tar -zxvf $PREPARE_DIR/simplesamlphp.tar.gz -C $PREPARE_DIR/private
mv $PREPARE_DIR/private/simplesamlphp-$SIMPLESAMLPHP_VERSION $PREPARE_DIR/private/simplesamlphp
rm $PREPARE_DIR/simplesamlphp.tar.gz

###
# Configure SimpleSAMLphp for the environment
# For the purposes of the Behat tests, we're using SimpleSAMLphp as an identity
# provider with its exampleauth module enabled
###
# Append existing configuration files with our the specifics for our tests
cat $BASH_DIR/fixtures/authsources.php.additions >> $PREPARE_DIR/private/simplesamlphp/config/authsources.php
cat $BASH_DIR/fixtures/config.php.additions      >> $PREPARE_DIR/private/simplesamlphp/config/config.php

# Copy identify provider configuration files into their appropriate locations
cp $BASH_DIR/fixtures/saml20-idp-hosted.php  $PREPARE_DIR/private/simplesamlphp/metadata/saml20-idp-hosted.php
cp $BASH_DIR/fixtures/shib13-idp-hosted.php  $PREPARE_DIR/private/simplesamlphp/metadata/shib13-idp-hosted.php

# Enable the exampleauth module
touch $PREPARE_DIR/private/simplesamlphp/modules/exampleauth/enable

# Generate a certificate SimpleSAMLphp uses for encryption
# Because these files are in ~/code/private, they're inaccessible from the web
openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes -out $PREPARE_DIR/private/simplesamlphp/cert/saml.crt -keyout $PREPARE_DIR/private/simplesamlphp/cert/saml.pem -batch

# Modify the login template so Behat can submit the form
sed -i  -- "s/<button/<button id='submit'/g" $PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.php

cd $PREPARE_DIR
# Make the SimpleSAMLphp installation publicly accessible
ln -s ./private/simplesamlphp/www ./simplesaml

###
# Push files to the environment
###
cd $PREPARE_DIR
git add private wp-content simplesaml
git config user.email "wp-saml-auth@getpantheon.com"
git config user.name "Pantheon"
git commit -m "Include SimpleSAMLphp and its configuration files"
git push

###
# Set up WordPress, theme, and plugins for the test run
###
terminus wp "core install --title=$TERMINUS_ENV-$TERMINUS_SITE --url=$PANTHEON_SITE_URL --admin_user=pantheon --admin_email=wp-saml-auth@getpantheon.com --admin_password=pantheon"
terminus wp "plugin list"
terminus wp "cache flush"
terminus wp "plugin list"
terminus wp "plugin activate wp-native-php-sessions wp-saml-auth"
terminus wp "theme activate $TERMINUS_SITE"
