#!/bin/bash

###
# Prepare a Pantheon site environment for the Behat test suite, by installing
# and configuring the plugin for the environment. This script is architected
# such that it can be run a second time if a step fails.
###

TERMINUS_USER_ID=$(terminus auth:whoami --field=id 2>&1)
if [[ ! $TERMINUS_USER_ID =~ ^[A-Za-z0-9-]{36}$ ]]; then
	echo "Terminus unauthenticated; assuming unauthenticated build"
	exit 0
fi

set -ex

if [ -z "$TERMINUS_SITE" ] || [ -z "$TERMINUS_ENV" ]; then
	echo "TERMINUS_SITE and TERMINUS_ENV environment variables must be set"
	exit 1
fi

###
# Create a new environment for this particular test run.
###
terminus env:create $TERMINUS_SITE.dev $TERMINUS_ENV
terminus env:wipe $SITE_ENV --yes

###
# Get all necessary environment details.
###
PANTHEON_GIT_URL=$(terminus connection:info $SITE_ENV --field=git_url)
PANTHEON_SITE_URL="$TERMINUS_ENV-$TERMINUS_SITE.pantheonsite.io"
PREPARE_DIR="/tmp/$TERMINUS_ENV-$TERMINUS_SITE"
BASH_DIR="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

###
# Switch to git mode for pushing the files up
###
terminus connection:set $SITE_ENV git
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

# Download the latest Classic Editor release from WordPress.org
wget -O $PREPARE_DIR/classic-editor.zip https://downloads.wordpress.org/plugin/classic-editor.zip
unzip $PREPARE_DIR/classic-editor.zip -d $PREPARE_DIR
mv $PREPARE_DIR/classic-editor $PREPARE_DIR/wp-content/plugins/
rm $PREPARE_DIR/classic-editor.zip

###
# Add the copy of this plugin itself to the environment
###
cd $BASH_DIR/..
rsync -av --exclude='node_modules/' --exclude='simplesamlphp/' --exclude='tests/' ./* $PREPARE_DIR/wp-content/plugins/wp-saml-auth
rm -rf $PREPARE_DIR/wp-content/plugins/wp-saml-auth/.git

###
# Add SimpleSAMLphp to the environment
# SimpleSAMLphp is installed to ~/code/private, and then symlinked into the
# web root
###
rm -rf $PREPARE_DIR/private
mkdir $PREPARE_DIR/private
wget https://github.com/simplesamlphp/simplesamlphp/releases/download/v1.14.12/simplesamlphp-1.14.12.tar.gz -O $PREPARE_DIR/simplesamlphp-latest.tar.gz
tar -zxvf $PREPARE_DIR/simplesamlphp-latest.tar.gz -C $PREPARE_DIR/private
ORIG_SIMPLESAMLPHP_DIR=$(ls $PREPARE_DIR/private)
mv $PREPARE_DIR/private/$ORIG_SIMPLESAMLPHP_DIR $PREPARE_DIR/private/simplesamlphp
rm $PREPARE_DIR/simplesamlphp-latest.tar.gz

###
# Configure SimpleSAMLphp for the environment
# For the purposes of the Behat tests, we're using SimpleSAMLphp as an identity
# provider with its exampleauth module enabled
###
# Append existing configuration files with our the specifics for our tests
echo "// This variable was added by behat-prepare.sh." >>  $PREPARE_DIR/private/simplesamlphp/config/authsources.php
# Silence output so as not to show the password.
{
  echo "\$wordpress_admin_password = '"${WORDPRESS_ADMIN_PASSWORD}"';" >> $PREPARE_DIR/private/simplesamlphp/config/authsources.php
} &> /dev/null
echo "\$wordpress_admin_username = '"${WORDPRESS_ADMIN_USERNAME}"';" >> $PREPARE_DIR/private/simplesamlphp/config/authsources.php
echo "\$wordpress_admin_email = '"${WORDPRESS_ADMIN_EMAIL}"';" >> $PREPARE_DIR/private/simplesamlphp/config/authsources.php
cat $BASH_DIR/fixtures/authsources.php.additions >> $PREPARE_DIR/private/simplesamlphp/config/authsources.php
cat $BASH_DIR/fixtures/config.php.additions      >> $PREPARE_DIR/private/simplesamlphp/config/config.php

# Copy identify provider configuration files into their appropriate locations
cp $BASH_DIR/fixtures/saml20-idp-hosted.php  $PREPARE_DIR/private/simplesamlphp/metadata/saml20-idp-hosted.php
cp $BASH_DIR/fixtures/shib13-idp-hosted.php  $PREPARE_DIR/private/simplesamlphp/metadata/shib13-idp-hosted.php
cp $BASH_DIR/fixtures/saml20-sp-remote.php  $PREPARE_DIR/private/simplesamlphp/metadata/saml20-sp-remote.php
cp $BASH_DIR/fixtures/shib13-sp-remote.php  $PREPARE_DIR/private/simplesamlphp/metadata/shib13-sp-remote.php

# Enable the exampleauth module
touch $PREPARE_DIR/private/simplesamlphp/modules/exampleauth/enable

# Generate a certificate SimpleSAMLphp uses for encryption
# Because these files are in ~/code/private, they're inaccessible from the web
openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes -out $PREPARE_DIR/private/simplesamlphp/cert/saml.crt -keyout $PREPARE_DIR/private/simplesamlphp/cert/saml.pem -batch

# Modify the login template so Behat can submit the form
sed -i  -- "s/<button/<button id='submit'/g" $PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.php
sed -i  -- "s/this.disabled=true; this.form.submit(); return true;//g" $PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.php
# Second button instance shouldn't have an id
sed -i  -- "s/<button id='submit' class=\"btn\" tabindex=\"6\"/<button class=\"btn\" tabindex=\"6\"/g" $PREPARE_DIR/private/simplesamlphp/modules/core/templates/loginuserpass.php

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

# Sometimes Pantheon takes a little time to refresh the filesystem
sleep 10

###
# Set up WordPress, theme, and plugins for the test run
###
# Silence output so as not to show the password.
{
  terminus wp $SITE_ENV -- core install --title=$TERMINUS_ENV-$TERMINUS_SITE --url=$PANTHEON_SITE_URL --admin_user=$WORDPRESS_ADMIN_USERNAME --admin_email=$WORDPRESS_ADMIN_EMAIL --admin_password=$WORDPRESS_ADMIN_PASSWORD
} &> /dev/null
terminus wp $SITE_ENV -- plugin activate classic-editor wp-native-php-sessions wp-saml-auth
terminus wp $SITE_ENV -- theme activate $TERMINUS_SITE
terminus wp $SITE_ENV -- rewrite structure '/%year%/%monthnum%/%day%/%postname%/'
