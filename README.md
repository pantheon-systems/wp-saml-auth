# WP SAML Auth #
**Contributors:** getpantheon, danielbachhuber, Outlandish Josh  
**Tags:** authentication, SAML, SimpleSAMLphp  
**Requires at least:** 4.4  
**Tested up to:** 4.5  
**Stable tag:** 0.0  
**License:** GPLv2 or later  
**License URI:** http://www.gnu.org/licenses/gpl-2.0.html  

SAML authentication for WordPress, using SimpleSAMLphp.

## Description ##

[![Build Status](https://travis-ci.org/danielbachhuber/wp-saml-auth.svg?branch=master)](https://travis-ci.org/danielbachhuber/wp-saml-auth)

SAML authentication for WordPress, using [SimpleSAMLphp](https://simplesamlphp.org/). When activated, and provided access to a functional SimpleSAMLphp application, this plugin permits authentication using any of the protocols supported by SimpleSAMLphp.

End users can log in via SimpleSAMLphp using a button added to the standard WordPress login view. When the button is clicked, the `SimpleSAML_Auth_Simple` class is called to determine whether the user is authenticated. If the user isn't authenticated, they're redirected to the SimpleSAMLphp login view. If they are authenticated, they will be signed into WordPress as their corresponding WordPress user. If no such WordPress user exists, one will be created.

See installation instructions for full configuration details.

## Installation ##

This plugin requires access to a SimpleSAMLphp installation running on the same server. If your server is already running SimpleSAMLphp, then you are good to go. Otherwise, you'll need to install and configure SimpleSAMLphp on the server before you can begin using this plugin.

Once SimpleSAMLphp is installed and running on your server, you can configure this plugin using a filter included in your theme's functions.php or a mu-plugin:

    function wpsax_filter_option( $value, $option_name ){

        $overrides = array(
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

        return isset( $overrides[ $option_name ] ) ? $overrides[ $option_name ] : $value;
    }
    add_filter( 'wp_saml_auth_option', 'wpsax_filter_option', 10, 2 );

## Changelog ##

### 0.1.0 (???? ??, ????) ###

* Initial release.
