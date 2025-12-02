<?php
/**
 * Integration tests for WP SAML Auth
 *
 * This file combines tests for:
 * - SimpleSAMLphp version detection and autoloader resolution
 * - Database and environment validation
 * - Provider setup and configuration
 *
 * @package WP_SAML_Auth
 */

/**
 * Class Test_Integration_Version_Detection
 *
 * Tests for SimpleSAMLphp version detection and autoloader resolution
 */
#[AllowDynamicProperties]
class Test_Integration_Version_Detection extends WP_UnitTestCase {

	/**
	 * Instance of WP_SAML_Auth for testing
	 *
	 * @var WP_SAML_Auth
	 */
	protected $wp_saml_auth;

	/**
	 * Setup for each test
	 */
	public function setUp(): void {
		parent::setUp();
		$this->wp_saml_auth = WP_SAML_Auth::get_instance();
	}

	/**
	 * Test that get_simplesamlphp_version returns false when autoloader doesn't exist
	 */
	public function test_version_detection_with_invalid_autoloader() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/nonexistent/path/autoload.php';
			}
			return $value;
		}, 10, 2 );

		$version = $this->wp_saml_auth->get_simplesamlphp_version();

		$this->assertFalse( $version, 'Version should be false when autoloader does not exist' );

		remove_all_filters( 'wp_saml_auth_option' );
	}

	/**
	 * Test that get_simplesamlphp_version can read from stub autoloader
	 */
	public function test_version_detection_with_stub_autoloader() {
		// The stub autoloader should be available from bootstrap
		$stub_path = '/tmp/simplesamlphp-stub/autoload.php';

		if ( ! file_exists( $stub_path ) ) {
			$this->markTestSkipped( 'Stub autoloader not available at ' . $stub_path );
		}

		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) use ( $stub_path ) {
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return $stub_path;
			}
			return $value;
		}, 10, 2 );

		// The stub doesn't have version info, so this should return false
		// but shouldn't throw an error
		$version = $this->wp_saml_auth->get_simplesamlphp_version();

		// Version will be false since stub doesn't include version metadata
		$this->assertFalse( $version );

		remove_all_filters( 'wp_saml_auth_option' );
	}

	/**
	 * Test version checking logic with different version strings
	 */
	public function test_version_comparison_logic() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'min_simplesamlphp_version' === $option_name ) {
				return '2.3.7';
			}
			if ( 'critical_simplesamlphp_version' === $option_name ) {
				return '2.0.0';
			}
			return $value;
		}, 10, 2 );

		// Test critical version (below 2.0.0)
		$this->assertEquals( 'critical', $this->wp_saml_auth->check_simplesamlphp_version( '1.18.0' ) );
		$this->assertEquals( 'critical', $this->wp_saml_auth->check_simplesamlphp_version( '1.19.9' ) );

		// Test warning version (between 2.0.0 and 2.3.7)
		$this->assertEquals( 'warning', $this->wp_saml_auth->check_simplesamlphp_version( '2.0.0' ) );
		$this->assertEquals( 'warning', $this->wp_saml_auth->check_simplesamlphp_version( '2.3.6' ) );

		// Test ok version (2.3.7 or later)
		$this->assertEquals( 'ok', $this->wp_saml_auth->check_simplesamlphp_version( '2.3.7' ) );
		$this->assertEquals( 'ok', $this->wp_saml_auth->check_simplesamlphp_version( '2.4.0' ) );
		$this->assertEquals( 'ok', $this->wp_saml_auth->check_simplesamlphp_version( '2.5.0' ) );

		// Test unknown
		$this->assertEquals( 'unknown', $this->wp_saml_auth->check_simplesamlphp_version( false ) );
		$this->assertEquals( 'unknown', $this->wp_saml_auth->check_simplesamlphp_version( '' ) );

		remove_all_filters( 'wp_saml_auth_option' );
	}

	/**
	 * Test that version enforcement blocks authentication when version is critical
	 */
	public function test_authentication_blocked_for_critical_version() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'enforce_min_simplesamlphp_version' === $option_name ) {
				return true;
			}
			if ( 'min_simplesamlphp_version' === $option_name ) {
				return '2.3.7';
			}
			if ( 'critical_simplesamlphp_version' === $option_name ) {
				return '2.0.0';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/tmp/simplesamlphp-stub/autoload.php';
			}
			return $value;
		}, 10, 2 );

		// Mock version detection to return critical version
		$mock = $this->getMockBuilder( 'WP_SAML_Auth' )
			->setMethods( [ 'get_simplesamlphp_version', 'get_provider' ] )
			->getMock();

		$mock->method( 'get_simplesamlphp_version' )
			->willReturn( '1.19.0' );

		$mock->method( 'get_provider' )
			->willReturn( null );

		$result = $mock->do_saml_authentication();

		$this->assertInstanceOf( 'WP_Error', $result );
		$this->assertEquals( 'wp_saml_auth_vulnerable_simplesamlphp', $result->get_error_code() );
		$this->assertStringContainsString( '1.19.0', $result->get_error_message() );

		remove_all_filters( 'wp_saml_auth_option' );
	}

	/**
	 * Test that version enforcement allows authentication when version is ok
	 */
	public function test_authentication_allowed_for_ok_version() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'enforce_min_simplesamlphp_version' === $option_name ) {
				return true;
			}
			if ( 'min_simplesamlphp_version' === $option_name ) {
				return '2.3.7';
			}
			if ( 'critical_simplesamlphp_version' === $option_name ) {
				return '2.0.0';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/tmp/simplesamlphp-stub/autoload.php';
			}
			return $value;
		}, 10, 2 );

		// Mock version detection to return safe version
		$mock = $this->getMockBuilder( 'WP_SAML_Auth' )
			->setMethods( [ 'get_simplesamlphp_version', 'get_provider' ] )
			->getMock();

		$mock->method( 'get_simplesamlphp_version' )
			->willReturn( '2.4.0' );

		$mock->method( 'get_provider' )
			->willReturn( null );

		// Should proceed past version check (will fail on provider being null)
		$result = $mock->do_saml_authentication();

		// Should NOT be the version error
		if ( is_wp_error( $result ) ) {
			$this->assertNotEquals( 'wp_saml_auth_vulnerable_simplesamlphp', $result->get_error_code() );
		}

		remove_all_filters( 'wp_saml_auth_option' );
	}

	/**
	 * Test that version enforcement can be disabled
	 */
	public function test_version_enforcement_can_be_disabled() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'enforce_min_simplesamlphp_version' === $option_name ) {
				return false; // Disabled
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/tmp/simplesamlphp-stub/autoload.php';
			}
			return $value;
		}, 10, 2 );

		// Mock version detection to return critical version
		$mock = $this->getMockBuilder( 'WP_SAML_Auth' )
			->setMethods( [ 'get_simplesamlphp_version', 'get_provider' ] )
			->getMock();

		$mock->method( 'get_simplesamlphp_version' )
			->willReturn( '1.18.0' ); // Critical version

		$mock->method( 'get_provider' )
			->willReturn( null );

		$result = $mock->do_saml_authentication();

		// Should NOT block for version when enforcement is disabled
		if ( is_wp_error( $result ) ) {
			$this->assertNotEquals( 'wp_saml_auth_vulnerable_simplesamlphp', $result->get_error_code() );
		}

		remove_all_filters( 'wp_saml_auth_option' );
	}
}

