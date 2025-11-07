<?php
/**
 * PHPUnit bootstrap for wp-saml-auth.
 * - Auto-installs WP test suite if missing (so early phpunit calls don’t fail).
 * - Ensures the test database exists before WP tries to select it.
 * - Loads Yoast PHPUnit Polyfills early.
 * - Uses wordpress-develop /src as ABSPATH if /tmp/wordpress isn't ready yet.
 * - Preserves your plugin/CLI loading, option defaults, and wp_logout shim.
 */

$env = fn($k, $d=null) => getenv($k) !== false ? getenv($k) : $d;

$WP_VERSION  = $env('WP_VERSION', '6.8.3');
$WP_CORE_DIR = rtrim($env('WP_CORE_DIR', '/tmp/wordpress'), '/');
$_tests_dir  = rtrim($env('WP_TESTS_DIR', '/tmp/wordpress-tests-lib'), '/');
$POLY_DIR    = rtrim($env('WP_TESTS_PHPUNIT_POLYFILLS_PATH', '/tmp/phpunit-deps'), '/');

$DB_HOST = $env('DB_HOST', '127.0.0.1');
$DB_USER = $env('DB_USER', 'root');
$DB_PASS = $env('DB_PASSWORD', 'root');
$DB_NAME = $env('DB_NAME', 'wp_test_boot');


/** ---------- Polyfills (load early) ---------- */
if (is_file($POLY_DIR . '/vendor/autoload.php')) {
	require_once $POLY_DIR . '/vendor/autoload.php';
} else {
	$fallback = dirname(__DIR__, 2) . '/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php';
	if (is_file($fallback)) {
		require_once $fallback;
	}
}

