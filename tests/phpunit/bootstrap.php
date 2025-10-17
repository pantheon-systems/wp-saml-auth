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

define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php' );

// --- Load the SimpleSAMLphp stubs early --------------------------------------
$__stub_autoload = __DIR__ . '/simplesamlphp-stubs/autoload.php';
if ( file_exists( $__stub_autoload ) ) {
	define( 'WP_SAML_AUTH_AUTOLOAD', $__stub_autoload );
	putenv( 'WP_SAML_AUTH_AUTOLOAD=' . $__stub_autoload );
	require_once $__stub_autoload;
}

// Give access to tests_add_filter() function.
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 */
function _manually_load_plugin() {
	$root = dirname( dirname( dirname( __FILE__ ) ) );

	require $root . '/wp-saml-auth.php';
	require $root . '/inc/class-wp-saml-auth-cli.php';
	require __DIR__ . '/class-wp-saml-auth-test-cli.php';

	add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Defaults aligned to unit tests.
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
	switch ( $option_name ) {
		case 'simplesamlphp_autoload':
			$value = defined( 'WP_SAML_AUTH_AUTOLOAD' ) ? WP_SAML_AUTH_AUTOLOAD : $value;
			break;

		// Default: do NOT permit username/password logins in tests.
		case 'permit_wp_login':
		case 'permit_user_login':
			$value = false;
			break;

		// Auto-provision ON by default so SAML can create users when attributes exist.
		case 'auto_provision':
			$value = true;
			break;

		// Map aligns with stub attributes.
		case 'user_login_attribute':
			$value = 'uid';
			break;
		case 'user_email_attribute':
			$value = 'mail';
			break;
		case 'user_role_attribute':
			$value = 'eduPersonAffiliation';
			break;

		case 'default_role':
			$value = 'subscriber';
			break;
	}
	return $value;
}

// Start WP test environment.
require $_tests_dir . '/includes/bootstrap.php';

// Also support the newer filter the plugin exposes.
add_filter( 'wp_saml_auth_autoload', function () {
	return defined( 'WP_SAML_AUTH_AUTOLOAD' ) ? WP_SAML_AUTH_AUTOLOAD : null;
} );

/**
 * In tests we avoid real cookies; return falsey (as tests expect).
 */
if ( ! function_exists( 'wp_set_auth_cookie' ) ) {
	function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
		wp_set_current_user( $user_id );
		return false;
	}
}

/**
 * Tests assert a falsey logout return.
 */
if ( ! function_exists( 'wp_logout' ) ) {
	function wp_logout() {
		wp_destroy_current_session();
		wp_set_current_user( 0 );
		do_action( 'wp_logout' );
		return false;
	}
}
