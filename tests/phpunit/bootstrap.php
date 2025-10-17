<?php
/**
 * PHPUnit bootstrap file
 *
 * @package Wp_Saml_Auth
 */

// Location of the WP core test library.
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
 * Manually load the plugin being tested and force the SimpleSAML shim.
 */
function _manually_load_plugin() {
	$repo_root     = dirname( __DIR__, 2 ); // repository root
	$tests_dir     = __DIR__;
	$shim_legacy   = $tests_dir . '/class-simplesaml-auth-simple.php';

	// Newer plugin code path: use 'wp_saml_auth_autoload'.
	add_filter(
		'wp_saml_auth_autoload',
		static function () use ( $shim_legacy ) {
			return $shim_legacy;
		},
		10,
		0
	);

	// Back-compat path used by older code/tests.
	add_filter(
		'wp_saml_auth_option',
		static function ( $value, $option_name ) use ( $shim_legacy ) {
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return $shim_legacy;
			}
			return $value;
		},
		10,
		2
	);

	// Load plugin and test helpers.
	require $repo_root . '/wp-saml-auth.php';
	require $repo_root . '/inc/class-wp-saml-auth-cli.php';
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
