<?php
/**
 * PHPUnit bootstrap file for WP SAML Auth
 */

//
// 1) Locate the WP tests framework
//
$_tests_dir = getenv('WP_TESTS_DIR');
if (! $_tests_dir) {
    $_tests_dir = '/tmp/wordpress-tests-lib';
}

//
// 2) Make sure PHPUnit Polyfills path is defined (GitHub Actions sets an env var)
//
if (! defined('WP_TESTS_PHPUNIT_POLYFILLS_PATH')) {
    $polyfills = getenv('WP_TESTS_PHPUNIT_POLYFILLS_PATH');
    if ($polyfills) {
        define('WP_TESTS_PHPUNIT_POLYFILLS_PATH', $polyfills);
    } else {
        define(
            'WP_TESTS_PHPUNIT_POLYFILLS_PATH',
            __DIR__ . '/../../vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php'
        );
    }
}

//
// 3) Load WP test helpers (gives us tests_add_filter(), etc.)
//
require_once $_tests_dir . '/includes/functions.php';

//
// 4) **Always-available SimpleSAML stub autoloader**
//    This guarantees the class \SimpleSAML\Auth\Simple can be loaded even if
//    the plugin fails to honor its filters/options for an autoload path.
//
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

//
// 5) Provide sane default options for the plugin during unit tests
//    Return a value ONLY when the current value is null, so tests can override.
//
function _wp_saml_auth_filter_option($value, $option_name) {
    if (null !== $value) {
        return $value;
    }

    switch ($option_name) {
        case 'simplesamlphp_autoload':
            // Also tell the plugin about our autoload file (belt & suspenders).
            return realpath(__DIR__ . '/simplesamlphp-stubs/autoload.php');

        // Defaults that keep unit tests deterministic; individual tests can override.
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
 * Register filters early and then load the plugin.
 * (Both happen on muplugins_loaded. We ensure the filters exist before the plugin loads.)
 */
function _wp_saml_auth_register_test_filters() {
    add_filter('wp_saml_auth_option', '_wp_saml_auth_filter_option', 1, 2);

    // Some codepaths read this filter directly; provide it too.
    add_filter('wp_saml_auth_autoload', function () {
        return realpath(__DIR__ . '/simplesamlphp-stubs/autoload.php');
    });
}
tests_add_filter('muplugins_loaded', '_wp_saml_auth_register_test_filters');

/**
 * Load the plugin and the CLI test helpers.
 */
function _manually_load_plugin() {
    $root = dirname(dirname(dirname(__FILE__))); // repository root
    require $root . '/wp-saml-auth.php';
    require $root . '/inc/class-wp-saml-auth-cli.php';
    require __DIR__ . '/class-wp-saml-auth-test-cli.php';
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');

/**
 * Cookie shims: unit tests don’t actually set browser cookies.
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

//
// 6) Finally boot the WP testing environment
//
require $_tests_dir . '/includes/bootstrap.php';
