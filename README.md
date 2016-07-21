# WP SAML Auth #
**Contributors:** getpantheon, danielbachhuber, Outlandish Josh  
**Tags:** authentication, SAML, SimpleSAMLphp  
**Requires at least:** 4.4  
**Tested up to:** 4.5.3  
**Stable tag:** 0.1.0  
**License:** GPLv2 or later  
**License URI:** http://www.gnu.org/licenses/gpl-2.0.html  

SAML authentication for WordPress, using SimpleSAMLphp.

## Description ##

[![Travis CI](https://travis-ci.org/pantheon-systems/wp-saml-auth.svg?branch=master)](https://travis-ci.org/pantheon-systems/wp-saml-auth) [![CircleCI](https://circleci.com/gh/pantheon-systems/wp-saml-auth/tree/master.svg?style=svg)](https://circleci.com/gh/pantheon-systems/wp-saml-auth/tree/master)

SAML authentication for WordPress, using [SimpleSAMLphp](https://simplesamlphp.org/). When activated, and provided access to a functional SimpleSAMLphp installation, this plugin permits authentication using any of the methods supported by SimpleSAMLphp.

The standard user flow looks like this:

* User can log in via SimpleSAMLphp using a button added to the standard WordPress login view.
* When the button is clicked, the `SimpleSAML_Auth_Simple` class is called to determine whether the user is authenticated.
* If the user isn't authenticated, they're redirected to the SimpleSAMLphp login view.
* Once the user is authenticated with SimpleSAMLphp, they will be signed into WordPress as their corresponding WordPress user. A new WordPress user will be created if none exists.
* When the user logs out of WordPress, they are also logged out of SimpleSAMLphp.

A set of configuration options allow you to change the plugin's default behavior. For instance, `permit_wp_login=>false` will force all authentication to go through SimpleSAMLphp, bypassing `wp-login.php`. Similiarly, `auto_provision=>false` will disable automatic creation of new WordPress users.

See installation instructions for full configuration details.

## Installation ##

This plugin requires access to a SimpleSAMLphp installation running in the same environment. If you are already running SimpleSAMLphp, then you are good to go. Otherwise, you'll need to install and configure SimpleSAMLphp before you can begin using this plugin. For local testing purposes, the [Identity Provider QuickStart](https://simplesamlphp.org/docs/stable/simplesamlphp-idp) is a good place to start.

Once SimpleSAMLphp is installed and running on your server, you can configure this plugin using a filter included in your theme's functions.php file or a mu-plugin:

    function wpsax_filter_option( $value, $option_name ) {
        $defaults = array(
            /**
             * Path to SimpleSAMLphp autoloader.
             *
             * Follow the standard implementation by installing SimpleSAMLphp
             * alongside the plugin, and provide the path to its autoloader.
             * Alternatively, this plugin will work if it can find the
             * `SimpleSAML_Auth_Simple` class.
             *
             * @param string
             */
            'simplesamlphp_autoload' => dirname( __FILE__ ) . '/simplesamlphp/lib/_autoload.php',
            /**
             * Authentication source to pass to SimpleSAMLphp
             *
             * This must be one of your configured identity providers in
             * SimpleSAMLphp. If the identity provider isn't configured
             * properly, the plugin will not work properly.
             *
             * @param string
             */
            'auth_source'            => 'default-sp',
            /**
             * Whether or not to automatically provision new WordPress users.
             *
             * When WordPress is presented with a SAML user without a
             * corresponding WordPress account, it can either create a new user
             * or display an error that the user needs to contact the site
             * administrator.
             *
             * @param bool
             */
            'auto_provision'         => true,
            /**
             * Whether or not to permit logging in with username and password.
             *
             * If this feature is disabled, all authentication requests will be
             * channeled through SimpleSAMLphp.
             *
             * @param bool
             */
            'permit_wp_login'        => true,
            /**
             * Attribute by which to get a WordPress user for a SAML user.
             *
             * @param string Supported options are 'email' and 'login'.
             */
            'get_user_by'            => 'email',
            /**
             * SAML attribute which includes the user_login value for a user.
             *
             * @param string
             */
            'user_login_attribute'   => 'uid',
            /**
             * SAML attribute which includes the user_email value for a user.
             *
             * @param string
             */
            'user_email_attribute'   => 'mail',
            /**
             * SAML attribute which includes the display_name value for a user.
             *
             * @param string
             */
            'display_name_attribute' => 'display_name',
            /**
             * SAML attribute which includes the first_name value for a user.
             *
             * @param string
             */
            'first_name_attribute' => 'first_name',
            /**
             * SAML attribute which includes the last_name value for a user.
             *
             * @param string
             */
            'last_name_attribute' => 'last_name',
            /**
             * Default WordPress role to grant when provisioning new users.
             *
             * @param string
             */
            'default_role'           => get_option( 'default_role' ),
        );
        $value = isset( $defaults[ $option_name ] ) ? $defaults[ $option_name ] : $value;
        return $value;
    }
    add_filter( 'wp_saml_auth_option', 'wpsax_filter_option', 10, 2 );

## Contributing ##

The best way to contribute to the development of this plugin is by participating on the GitHub project:

https://github.com/pantheon-systems/wp-saml-auth

Pull requests and issues are welcome!

You may notice there are two sets of tests running, on two different services:

* Travis CI runs the [PHPUnit](https://phpunit.de/) test suite, which mocks interactions with SimpleSAMLphp.
* Circle CI runs the [Behat](http://behat.org/) test suite against a Pantheon site, to ensure the plugin's compatibility with the Pantheon platform. This includes configuring a fully-functional instance of SimpleSAMLphp.

Both of these test suites can be run locally, with a varying amount of setup.

PHPUnit requires the [WordPress PHPUnit test suite](https://make.wordpress.org/core/handbook/testing/automated-testing/phpunit/), and access to a database with name `wordpress_test`. If you haven't already configured the test suite locally, you can run `bash bin/install-wp-tests.sh wordpress_test root '' localhost`.

Behat requires a Pantheon site. Once you've created the site, you'll need install Terminus, and set the `TERMINUS_TOKEN`, `TERMINUS_SITE`, and `TERMINUS_ENV` environment variables. Then, you can run `./bin/behat-prepare.sh` to prepare the site for the test suite.

## Frequently Asked Questions ##

### How do I use SimpleSAMLphp and WP SAML Auth on a multi web node environment? ###

Because SimpleSAMLphp uses PHP sessions to manage user authentication, it will work unreliably or not at all on a server configuration with multiple web nodes. This is because PHP's default session handler uses the filesystem, and each web node has a different filesystem. Fortunately, there's a way around this.

First, install and activate the [WP Native PHP Sessions plugin](https://wordpress.org/plugins/wp-native-php-sessions/), which registers a database-based PHP session handler for WordPress to use.

Next, modify SimpleSAMLphp's `www/_include.php` file to require `wp-load.php`. If you installed SimpleSAMLphp within the `wp-saml-auth` directory, you'd edit `wp-saml-auth/simplesamlphp/www/_include.php` to include:

    <?php
    require_once dirname( dirname( dirname( dirname( dirname( dirname( __FILE__ ) ) ) ) ) ) . '/wp-load.php';

Note: the declaration does need to be at the top of `_include.php`, to ensure WordPress (and thus the session handling) is loaded before SimpleSAMLphp.

There is no third step. Because SimpleSAMLphp loads WordPress, which has WP Native PHP Sessions active, SimpleSAMLphp and WP SAML Auth will be able to communicate to one another on a multi web node environment.

## Changelog ##

### 0.1.0 (April 18, 2016) ###

* Initial release.