/** ---------- Ensure test DB exists (for early phpunit runs) ---------- */
$mysqli = @mysqli_init();
if ($mysqli && @$mysqli->real_connect($DB_HOST, $DB_USER, $DB_PASS)) {
	// Create DB if missing; use utf8mb4 for parity with CI script.
	@$mysqli->query("CREATE DATABASE IF NOT EXISTS `{$DB_NAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
	@$mysqli->close();
}

/** We'll decide ABSPATH dynamically */
$DEVDIR_SRC = null;

/** ---------- Ensure WP test suite exists ---------- */
$includes_bootstrap = $_tests_dir . '/includes/bootstrap.php';
if (! is_file($includes_bootstrap)) {
	// Fetch wordpress-develop tarball and extract tests/phpunit into $_tests_dir
	$tgz = "/tmp/wordpress-develop-{$WP_VERSION}.tar.gz";
	if (! is_file($tgz)) {
		$url = "https://github.com/WordPress/wordpress-develop/archive/refs/tags/{$WP_VERSION}.tar.gz";
		$tmp = @fopen($url, 'r');
		if (!$tmp) {
			fwrite(STDERR, "ERROR: Unable to download {$url}\n");
			exit(1);
		}
		file_put_contents($tgz, $tmp);
	}
	$extract = "/tmp/wp-develop-{$WP_VERSION}";
	if (is_dir($extract)) {
		$iter = new RecursiveIteratorIterator(
			new RecursiveDirectoryIterator($extract, FilesystemIterator::SKIP_DOTS),
			RecursiveIteratorIterator::CHILD_FIRST
		);
		foreach ($iter as $f) { $f->isDir() ? @rmdir($f) : @unlink($f); }
		@rmdir($extract);
	}
	@mkdir($extract, 0777, true);

	// Extract
	$phar = new PharData($tgz);
	$phar->decompress(); // creates .tar next to .tar.gz
	$tar = str_replace('.gz', '', $tgz);
	$pharTar = new PharData($tar);
	$pharTar->extractTo($extract);

	// Find folder like wordpress-develop-x.y.z
	$devDir = null;
	foreach (glob($extract . '/wordpress-develop-*') as $cand) {
		if (is_dir($cand)) { $devDir = $cand; break; }
	}
	if (! $devDir || ! is_dir($devDir . '/tests/phpunit')) {
		fwrite(STDERR, "ERROR: wordpress-develop tests not found for {$WP_VERSION}\n");
		exit(1);
	}

	// Remember /src for ABSPATH fallback
	if (is_dir($devDir . '/src')) {
		$DEVDIR_SRC = rtrim($devDir . '/src', '/') . '/';
	}

	if (! is_dir($_tests_dir)) {
		@mkdir($_tests_dir, 0777, true);
	}

	// Copy tests/phpunit/* -> $_tests_dir
	$it = new RecursiveIteratorIterator(
		new RecursiveDirectoryIterator($devDir . '/tests/phpunit', FilesystemIterator::SKIP_DOTS),
		RecursiveIteratorIterator::SELF_FIRST
	);
	foreach ($it as $src) {
		$rel = substr($src->getPathname(), strlen($devDir . '/tests/phpunit'));
		$dst = $_tests_dir . $rel;
		if ($src->isDir()) {
			if (! is_dir($dst)) @mkdir($dst, 0777, true);
		} else {
			@copy($src->getPathname(), $dst);
		}
	}

	// Decide ABSPATH for early run:
	$ABSPATH = (is_file($WP_CORE_DIR . '/wp-settings.php'))
		? rtrim($WP_CORE_DIR, '/') . '/'
		: ($DEVDIR_SRC ?: rtrim($WP_CORE_DIR, '/') . '/');

	// Write wp-tests-config.php (NOTE: we DO NOT define WP_PHP_BINARY here to avoid "already defined" warnings)
	$cfg = <<<PHP
<?php
define( 'DB_NAME', '{$DB_NAME}' );
define( 'DB_USER', '{$DB_USER}' );
define( 'DB_PASSWORD', '{$DB_PASS}' );
define( 'DB_HOST', '{$DB_HOST}' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );
define( 'WP_TESTS_DOMAIN', 'example.org' );
define( 'WP_TESTS_EMAIL', 'admin@example.org' );
define( 'WP_TESTS_TITLE', 'Test Blog' );
\$table_prefix = 'wptests_';
define( 'ABSPATH', '{$ABSPATH}' );
define( 'WP_TESTS_PHPUNIT_POLYFILLS_PATH', '{$POLY_DIR}' );
PHP;
	file_put_contents($_tests_dir . '/wp-tests-config.php', $cfg);

	$includes_bootstrap = $_tests_dir . '/includes/bootstrap.php';
	if (! is_file($includes_bootstrap)) {
		fwrite(STDERR, "ERROR: WP tests bootstrap still missing in {$_tests_dir}\n");
		exit(1);
	}
} else {
	// tests already present; if ABSPATH points to /tmp/wordpress but core isn't there, use /src
	$core_has_settings = is_file($WP_CORE_DIR . '/wp-settings.php');
	if (! $core_has_settings && !defined('ABSPATH')) {
		foreach (glob('/tmp/wp-develop-*', GLOB_ONLYDIR) as $ex) {
			if (is_dir($ex . '/wordpress-develop-' . $WP_VERSION . '/src')) {
				$DEVDIR_SRC = rtrim($ex . '/wordpress-develop-' . $WP_VERSION . '/src', '/') . '/';
				break;
			}
			if (is_dir($ex . '/src')) {
				$DEVDIR_SRC = rtrim($ex . '/src', '/') . '/';
				break;
			}
		}
		if ($DEVDIR_SRC) {
			define('ABSPATH', $DEVDIR_SRC);
		}
	}

	// Also sanitize an old wp-tests-config.php that may define WP_PHP_BINARY / WP_RUN_CORE_TESTS
	$config_file = $_tests_dir . '/wp-tests-config.php';
	if (is_file($config_file) && is_writable($config_file)) {
		$cfg = file_get_contents($config_file);
		$cfg2 = preg_replace('/^\s*define\(\s*[\'"]WP_PHP_BINARY[\'"].*?\);\s*$/m', '', $cfg);
		$cfg2 = preg_replace('/^\s*define\(\s*[\'"]WP_RUN_CORE_TESTS[\'"].*?\);\s*$/m', '', $cfg2);
		if ($cfg2 !== null && $cfg2 !== $cfg) {
			file_put_contents($config_file, $cfg2);
		}
	}
}

/** ---------- Ensure required constants even if config predates new ones ---------- */
if (!defined('WP_PHP_BINARY')) {
	define('WP_PHP_BINARY', PHP_BINARY ?: 'php');
}
if (!defined('WP_RUN_CORE_TESTS')) {
	define('WP_RUN_CORE_TESTS', false);
}

/** ---------- Provide tests_add_filter ---------- */
require_once $_tests_dir . '/includes/functions.php';

/** ---------- Load plugin & CLI (preserving your logic) ---------- */
function _manually_load_plugin() {
	$root = dirname(__DIR__, 2);

	foreach (['/wp-saml-auth.php','/plugin.php','/index.php'] as $rel) {
		$p = $root . $rel;
		if (file_exists($p)) { require $p; break; }
	}

	$cli_main = $root . '/inc/class-wp-saml-auth-cli.php';
	if (file_exists($cli_main)) { require $cli_main; }

	$cli_test = __DIR__ . '/class-wp-saml-auth-test-cli.php';
	if (file_exists($cli_test)) { require $cli_test; }

	add_filter('wp_saml_auth_option', '_wp_saml_auth_filter_option', 10, 2);
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');

/** ---------- Option defaults preserved ---------- */
function _wp_saml_auth_filter_option($value, $name) {
	if ($name === 'simplesamlphp_autoload') {
		$autoload = getenv('SIMPLESAMLPHP_AUTOLOAD');
		if ($autoload && file_exists($autoload)) return $autoload;
		return '/tmp/simplesamlphp-stub/autoload.php';
	}
	if ($name === 'auto_provision') return true;
	if ($name === 'permit_wp_login') return true;
	if ($name === 'default_role') return 'subscriber';
	return $value;
}

/** ---------- wp_logout shim (as before) ---------- */
if (! function_exists('wp_logout')) {
	function wp_logout() {
		if (function_exists('wp_destroy_current_session')) wp_destroy_current_session();
		if (function_exists('wp_set_current_user')) wp_set_current_user(0);
		do_action('wp_logout');
	}
}

/** ---------- Finally load the WP tests bootstrap (defines WP_UnitTestCase) ---------- */
require $_tests_dir . '/includes/bootstrap.php';

