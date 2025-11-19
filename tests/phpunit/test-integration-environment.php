<?php
/**
 * Integration tests for database and environment validation
 *
 * @package WP_SAML_Auth
 */

/**
 * Class Test_Integration_Environment
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
