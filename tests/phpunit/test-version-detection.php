<?php
/**
 * Integration tests for SimpleSAMLphp version detection and autoloader resolution
 *
 * @package WP_SAML_Auth
 */

/**
 * Class Test_Integration_Version_Detection
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
