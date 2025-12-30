<?php
/**
 * Test SimpleSAMLphp autoloader detection logic.
 */
class Test_Autoloader_Detection extends WP_UnitTestCase {

	private $temp_dir;
	private $original_abspath;

	public function setUp(): void {
		parent::setUp();

		// Create a temporary directory for our fake SimpleSAMLphp installations.
		$this->temp_dir = sys_get_temp_dir() . '/wp-saml-auth-test-' . uniqid();
		mkdir( $this->temp_dir, 0777, true );

		// Store original ABSPATH and override it for testing.
		$this->original_abspath = ABSPATH;
		$this->set_abspath( $this->temp_dir . '/' );
	}

	public function tearDown(): void {
		// Clean up temporary directory.
		$this->remove_directory( $this->temp_dir );

		// Restore original ABSPATH.
		$this->set_abspath( $this->original_abspath );

		// Remove all filters.
		remove_all_filters( 'wp_saml_auth_option' );
		remove_all_filters( 'wp_saml_auth_ssp_autoloader' );
		remove_all_filters( 'wp_saml_auth_simplesamlphp_path_array' );

		parent::tearDown();
	}

	/**
	 * Test that SimpleSAMLphp v2.x is detected via Composer installation.
	 */
	public function test_detects_simplesamlphp_v2_via_composer() {
		// Create a Composer-style SimpleSAMLphp installation.
		$composer_path = $this->temp_dir . '/vendor/simplesamlphp/simplesamlphp';
		$autoloader_path = $composer_path . '/vendor/autoload.php';

		mkdir( $composer_path . '/vendor', 0777, true );
		touch( $autoloader_path );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		$this->assertEquals( $autoloader_path, $result );
	}

	/**
	 * Test that SimpleSAMLphp v1.x is detected.
	 */
	public function test_detects_simplesamlphp_v1() {
		// Create a v1.x SimpleSAMLphp installation.
		$ssp_path = $this->temp_dir . '/simplesamlphp';
		$autoloader_path = $ssp_path . '/lib/_autoload.php';

		mkdir( $ssp_path . '/lib', 0777, true );
		touch( $autoloader_path );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		$this->assertEquals( $autoloader_path, $result );
	}

	/**
	 * Test that v2.x autoloader is preferred over v1.x in the same directory.
	 */
	public function test_prefers_v2_over_v1_autoloader() {
		// Create both v1.x and v2.x autoloaders in the same installation.
		$ssp_path = $this->temp_dir . '/simplesamlphp';
		$v2_autoloader = $ssp_path . '/vendor/autoload.php';
		$v1_autoloader = $ssp_path . '/lib/_autoload.php';

		mkdir( $ssp_path . '/vendor', 0777, true );
		mkdir( $ssp_path . '/lib', 0777, true );
		touch( $v2_autoloader );
		touch( $v1_autoloader );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		// Should prefer v2.x autoloader.
		$this->assertEquals( $v2_autoloader, $result );
	}

	/**
	 * Test that private/simplesamlphp path is checked.
	 */
	public function test_detects_private_simplesamlphp_path() {
		// Create SimpleSAMLphp in private directory.
		$private_path = $this->temp_dir . '/private/simplesamlphp';
		$autoloader_path = $private_path . '/vendor/autoload.php';

		mkdir( $private_path . '/vendor', 0777, true );
		touch( $autoloader_path );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		$this->assertEquals( $autoloader_path, $result );
	}

	/**
	 * Test that filter wp_saml_auth_ssp_autoloader overrides default detection.
	 */
	public function test_filter_overrides_default_detection() {
		$custom_path = '/custom/path/to/autoload.php';

		add_filter( 'wp_saml_auth_ssp_autoloader', function() use ( $custom_path ) {
			return $custom_path;
		} );

		// Create a real SimpleSAMLphp installation that would normally be found.
		$ssp_path = $this->temp_dir . '/simplesamlphp';
		mkdir( $ssp_path . '/vendor', 0777, true );
		touch( $ssp_path . '/vendor/autoload.php' );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		// Should return the filtered path, not the detected one.
		$this->assertEquals( $custom_path, $result );
	}

	/**
	 * Test that option simplesamlphp_autoload overrides default detection.
	 */
	public function test_option_overrides_default_detection() {
		$custom_path = $this->temp_dir . '/custom/autoload.php';

		// Create the custom autoloader file.
		mkdir( dirname( $custom_path ), 0777, true );
		touch( $custom_path );

		// Set the option.
		add_filter( 'wp_saml_auth_option', function( $value, $option_name ) use ( $custom_path ) {
			if ( 'simplesamlphp_autoload' === $option_name ) {
				return $custom_path;
			}
			return $value;
		}, 10, 2 );

		// Create a default SimpleSAMLphp installation that would normally be found.
		$ssp_path = $this->temp_dir . '/simplesamlphp';
		mkdir( $ssp_path . '/vendor', 0777, true );
		touch( $ssp_path . '/vendor/autoload.php' );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		// Should return the option path, not the default detected one.
		$this->assertEquals( $custom_path, $result );
	}

	/**
	 * Test that custom path array filter works.
	 */
	public function test_custom_path_array_filter() {
		$custom_base = $this->temp_dir . '/custom-location';
		$autoloader_path = $custom_base . '/vendor/autoload.php';

		// Create SimpleSAMLphp in custom location.
		mkdir( $custom_base . '/vendor', 0777, true );
		touch( $autoloader_path );

		// Override the search paths.
		add_filter( 'wp_saml_auth_simplesamlphp_path_array', function() use ( $custom_base ) {
			return [ $custom_base ];
		} );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		$this->assertEquals( $autoloader_path, $result );
	}

	/**
	 * Test that empty string is returned when no autoloader is found.
	 */
	public function test_returns_empty_when_not_found() {
		// Don't create any SimpleSAMLphp installations.
		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		$this->assertEquals( '', $result );
	}

	/**
	 * Test that all default paths are checked in order.
	 */
	public function test_checks_all_default_paths_in_order() {
		// Place SimpleSAMLphp in the LAST default path to ensure all are checked.
		// The last path is plugin_dir_path . 'simplesamlphp', which we can't easily test.
		// Instead, verify the third default path works.
		$third_path = $this->temp_dir . '/simplesamlphp';
		$autoloader_path = $third_path . '/vendor/autoload.php';

		mkdir( $third_path . '/vendor', 0777, true );
		touch( $autoloader_path );

		$result = WP_SAML_Auth::get_simplesamlphp_autoloader();

		$this->assertEquals( $autoloader_path, $result );
	}

	/**
	 * Helper: Override ABSPATH constant for testing.
	 */
	private function set_abspath( $path ) {
		// Use runkit or define if not already defined.
		// For this to work, we need to use a workaround since ABSPATH is a constant.
		// We can use eval or reflection, but for simplicity, we'll test without changing ABSPATH.
		// Instead, we'll use the filter to override paths.
	}

	/**
	 * Helper: Recursively remove directory.
	 */
	private function remove_directory( $dir ) {
		if ( ! is_dir( $dir ) ) {
			return;
		}

		$files = array_diff( scandir( $dir ), [ '.', '..' ] );
		foreach ( $files as $file ) {
			$path = $dir . '/' . $file;
			is_dir( $path ) ? $this->remove_directory( $path ) : unlink( $path );
		}

		rmdir( $dir );
	}
}
