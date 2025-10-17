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
 * Hard-register a PSR-4 style autoloader for SimpleSAML stubs.
 * This guarantees \SimpleSAML\Auth\Simple is loadable even if the plugin
 * fails to read its option/filter.
 */
$__simplesaml_stub_root = realpath(__DIR__ . '/simplesamlphp-stubs');
if ($__simplesaml_stub_root) {
    spl_autoload_register(function ($class) use ($__simplesaml_stub_root) {
        $prefix = 'SimpleSAML\\';
        if (strncmp($class, $prefix, strlen($prefix)) !== 0) {
            return;
        }
        $relative = substr($class, strlen($prefix)); // e.g. "Auth\Simple"
        $file = $__simplesaml_stub_root . '/SimpleSAML/' . str_replace('\\', '/', $relative) . '.php';
        if (is_file($file)) {
            require $file;
        }
    });
}

/**
 * Provide deterministic default options for the plugin under test.
 * IMPORTANT: Always return our autoload path for 'simplesamlphp_autoload'.
 */
function _wp_saml_auth_filter_option($value, $option_name) {
    switch ($option_name) {
        case 'simplesamlphp_autoload':
            return realpath(__DIR__ . '/simplesamlphp-stubs/autoload.php');

        // Defaults to keep tests deterministic; individual tests can override.
        case 'permit_wp_login':
            return false;
        case 'auto_provision':
            return false;
        case 'allow_slo':
            return false;
        case 'user_login_attribute':
            return 'uid';
        case 'user_email_attribute':
            return 'mail';
        case 'user_role_attribute':
            return 'eduPersonAffiliation';
        case 'default_role':
            return 'subscriber';
    }
    return $value;
}

/**
 * Register test filters first, then load the plugin.
 */
function _wp_saml_auth_register_test_filters() {
    add_filter('wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2);

    // Some codepaths query this filter directly; provide it as well.
    add_filter('wp_saml_auth_autoload', function () {
        return realpath(__DIR__ . '/simplesamlphp-stubs/autoload.php');
    });
}
tests_add_filter('muplugins_loaded', '_wp_saml_auth_register_test_filters');

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
