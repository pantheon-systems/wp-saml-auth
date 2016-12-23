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
	require dirname( dirname( dirname( __FILE__ ) ) ) . '/wp-saml-auth.php';
	require dirname( dirname( dirname( __FILE__ ) ) ) . '/inc/class-wp-saml-auth-cli.php';
	require dirname( __FILE__ ) . '/class-wp-saml-auth-test-cli.php';

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

/**
 * Log in a user by setting authentication cookies.
 *
 * @since 2.5.0
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
	wp_set_current_user( $user_id );
	return true;
}

/**
 * Log the current user out.
 *
 * @since 2.5.0
 */
function wp_logout() {
	wp_destroy_current_session();
	wp_set_current_user( 0 );

	/**
	 * Fires after a user is logged-out.
	 *
	 * @since 1.5.0
	 */
	do_action( 'wp_logout' );
}

// Start up the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';