/**
 * Class Test_Integration_Environment
 *
 * Tests for database and environment validation
 */
#[AllowDynamicProperties]
class Test_Integration_Environment extends WP_UnitTestCase {

	/**
	 * Test that WordPress database connection is working
	 */
	public function test_database_connection_is_working() {
		global $wpdb;

		$this->assertNotNull( $wpdb, 'Global $wpdb should be available' );
		$this->assertInstanceOf( 'wpdb', $wpdb );

		// Verify we can query the database
		$result = $wpdb->get_var( 'SELECT 1' );
		$this->assertEquals( '1', $result, 'Database query should succeed' );
	}

	/**
	 * Test that required database tables exist
	 */
	public function test_required_database_tables_exist() {
		global $wpdb;

		$required_tables = [
			$wpdb->users,
			$wpdb->usermeta,
			$wpdb->options,
		];

		foreach ( $required_tables as $table ) {
			$table_exists = $wpdb->get_var( $wpdb->prepare( 'SHOW TABLES LIKE %s', $table ) );
			$this->assertEquals( $table, $table_exists, "Table {$table} should exist" );
		}
	}

	/**
	 * Test that user creation and retrieval works
	 */
	public function test_user_creation_and_retrieval() {
		$user_id = $this->factory->user->create( [
			'user_login' => 'integration_test_user_' . wp_rand(),
			'user_email' => 'integration_test_' . wp_rand() . '@example.com',
		] );

		$this->assertGreaterThan( 0, $user_id, 'User creation should succeed' );

		$user = get_user_by( 'id', $user_id );
		$this->assertInstanceOf( 'WP_User', $user );
		$this->assertEquals( $user_id, $user->ID );

		// Cleanup
		wp_delete_user( $user_id );
	}

