<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
	$_tests_dir = '/tmp/wordpress-tests-lib';
}

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 */
function _manually_load_plugin() {
	require dirname( dirname( __FILE__ ) ) . '/wp-saml-auth.php';

	add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

function _wp_saml_auth_filter_option( $value, $option_name ) {
	switch ( $option_name ) {
		case 'simplesamlphp_autoload':
			$value = dirname( __FILE__ ) . '/class-simplesaml-auth-simple.php';
			break;
	}
	return $value;
}

function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
	return true;
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';
