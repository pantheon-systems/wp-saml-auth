<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

// Where the WP core test library lives (set by CI).
$_tests_dir = getenv( 'WP_TESTS_DIR' );
if ( ! $_tests_dir ) {
	$_tests_dir = '/tmp/wordpress-tests-lib';
}

// Yoast polyfills for cross-PHP PHPUnit features.
define(
	'WP_TESTS_PHPUNIT_POLYFILLS_PATH',
	__DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php'
);

// Give access to tests_add_filter().
require_once $_tests_dir . '/includes/functions.php';

/**
 * Manually load the plugin being tested.
 *
 * IMPORTANT: This uses the original, repo-provided SimpleSAML test double
 * `class-simplesaml-auth-simple.php` that the tests were written for.
 */
function _manually_load_plugin() {
	$root         = dirname( __DIR__, 2 ); // repository root
	$tests_dir    = __DIR__;
	$shim_legacy  = $tests_dir . '/class-simplesaml-auth-simple.php';

	// Tell the plugin to use the legacy SimpleSAML shim the tests expect.
	add_filter(
		'wp_saml_auth_option',
		static function( $value, $option_name ) use ( $shim_legacy ) {
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return $shim_legacy;
			}
			return $value;
		},
		10,
		2
	);

	// Load plugin and CLI harness.
	require $root . '/wp-saml-auth.php';
	require $root . '/inc/class-wp-saml-auth-cli.php';
	require $tests_dir . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter( 'muplugins_loaded', '_manually_load_plugin' );

/**
 * Minimal auth shims so unit tests don't set cookies/sessions.
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