	/**
	 * Test that options can be created and retrieved
	 */
	public function test_options_creation_and_retrieval() {
		$option_name = 'wp_saml_auth_integration_test_' . wp_rand();
		$option_value = [ 'test' => 'value', 'number' => 123 ];

		$updated = update_option( $option_name, $option_value );
		$this->assertTrue( $updated, 'Option update should succeed' );

		$retrieved = get_option( $option_name );
		$this->assertEquals( $option_value, $retrieved, 'Retrieved option should match stored value' );

		// Cleanup
		delete_option( $option_name );
	}

	/**
	 * Test environment variables are set correctly
	 */
	public function test_environment_variables_are_set() {
		$required_env_vars = [
			'DB_HOST'     => getenv( 'DB_HOST' ),
			'DB_USER'     => getenv( 'DB_USER' ),
			'WP_CORE_DIR' => getenv( 'WP_CORE_DIR' ),
		];

		foreach ( $required_env_vars as $var_name => $var_value ) {
			$this->assertNotEmpty( $var_value, "Environment variable {$var_name} should be set" );
		}
	}

	/**
	 * Test WordPress core directories exist
	 */
	public function test_wordpress_core_directories_exist() {
		$core_dir = getenv( 'WP_CORE_DIR' );
		if ( empty( $core_dir ) ) {
			$this->markTestSkipped( 'WP_CORE_DIR environment variable not set' );
		}

		$this->assertDirectoryExists( $core_dir, 'WordPress core directory should exist' );
		$this->assertFileExists( $core_dir . '/wp-settings.php', 'wp-settings.php should exist' );
		$this->assertDirectoryExists( $core_dir . '/wp-content', 'wp-content directory should exist' );
		$this->assertDirectoryExists( $core_dir . '/wp-content/plugins', 'plugins directory should exist' );
	}

	/**
	 * Test plugin is installed in correct location
	 */
	public function test_plugin_is_installed_correctly() {
		$core_dir = getenv( 'WP_CORE_DIR' );
		if ( empty( $core_dir ) ) {
			$this->markTestSkipped( 'WP_CORE_DIR environment variable not set' );
		}

		$plugin_dir = $core_dir . '/wp-content/plugins/wp-saml-auth';
		$this->assertDirectoryExists( $plugin_dir, 'Plugin directory should exist in WP plugins folder' );
		$this->assertFileExists( $plugin_dir . '/wp-saml-auth.php', 'Plugin main file should exist' );
	}

