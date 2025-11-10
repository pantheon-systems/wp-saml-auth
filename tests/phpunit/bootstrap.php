<?php
/**
 * PHPUnit bootstrap for wp-saml-auth.
 * - Self-provisions the WP test suite if missing.
 * - Ensures the test database exists for early phpunit calls.
 * - Uses wordpress-develop /src as ABSPATH when /tmp/wordpress isn’t ready yet.
 * - Loads Yoast PHPUnit Polyfills early.
 * - Creates a SimpleSAML stub and forces `simplesamlphp_autoload` using tests_add_filter()
 *   (so it’s ready before WP/plugin load).
 * - Loads the plugin during `muplugins_loaded` via tests_add_filter().
 * - Preserves your defaults and wp_logout shim.
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

/** ---------- Ensure test DB exists for early runs ---------- */
$mysqli = @mysqli_init();
if ($mysqli && @$mysqli->real_connect($DB_HOST, $DB_USER, $DB_PASS)) {
	@$mysqli->query("CREATE DATABASE IF NOT EXISTS `{$DB_NAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
	@$mysqli->close();
}

/** We'll decide ABSPATH dynamically */
$DEVDIR_SRC = null;

/** ---------- Self-provision WP test suite if missing ---------- */
$includes_bootstrap = $_tests_dir . '/includes/bootstrap.php';
if (! is_file($includes_bootstrap)) {
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

	$phar = new PharData($tgz);
	$phar->decompress(); // .tar
	$tar = str_replace('.gz', '', $tgz);
	$pharTar = new PharData($tar);
	$pharTar->extractTo($extract);

	$devDir = null;
	foreach (glob($extract . '/wordpress-develop-*') as $cand) {
		if (is_dir($cand)) { $devDir = $cand; break; }
	}
	if (! $devDir || ! is_dir($devDir . '/tests/phpunit')) {
		fwrite(STDERR, "ERROR: wordpress-develop tests not found for {$WP_VERSION}\n");
		exit(1);
	}

	if (is_dir($devDir . '/src')) {
		$DEVDIR_SRC = rtrim($devDir . '/src', '/') . '/';
	}

	@mkdir($_tests_dir, 0777, true);

	$it = new RecursiveIteratorIterator(
		new RecursiveDirectoryIterator($devDir . '/tests/phpunit', FilesystemIterator::SKIP_DOTS),
		RecursiveIteratorIterator::SELF_FIRST
	);
	foreach ($it as $src) {
		$rel = substr($src->getPathname(), strlen($devDir . '/tests/phpunit'));
		$dst = $_tests_dir . $rel;
		if ($src->isDir()) {
			@mkdir($dst, 0777, true);
		} else {
			@copy($src->getPathname(), $dst);
		}
	}

	$ABSPATH = (is_file($WP_CORE_DIR . '/wp-settings.php'))
		? rtrim($WP_CORE_DIR, '/') . '/'
		: ($DEVDIR_SRC ?: rtrim($WP_CORE_DIR, '/') . '/');

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
	if (!is_file($WP_CORE_DIR . '/wp-settings.php') && !defined('ABSPATH')) {
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
	// Strip old defines that can cause “already defined” warnings
	$config_file = $_tests_dir . '/wp-tests-config.php';
	if (is_file($config_file) && is_writable($config_file)) {
		$cfg = file_get_contents($config_file);
		$cfg2 = preg_replace('/^\s*define\(\s*[\'"]WP_PHP_BINARY[\'"].*?\);\s*$/m', '', $cfg);
		$cfg2 = preg_replace('/^\s*define\(\s*[\'"]WP_RUN_CORE_TESTS[\'"].*?\);\s*$/m', '', $cfg2);
		if ($cfg2 !== null && $cfg2 !== $cfg) file_put_contents($config_file, $cfg2);
	}
}

/** ---------- Ensure required constants even if config predates new ones ---------- */
if (!defined('WP_PHP_BINARY'))  define('WP_PHP_BINARY', PHP_BINARY ?: 'php');
if (!defined('WP_RUN_CORE_TESTS')) define('WP_RUN_CORE_TESTS', false);

/** ---------- Load test helper BEFORE using tests_add_filter() ---------- */
require_once $_tests_dir . '/includes/functions.php';

/**
 * ---------- SimpleSAML test stub + option via tests_add_filter() ----------
 * We create a stub autoload that defines \SimpleSAML\Auth\Simple.
 * Then we register the option with tests_add_filter so it’s present
 * when WordPress (and the plugin) boot.
 */
(function () {
	$stubDir  = '/tmp/simplesamlphp-stub';
	$autoload = $stubDir . '/autoload.php';

	if (!is_dir($stubDir)) {
		@mkdir($stubDir, 0777, true);
	}
	if (!file_exists($autoload)) {
		file_put_contents($autoload, <<<'PHP'
<?php
namespace SimpleSAML\Auth;

class Simple {
    private $authed = true; // default to authenticated for provisioning tests
    private $attrs;

    public function __construct($sp) {
        $this->attrs = [
            'uid'         => ['testuser'],
            'mail'        => ['testuser@example.com'],
            'givenName'   => ['Test'],
            'sn'          => ['User'],
            'displayName' => ['Test User'],
        ];
        $envAttrs = getenv('WPSA_TEST_SAML_ATTRS');
        if ($envAttrs) {
            $json = json_decode($envAttrs, true);
            if (is_array($json)) {
                foreach ($json as $k => $v) {
                    $this->attrs[$k] = is_array($v) ? array_values($v) : [$v];
                }
            }
        }
        $forced = getenv('WPSA_TEST_SAML_AUTHED');
        if ($forced !== false) {
            $this->authed = (bool)(int)$forced;
        }
    }

    public function isAuthenticated(): bool { return $this->authed; }
    public function getAttributes(): array { return $this->attrs; }
    public function logout($params = []) { $this->authed = false; return true; }
}
PHP
		);
	}

	// Register option defaults EARLY via tests_add_filter (no add_filter here).
	tests_add_filter('wp_saml_auth_option', function ($value, $name) use ($autoload) {
		if ($name === 'simplesamlphp_autoload') return $autoload;
		if ($name === 'auto_provision')        return true;
		if ($name === 'permit_wp_login')       return true;
		if ($name === 'default_role')          return 'subscriber';
		return $value;
	});
})();

/** ---------- Preserve your option filter (as fallback) ---------- */
function _wp_saml_auth_filter_option( $value, $name ) {
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

/** ---------- Load the plugin during muplugins_loaded (via tests_add_filter) ---------- */
function _manually_load_plugin() {
	$root = dirname(__DIR__, 2);

	// At this point WP is loaded; filters from tests_add_filter are active.
	foreach (['/wp-saml-auth.php','/plugin.php','/index.php'] as $rel) {
		$p = $root . $rel;
		if (file_exists($p)) { require $p; break; }
	}

	$cli_main = $root . '/inc/class-wp-saml-auth-cli.php';
	if (file_exists($cli_main)) { require $cli_main; }
	$cli_test = __DIR__ . '/class-wp-saml-auth-test-cli.php';
	if (file_exists($cli_test)) { require $cli_test; }
}
tests_add_filter('muplugins_loaded', '_manually_load_plugin');

/** ---------- wp_logout shim ---------- */
if (! function_exists('wp_logout')) {
	function wp_logout() {
		if (function_exists('wp_destroy_current_session')) wp_destroy_current_session();
		if (function_exists('wp_set_current_user')) wp_set_current_user(0);
		do_action('wp_logout');
	}
}

/** ---------- Finally load the WP tests bootstrap ---------- */
require $_tests_dir . '/includes/bootstrap.php';
