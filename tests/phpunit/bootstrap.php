<?php
/**
 * PHPUnit bootstrap file for WP SAML Auth
 */

$_tests_dir = getenv('WP_TESTS_DIR');
if (! $_tests_dir) {
    $_tests_dir = '/tmp/wordpress-tests-lib';
}

/**
 * Ensure Yoast PHPUnit Polyfills is available (path provided by CI or vendor).
 */
if (! defined('WP_TESTS_PHPUNIT_POLYFILLS_PATH')) {
    $polyfills = getenv('WP_TESTS_PHPUNIT_POLYFILLS_PATH');
    if ($polyfills) {
        define('WP_TESTS_PHPUNIT_POLYFILLS_PATH', $polyfills);
    } else {
        define('WP_TESTS_PHPUNIT_POLYFILLS_PATH', __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php');
    }
}

/**
 * WP testing helpers (tests_add_filter, etc.)
 */
require_once $_tests_dir . '/includes/functions.php';

/**
 * Wire SimpleSAML stubs *only*: we expose the autoload path via the plugin's
 * filters so the plugin can load its provider. We do NOT override any other
 * plugin options here; the tests control behaviour via their own filters.
 */
$__simplesaml_stub_root = realpath(__DIR__ . '/simplesamlphp-stubs');
$__simplesaml_autoload  = $__simplesaml_stub_root ? ($__simplesaml_stub_root . '/autoload.php') : null;

function _wp_saml_auth_register_test_filters_minimal() {
    $autoload = $GLOBALS['__simplesaml_autoload'] ?? null;

    // Option-based loader used by the plugin at init.
    add_filter('wp_saml_auth_option', function ($value, $option_name) use ($autoload) {
        if ($option_name === 'simplesamlphp_autoload') {
            return $autoload;
        }
        return $value; // do not override any other option by default
    }, 1, 2);

    // Legacy direct filter used in older codepaths.
    add_filter('wp_saml_auth_autoload', function () use ($autoload) {
        return $autoload;
    });
}
tests_add_filter('muplugins_loaded', '_wp_saml_auth_register_test_filters_minimal');

/**
 * Load the plugin and test CLI helpers.
 */
function _manually_load_plugin() {
    $root = dirname(dirname(dirname(__FILE__))); // repo root
    require $root . '/wp-saml-auth.php';
    require $root . '/inc/class-wp-saml-auth-cli.php';
    require __DIR__ . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');

/**
 * Cookie shims for unit tests.
 */
function wp_set_auth_cookie($user_id, $remember = false, $secure = '', $token = '') {
    wp_set_current_user($user_id);
    return true;
}
function wp_logout() {
    wp_destroy_current_session();
    wp_set_current_user(0);
    do_action('wp_logout');
}

/**
 * Boot the WordPress testing environment
 */
require $_tests_dir . '/includes/bootstrap.php';