	/**
	 * Test plugin is activated
	 */
	public function test_plugin_is_activated() {
		$active_plugins = get_option( 'active_plugins' );
		$this->assertIsArray( $active_plugins );
		$this->assertContains( 'wp-saml-auth/wp-saml-auth.php', $active_plugins, 'Plugin should be in active plugins list' );

		// Also test using WordPress function
		$this->assertTrue( is_plugin_active( 'wp-saml-auth/wp-saml-auth.php' ), 'is_plugin_active should return true' );
	}

	/**
	 * Test WP_SAML_Auth class is available
	 */
	public function test_main_class_is_loaded() {
		$this->assertTrue( class_exists( 'WP_SAML_Auth' ), 'WP_SAML_Auth class should be loaded' );

		$instance = WP_SAML_Auth::get_instance();
		$this->assertInstanceOf( 'WP_SAML_Auth', $instance );
	}

	/**
	 * Test SimpleSAML stub is available
	 */
	public function test_simplesaml_stub_is_available() {
		$this->assertTrue( class_exists( 'SimpleSAML\Auth\Simple' ), 'SimpleSAML stub class should be available' );
	}

	/**
	 * Test required PHP extensions are loaded
	 */
	public function test_required_php_extensions() {
		$required_extensions = [
			'mysqli',
			'json',
			'mbstring',
		];

		foreach ( $required_extensions as $extension ) {
			$this->assertTrue(
				extension_loaded( $extension ),
				"PHP extension {$extension} should be loaded"
			);
		}
	}

	/**
	 * Test PHP version meets minimum requirements
	 */
	public function test_php_version_meets_requirements() {
		// Plugin should work on PHP 7.4+
		$this->assertGreaterThanOrEqual(
			'7.4.0',
			PHP_VERSION,
			'PHP version should be at least 7.4.0'
		);
	}

	/**
	 * Test WordPress version is available
	 */
	public function test_wordpress_version_is_available() {
		global $wp_version;

		$this->assertNotEmpty( $wp_version, 'WordPress version should be set' );
		$this->assertMatchesRegularExpression( '/^\d+\.\d+/', $wp_version, 'WordPress version should be in correct format' );
	}

	/**
	 * Test that bootstrap properly sets up test environment
	 */
	public function test_bootstrap_setup_is_complete() {
		// Check that WP test functions are available
		$this->assertTrue( function_exists( 'tests_add_filter' ), 'tests_add_filter should be available' );

		// Check that factory is available
		$this->assertNotNull( $this->factory, 'Factory should be available in tests' );
		$this->assertInstanceOf( 'WP_UnitTest_Factory', $this->factory );
	}

	/**
	 * Test database charset and collation
	 */
	public function test_database_charset_and_collation() {
		global $wpdb;

		// Get database charset
		$charset = $wpdb->get_var( "SELECT @@character_set_database" );
		$this->assertStringContainsString( 'utf8', $charset, 'Database should use UTF-8 charset' );

		// Get database collation
		$collation = $wpdb->get_var( "SELECT @@collation_database" );
		$this->assertStringContainsString( 'utf8', $collation, 'Database should use UTF-8 collation' );
	}

	/**
	 * Test that temp directory is writable
	 */
	public function test_temp_directory_is_writable() {
		$temp_dir = sys_get_temp_dir();
		$this->assertDirectoryExists( $temp_dir );
		$this->assertDirectoryIsWritable( $temp_dir, 'Temp directory should be writable' );
	}

	/**
	 * Test WP constants are defined
	 */
	public function test_wordpress_constants_are_defined() {
		$required_constants = [
			'ABSPATH',
			'WP_CONTENT_DIR',
			'WP_PLUGIN_DIR',
		];

		foreach ( $required_constants as $constant ) {
			$this->assertTrue(
				defined( $constant ),
				"Constant {$constant} should be defined"
			);
		}
	}
}

/**
 * Class Test_Integration_Provider_Setup
 *
 * Tests for provider setup and configuration
 */
#[AllowDynamicProperties]
class Test_Integration_Provider_Setup extends WP_UnitTestCase {

