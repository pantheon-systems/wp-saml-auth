=== WP SAML Auth ===
Contributors: getpantheon, danielbachhuber, Outlandish Josh
Tags: authentication, SAML, SimpleSAMLphp
Requires at least: 4.4
Tested up to: 4.5
Stable tag: 0.0
License: GPLv2 or later
License URI: http://www.gnu.org/licenses/gpl-2.0.html

SAML authentication for WordPress, using SimpleSAMLphp.

== Description ==

[![Build Status](https://travis-ci.org/danielbachhuber/wp-saml-auth.svg?branch=master)](https://travis-ci.org/danielbachhuber/wp-saml-auth)

== Installation ==

This plugin requires access to a SimpleSAMLphp installation running on the same server. If your server is already running SimpleSAMLphp, then you are good to go. Otherwise, you'll need to install and configure SimpleSAMLphp on the server before you can begin using this plugin.

Once SimpleSAMLphp is installed and running on your server, you can configure this plugin using a filter included in your theme's functions.php or a mu-plugin:

    function wpsax_filter_option( $value, $option_name ){

        // Overload default options as you need to.
        switch ( $option_name ) {
            case 'auth_source':
                $value = 'example-userpass';
                break;
        }

	    return $value;
    }
    add_filter( 'wp_saml_auth_option', 'wpsax_filter_option', 10, 2 );
