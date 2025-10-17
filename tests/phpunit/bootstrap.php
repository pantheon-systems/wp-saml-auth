<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

// WP test lib location (provided by the workflow via WP_TESTS_DIR)
$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
	$_tests_dir = '/tmp/wordpress-tests-lib';
}

// Yoast polyfills path for cross-PHP PHPUnit features
define(
	'WP_TESTS_PHPUNIT_POLYFILLS_PATH',
	__DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php'
);

// Give access to tests_add_filter()
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 */
function _manually_load_plugin() {
	$root = dirname( dirname( dirname( __FILE__ ) ) ); // ← go up 3 levels to repo root

	require $root . '/wp-saml-auth.php';
	require $root . '/inc/class-wp-saml-auth-cli.php';
	require __DIR__ . '/class-wp-saml-auth-test-cli.php';

	// Use the simple auth shim for legacy expectation in some tests.
	add_filter( 'wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2 );
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Override specific wp-saml-auth options for tests.
 */
function _wp_saml_auth_filter_option( $value, $option_name ) {
	switch ( $option_name ) {
		case 'simplesamlphp_autoload':
			// Classic shim the tests expect for some scenarios (kept for backward-compat).
			$value = __DIR__ . '/class-simplesaml-auth-simple.php';
			break;
	}
	return $value;
}

/**
 * Minimal auth shims so unit tests don't fight cookies/sessions.
 */
function wp_set_auth_cookie( $user_id, $remember = false, $secure = '', $token = '' ) {
	wp_set_current_user( $user_id );
	return true;
}

function wp_logout() {
	wp_destroy_current_session();
	wp_set_current_user( 0 );
	do_action( 'wp_logout' );
}

// Boot the WP testing environment.
require $_tests_dir . '/includes/bootstrap.php';

/**
 * Force WP SAML Auth to use our SimpleSAMLphp stubs during unit tests.
 * This ensures we never try to load the real SimpleSAMLphp library in PHPUnit.
 */
add_filter( 'wp_saml_auth_autoload', function () {
	return __DIR__ . '/simplesamlphp-stubs/autoload.php';
} );
