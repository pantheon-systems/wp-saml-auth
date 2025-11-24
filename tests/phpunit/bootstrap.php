<?php
/**
 * PHPUnit bootstrap for wp-saml-auth (NO mu-plugin load).
 * - Preloads SimpleSAML stub.
 * - Activates plugin via active_plugins option.
 * - Seeds plugin settings before WP loads plugins.
 * - Leaves Behat untouched.
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

/** ---------- Create SimpleSAML stub (but don't load it yet) ---------- */
$STUB_DIR = '/tmp/simplesamlphp-stub';
$STUB_AUTOLOAD = $STUB_DIR . '/autoload.php';
if (!is_dir($STUB_DIR)) @mkdir($STUB_DIR, 0777, true);
if (!is_file($STUB_AUTOLOAD)) {
	file_put_contents($STUB_AUTOLOAD, <<<'PHP'
<?php
namespace SimpleSAML\Auth;

class Simple {
    private $authed = false; // Start unauthenticated
    private $attrs;

    public function __construct($sp) {
        // Default attributes as a fallback
        $this->attrs = [
            'uid'         => ['testuser'],
            'mail'        => ['testuser@example.com'],
            'givenName'   => ['Test'],
            'sn'          => ['User'],
            'displayName' => ['Test User'],
        ];

        // Prefer the test's "current SAML user" if provided
        if (isset($GLOBALS['wp_saml_auth_current_user']) && is_array($GLOBALS['wp_saml_auth_current_user'])) {
            $this->attrs = $GLOBALS['wp_saml_auth_current_user'];
        }

        // Optional env-based attribute override
        if ($json = getenv('WPSA_TEST_SAML_ATTRS')) {
            $decoded = json_decode($json, true);
            if (is_array($decoded)) {
                $this->attrs = array_map(
                    fn($v) => is_array($v) ? array_values($v) : [$v],
                    $decoded
                );
            }
        }

        // Optional explicit auth override
        if (($forced = getenv('WPSA_TEST_SAML_AUTHED')) !== false) {
            $this->authed = (bool)(int)$forced;
        }
    }

    public function requireAuth(): void {
        // When the plugin forces SAML login, mark as authenticated and
        // refresh attributes from the test global if present
        if (isset($GLOBALS['wp_saml_auth_current_user']) && is_array($GLOBALS['wp_saml_auth_current_user'])) {
            $this->attrs = $GLOBALS['wp_saml_auth_current_user'];
        }

        $this->authed = true;

        // Env override wins if explicitly set
        if (($forced = getenv('WPSA_TEST_SAML_AUTHED')) !== false) {
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
// Don't load the stub here - let it be loaded via the filter below

/** ---------- Polyfills ---------- */
if (is_file($POLY_DIR . '/vendor/autoload.php')) {
	require_once $POLY_DIR . '/vendor/autoload.php';
} else {
	$fallback = dirname(__DIR__, 2) . '/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php';
	if (is_file($fallback)) require_once $fallback;
}

/** ---------- Ensure DB exists ---------- */
$mysqli = @mysqli_init();
if ($mysqli && @$mysqli->real_connect($DB_HOST, $DB_USER, $DB_PASS)) {
	@$mysqli->query("CREATE DATABASE IF NOT EXISTS `{$DB_NAME}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
	@$mysqli->close();
}

/** ---------- Provision WP test suite if missing ---------- */
$includes_bootstrap = $_tests_dir . '/includes/bootstrap.php';
$DEVDIR_SRC = null;

if (!is_file($includes_bootstrap)) {
	$tgz = "/tmp/wordpress-develop-{$WP_VERSION}.tar.gz";
	if (!is_file($tgz)) {
		$url = "https://github.com/WordPress/wordpress-develop/archive/refs/tags/{$WP_VERSION}.tar.gz";
		$tmp = @fopen($url, 'r');
		if (!$tmp) { fwrite(STDERR, "ERROR: Unable to download {$url}\n"); exit(1); }
		file_put_contents($tgz, $tmp);
	}
	$extract = "/tmp/wp-develop-{$WP_VERSION}";
	if (is_dir($extract)) {
		$it = new RecursiveIteratorIterator(
			new RecursiveDirectoryIterator($extract, FilesystemIterator::SKIP_DOTS),
			RecursiveIteratorIterator::CHILD_FIRST
		);
		foreach ($it as $f) { $f->isDir() ? @rmdir($f) : @unlink($f); }
		@rmdir($extract);
	}
	@mkdir($extract, 0777, true);

	$phar = new PharData($tgz); $phar->decompress();
	$tar = str_replace('.gz', '', $tgz);
	(new PharData($tar))->extractTo($extract);

	$devDir = null;
	foreach (glob($extract . '/wordpress-develop-*') as $cand) {
		if (is_dir($cand)) { $devDir = $cand; break; }
	}
	if (!$devDir || !is_dir($devDir . '/tests/phpunit')) {
		fwrite(STDERR, "ERROR: wordpress-develop tests not found for {$WP_VERSION}\n");
		exit(1);
	}
	if (is_dir($devDir . '/src')) $DEVDIR_SRC = rtrim($devDir . '/src', '/') . '/';

	@mkdir($_tests_dir, 0777, true);
	$it = new RecursiveIteratorIterator(
		new RecursiveDirectoryIterator($devDir . '/tests/phpunit', FilesystemIterator::SKIP_DOTS),
		RecursiveIteratorIterator::SELF_FIRST
	);
	foreach ($it as $src) {
		$rel = substr($src->getPathname(), strlen($devDir . '/tests/phpunit'));
		$dst = $_tests_dir . $rel;
		if ($src->isDir()) @mkdir($dst, 0777, true); else @copy($src->getPathname(), $dst);
	}

	$ABSPATH = (is_file($WP_CORE_DIR . '/wp-settings.php'))
		? rtrim($WP_CORE_DIR, '/') . '/'
		: ($DEVDIR_SRC ?: rtrim($WP_CORE_DIR, '/') . '/');

	file_put_contents($_tests_dir . '/wp-tests-config.php', <<<PHP
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
PHP
	);

	$includes_bootstrap = $_tests_dir . '/includes/bootstrap.php';
} else {
	if (!is_file($WP_CORE_DIR . '/wp-settings.php') && !defined('ABSPATH')) {
		foreach (glob('/tmp/wp-develop-*', GLOB_ONLYDIR) as $ex) {
			if (is_dir($ex . '/wordpress-develop-' . $WP_VERSION . '/src')) {
				$DEVDIR_SRC = rtrim($ex . '/wordpress-develop-' . $WP_VERSION . '/src', '/') . '/'; break;
			}
			if (is_dir($ex . '/src')) { $DEVDIR_SRC = rtrim($ex . '/src', '/') . '/'; break; }
		}
		if ($DEVDIR_SRC) define('ABSPATH', $DEVDIR_SRC);
	}
	$config_file = $_tests_dir . '/wp-tests-config.php';
	if (is_file($config_file) && is_writable($config_file)) {
		$cfg = file_get_contents($config_file);
		$cfg = preg_replace('/^\s*define\(\s*[\'"]WP_PHP_BINARY[\'"].*?\);\s*$/m', '', $cfg);
		$cfg = preg_replace('/^\s*define\(\s*[\'"]WP_RUN_CORE_TESTS[\'"].*?\);\s*$/m', '', $cfg);
		file_put_contents($config_file, $cfg);
	}
}

if (!defined('WP_PHP_BINARY'))     define('WP_PHP_BINARY', PHP_BINARY ?: 'php');
if (!defined('WP_RUN_CORE_TESTS')) define('WP_RUN_CORE_TESTS', false);

/** ---------- WP test helpers ---------- */
require_once $_tests_dir . '/includes/functions.php';


/**
 * Provide default simplesamlphp_autoload option for tests.
 * Points to the stub created above unless test overrides it.
 */
tests_add_filter(
	'wp_saml_auth_option',
	function ( $value, $name ) {
		if ( 'simplesamlphp_autoload' === $name ) {
			$autoload = getenv( 'SIMPLESAMLPHP_AUTOLOAD' );
			if ( $autoload && file_exists( $autoload ) ) {
				return $autoload;
			}
			// Return path to the stub created at bootstrap
			return '/tmp/simplesamlphp-stub/autoload.php';
		}

		return $value;
	},
	10,
	2
);

/**
 * Log the current user out.
 * Activate the plugin like a normal plugin (NO mu-plugins).
 * We add our plugin’s entry to active_plugins before WP loads them.
 *
 * @since 2.5.0
 * NOTE: Ensure the plugin folder exists under WP_PLUGIN_DIR (your CI
 * script already "syncs plugin to WP"; if needed, copy/symlink here).
 */
tests_add_filter( 'pre_option_active_plugins', function ($pre) {
	$list = is_array($pre) ? $pre : [];
	// Standard main file path: wp-saml-auth/wp-saml-auth.php
	if (!in_array('wp-saml-auth/wp-saml-auth.php', $list, true)) {
		$list[] = 'wp-saml-auth/wp-saml-auth.php';
	}
	return $list;
}, 10, 1 );

// Manually load the plugin before WP tries to load plugins
tests_add_filter('muplugins_loaded', function () {
	$WP_CORE_DIR = rtrim(getenv('WP_CORE_DIR') ?: '/tmp/wordpress', '/');
	$pluginFile = $WP_CORE_DIR . '/wp-content/plugins/wp-saml-auth/wp-saml-auth.php';
	if (file_exists($pluginFile)) {
		require_once $pluginFile;
	}
});

tests_add_filter('plugins_loaded', function () {
	$root    = dirname(__DIR__, 2);                    // repo root
	$cli     = $root . '/inc/class-wp-saml-auth-cli.php';
	$testCli = __DIR__ . '/class-wp-saml-auth-test-cli.php'; // adjust path if different

	if (is_file($cli))     require_once $cli;
	if (is_file($testCli)) require_once $testCli;
}, 1);

/** ---------- wp_logout shim ---------- */
if (!function_exists('wp_logout')) {
	function wp_logout() {
		if (function_exists('wp_destroy_current_session')) wp_destroy_current_session();
		if (function_exists('wp_set_current_user')) wp_set_current_user(0);
		do_action('wp_logout');
	}
}
// In tests/phpunit/bootstrap.php, BEFORE requiring WP tests bootstrap:
$pluginSrc = dirname(__DIR__, 2);                              // repo root
$pluginDst = rtrim(getenv('WP_PLUGIN_DIR') ?: $WP_CORE_DIR . '/wp-content/plugins', '/') . '/wp-saml-auth';

if (!is_dir($pluginDst)) {
	// Try symlink for speed; if it fails (e.g., on CI) fall back to copy.
	if (!@symlink($pluginSrc, $pluginDst)) {
		$it = new RecursiveIteratorIterator(
			new RecursiveDirectoryIterator($pluginSrc, FilesystemIterator::SKIP_DOTS),
			RecursiveIteratorIterator::SELF_FIRST
		);
		@mkdir($pluginDst, 0777, true);
		foreach ($it as $src) {
			$rel = substr($src->getPathname(), strlen($pluginSrc));
			$dst = $pluginDst . $rel;
			if ($src->isDir()) { @mkdir($dst, 0777, true); }
			else { @copy($src->getPathname(), $dst); }
		}
	}
}

/** ---------- Finally bootstrap WP tests (WP will load active plugins itself) ---------- */
require $_tests_dir . '/includes/bootstrap.php';
