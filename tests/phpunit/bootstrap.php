<?php
/**
 * Deterministic PHPUnit bootstrap for wp-saml-auth
 * - Creates a SimpleSAML stub in /tmp and preloads it (no repo file needed)
 * - Self-provisions WP tests if missing
 * - Ensures DB & ABSPATH
 * - Supplies a full settings array (incl. provider & autoload) before plugin init
 * - Keeps Behat untouched
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

/** ---------- Create & preload SimpleSAML stub in /tmp ---------- */
$STUB_DIR = '/tmp/simplesamlphp-stub';
$STUB_AUTOLOAD = $STUB_DIR . '/autoload.php';

if (!is_dir($STUB_DIR)) {
	@mkdir($STUB_DIR, 0777, true);
}
if (!is_file($STUB_AUTOLOAD)) {
	file_put_contents($STUB_AUTOLOAD, <<<'PHP'
<?php
namespace SimpleSAML\Auth;

class Simple {
    private $authed = false; // default: unauthenticated
    private $attrs;

    public function __construct($sp) {
        $this->attrs = [
            'uid'         => ['testuser'],
            'mail'        => ['testuser@example.com'],
            'givenName'   => ['Test'],
            'sn'          => ['User'],
            'displayName' => ['Test User'],
        ];
        if ($env = getenv('WPSA_TEST_SAML_ATTRS')) {
            $json = json_decode($env, true);
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

    public function requireAuth(): void {
        $forced = getenv('WPSA_TEST_SAML_AUTHED');
        $this->authed = ($forced !== false) ? (bool)(int)$forced : true;
    }

    public function isAuthenticated(): bool { return $this->authed; }
    public function getAttributes(): array { return $this->attrs; }
    public function logout($params = []) { $this->authed = false; return true; }
}
PHP
	);
}
require_once $STUB_AUTOLOAD; // ensure class exists before plugin init

/** ---------- Polyfills ---------- */
if (is_file($POLY_DIR . '/vendor/autoload.php')) {
	require_once $POLY_DIR . '/vendor/autoload.php';
} else {
	$fallback = dirname(__DIR__, 2) . '/vendor/yoast/phpunit-polyfills/phpunitpolyfills-autoload.php';
	if (is_file($fallback)) {
		require_once $fallback;
	}
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
			if (is_dir($ex . '/src')) {
				$DEVDIR_SRC = rtrim($ex . '/src', '/') . '/'; break;
			}
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

/** ---------- EARLY: full settings so plugin always instantiates client ---------- */
$__wpsa_settings = [
	'provider'               => 'test-sp',
	'auto_provision'         => true,
	'permit_wp_login'        => false,      // <-- was true
	'user_claim'             => 'mail',
	'map_by_email'           => true,
	'default_role'           => 'student',  // <-- was subscriber
	'display_name_mapping'   => 'display_name',
	'attribute_mapping'      => [
		'user_login'   => 'uid',
		'user_email'   => 'mail',
		'first_name'   => 'givenName',
		'last_name'    => 'sn',
		'display_name' => 'displayName',
	],
	'simplesamlphp_autoload' => $STUB_AUTOLOAD,
];

tests_add_filter(
	'pre_option_wp_saml_auth_settings',
	fn($pre) => $__wpsa_settings,
	10,
	1
);

/** ---------- Per-option filter (2 args) kept for realism ---------- */
tests_add_filter(
	'wp_saml_auth_option',
	function ($value, $name) use ($STUB_AUTOLOAD) {
		if ($name === 'simplesamlphp_autoload') return $STUB_AUTOLOAD;
		if ($name === 'provider')               return 'test-sp';
		if ($name === 'auto_provision')         return true;
		if ($name === 'permit_wp_login')        return false;     // <-- was true
		if ($name === 'default_role')           return 'student'; // <-- was subscriber
		if ($name === 'user_claim')             return 'mail';
		if ($name === 'map_by_email')           return true;
		if ($name === 'display_name_mapping')   return 'display_name';
		if ($name === 'attribute_mapping') {
			return [
				'user_login'   => 'uid',
				'user_email'   => 'mail',
				'first_name'   => 'givenName',
				'last_name'    => 'sn',
				'display_name' => 'displayName',
			];
		}
		return $value;
	},
	10,
	2
);

/** ---------- Load plugin during muplugins_loaded ---------- */
function _wpsa_manually_load_plugin() {
	global $__wpsa_settings;
	// Ensure runtime option exists for any direct get_option() calls.
	update_option('wp_saml_auth_settings', $__wpsa_settings);

	$root = dirname(__DIR__, 2);
	foreach (['/wp-saml-auth.php','/plugin.php','/index.php'] as $rel) {
		$p = $root . $rel;
		if (file_exists($p)) { require $p; break; }
	}

	$cli_main = $root . '/inc/class-wp-saml-auth-cli.php';
	if (file_exists($cli_main)) require $cli_main;
	$cli_test = __DIR__ . '/class-wp-saml-auth-test-cli.php';
	if (file_exists($cli_test)) require $cli_test;
}
tests_add_filter('muplugins_loaded', '_wpsa_manually_load_plugin');

/** ---------- wp_logout shim ---------- */
if (!function_exists('wp_logout')) {
	function wp_logout() {
		if (function_exists('wp_destroy_current_session')) wp_destroy_current_session();
		if (function_exists('wp_set_current_user')) wp_set_current_user(0);
		do_action('wp_logout');
	}
}

/** ---------- Finally bootstrap WP tests ---------- */
require $_tests_dir . '/includes/bootstrap.php';