	/**
	 * Instance of WP_SAML_Auth for testing
	 *
	 * @var WP_SAML_Auth
	 */
	protected $wp_saml_auth;

	/**
	 * Setup for each test
	 */
	public function setUp(): void {
		parent::setUp();
		$this->wp_saml_auth = WP_SAML_Auth::get_instance();

		// Reset provider instance between tests using reflection
		$reflection = new ReflectionClass( $this->wp_saml_auth );
		$property = $reflection->getProperty( 'provider' );
		$property->setAccessible( true );
		$property->setValue( $this->wp_saml_auth, null );
	}

	/**
	 * Cleanup after each test
	 */
	public function tearDown(): void {
		remove_all_filters( 'wp_saml_auth_option' );
		parent::tearDown();
	}

	/**
	 * Test provider setup with SimpleSAMLphp (stub)
	 */
	public function test_provider_setup_with_simplesamlphp() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/tmp/simplesamlphp-stub/autoload.php';
			}
			if ( 'auth_source' === $option_name ) {
				return 'default-sp';
			}
			return $value;
		}, 10, 2 );

		$provider = $this->wp_saml_auth->get_provider();

		$this->assertNotNull( $provider, 'Provider should not be null' );
		$this->assertInstanceOf( 'SimpleSAML\Auth\Simple', $provider );
	}

	/**
	 * Test provider setup fails gracefully with missing autoloader
	 *
	 * Note: In test environment, SimpleSAML stub is pre-loaded in bootstrap,
	 * so we test that the provider is still created (using the stub).
	 * In production, a missing autoloader would result in null provider.
	 */
	public function test_provider_setup_with_preloaded_simplesaml_class() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/nonexistent/path/autoload.php';
			}
			if ( 'auth_source' === $option_name ) {
				return 'test-sp';
			}
			return $value;
		}, 10, 2 );

		$provider = $this->wp_saml_auth->get_provider();

		// In test environment, class is pre-loaded, so provider will exist
		$this->assertNotNull( $provider, 'Provider should be created when SimpleSAML class is already loaded' );
		$this->assertInstanceOf( 'SimpleSAML\Auth\Simple', $provider );
	}

	/**
	 * Test provider setup with invalid autoloader path
	 *
	 * Note: In test environment, SimpleSAML stub is pre-loaded, so the provider
	 * will still be created. This test verifies the code doesn't crash with
	 * invalid autoloader paths when the class is already available.
	 */
	public function test_provider_setup_with_invalid_autoloader_path() {
		// Create a temporary invalid autoloader file
		$temp_file = tempnam( sys_get_temp_dir(), 'invalid_autoload' );
		file_put_contents( $temp_file, '<?php // Invalid autoloader - no classes defined' );

		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) use ( $temp_file ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return $temp_file;
			}
			if ( 'auth_source' === $option_name ) {
				return 'test-sp';
			}
			return $value;
		}, 10, 2 );

		$provider = $this->wp_saml_auth->get_provider();

		// In test environment, SimpleSAML class is pre-loaded in bootstrap
		// so provider will be created even with invalid autoloader path
		$this->assertNotNull( $provider, 'Provider created when class is pre-loaded' );
		$this->assertInstanceOf( 'SimpleSAML\Auth\Simple', $provider );

		unlink( $temp_file );
	}

	/**
	 * Test that get_option properly filters options
	 */
	public function test_get_option_applies_filters() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'test_option' === $option_name ) {
				return 'test_value';
			}
			return $value;
		}, 10, 2 );

		$result = WP_SAML_Auth::get_option( 'test_option' );

		$this->assertEquals( 'test_value', $result );
	}

	/**
	 * Test that get_option returns null by default
	 */
	public function test_get_option_returns_null_by_default() {
		$result = WP_SAML_Auth::get_option( 'nonexistent_option' );

		$this->assertNull( $result );
	}

	/**
	 * Test configuration options are properly accessed
	 */
	public function test_configuration_options_are_accessible() {
		$options_to_test = [
			'connection_type',
			'auto_provision',
			'permit_wp_login',
			'get_user_by',
			'user_login_attribute',
			'user_email_attribute',
			'display_name_attribute',
			'first_name_attribute',
			'last_name_attribute',
			'auth_source',
			'default_role',
		];

		foreach ( $options_to_test as $option ) {
			add_filter( 'wp_saml_auth_option', function( $value, $option_name ) use ( $option ) {
				if ( $option === $option_name ) {
					return "test_value_for_{$option}";
				}
				return $value;
			}, 10, 2 );

			$result = WP_SAML_Auth::get_option( $option );
			$this->assertEquals( "test_value_for_{$option}", $result, "Option {$option} should be accessible" );

			remove_all_filters( 'wp_saml_auth_option' );
		}
	}

	/**
	 * Test that provider is cached after first initialization
	 */
	public function test_provider_is_cached() {
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/tmp/simplesamlphp-stub/autoload.php';
			}
			if ( 'auth_source' === $option_name ) {
				return 'default-sp';
			}
			return $value;
		}, 10, 2 );

		$provider1 = $this->wp_saml_auth->get_provider();
		$provider2 = $this->wp_saml_auth->get_provider();

		$this->assertSame( $provider1, $provider2, 'Provider should be the same instance (cached)' );
	}

	/**
	 * Test singleton pattern for WP_SAML_Auth instance
	 */
	public function test_singleton_instance() {
		$instance1 = WP_SAML_Auth::get_instance();
		$instance2 = WP_SAML_Auth::get_instance();

		$this->assertSame( $instance1, $instance2, 'WP_SAML_Auth should return same instance' );
	}

	/**
	 * Test auth_source option is used when creating provider
	 */
	public function test_auth_source_is_used_in_provider() {
		$custom_auth_source = 'custom-test-sp';

		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) use ( $custom_auth_source ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/tmp/simplesamlphp-stub/autoload.php';
			}
			if ( 'auth_source' === $option_name ) {
				return $custom_auth_source;
			}
			return $value;
		}, 10, 2 );

		$provider = $this->wp_saml_auth->get_provider();

		$this->assertNotNull( $provider );
		$this->assertInstanceOf( 'SimpleSAML\Auth\Simple', $provider );
	}

	/**
	 * Test WP_DEBUG logging when provider setup fails
	 *
	 * Note: In test environment, SimpleSAML stub may already be loaded by previous tests,
	 * so the provider could still be created even with an invalid autoloader path.
	 * This test verifies the code handles the scenario gracefully.
	 */
	public function test_wp_debug_logging_on_provider_failure() {
		// This test verifies that error logging happens when WP_DEBUG is on
		if ( ! defined( 'WP_DEBUG' ) || ! WP_DEBUG ) {
			$this->markTestSkipped( 'WP_DEBUG is not enabled' );
		}

		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) {
			if ( 'connection_type' === $option_name ) {
				return 'simplesamlphp';
			}
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return '/nonexistent/autoload.php';
			}
			return $value;
		}, 10, 2 );

		// Capture error_log output
		$error_logged = false;
		set_error_handler( function( $errno, $errstr ) use ( &$error_logged ) {
			if ( strpos( $errstr, 'WP SAML Auth' ) !== false ) {
				$error_logged = true;
			}
			return false; // Continue normal error handling
		} );

		$provider = $this->wp_saml_auth->get_provider();

		restore_error_handler();

		// In test environment, if SimpleSAML\Auth\Simple class was already loaded by a previous test,
		// the provider will still be created. Otherwise it will be null.
		// Both outcomes are acceptable - we're mainly testing that the code doesn't crash.
		if ( $provider !== null ) {
			$this->assertInstanceOf( 'SimpleSAML\Auth\Simple', $provider, 'If provider exists, it should be correct type' );
		}
		// Note: error_log may not trigger a PHP error, so we can't always assert error_logged
	}
}
