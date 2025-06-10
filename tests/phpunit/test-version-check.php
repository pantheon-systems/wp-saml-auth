<?php
/**
 * Test SimpleSAMLphp version checking functionality
 *
 * @package WP_SAML_Auth
 */

/**
 * Class WP_SAML_Auth_Version_Check_Test
 */
class WP_SAML_Auth_Version_Check_Test extends WP_UnitTestCase {

	/**
	 * Test the check_simplesamlphp_version method
	 */
	public function test_check_simplesamlphp_version() {
		$wp_saml_auth = WP_SAML_Auth::get_instance();

		// Test critical version
		$this->assertEquals('critical', $wp_saml_auth->check_simplesamlphp_version('1.19.0'));
		
		// Test warning version
		$this->assertEquals('warning', $wp_saml_auth->check_simplesamlphp_version('2.0.0'));
		$this->assertEquals('warning', $wp_saml_auth->check_simplesamlphp_version('2.3.6'));
		
		// Test ok version
		$this->assertEquals('ok', $wp_saml_auth->check_simplesamlphp_version('2.3.7'));
		$this->assertEquals('ok', $wp_saml_auth->check_simplesamlphp_version('2.4.0'));
		
		// Test unknown version
		$this->assertEquals('unknown', $wp_saml_auth->check_simplesamlphp_version(false));
		$this->assertEquals('unknown', $wp_saml_auth->check_simplesamlphp_version(''));
	}

	/**
	 * Test the authentication blocking for vulnerable versions
	 */
	public function test_authentication_blocking() {
		$wp_saml_auth = WP_SAML_Auth::get_instance();
		
		// Mock the get_simplesamlphp_version method to return a vulnerable version
		$mock_wp_saml_auth = $this->getMockBuilder('WP_SAML_Auth')
			->setMethods(['get_simplesamlphp_version', 'get_provider'])
			->getMock();
		
		$mock_wp_saml_auth->method('get_simplesamlphp_version')
			->willReturn('1.19.0');
		
		$mock_wp_saml_auth->method('get_provider')
			->willReturn(null);
		
		// Set connection type to simplesamlphp and enforce_min_simplesamlphp_version to true
		add_filter('wp_saml_auth_option', function($value, $option_name) {
			if ('connection_type' === $option_name) {
				return 'simplesamlphp';
			}
			if ('enforce_min_simplesamlphp_version' === $option_name) {
				return true;
			}
			if ('critical_simplesamlphp_version' === $option_name) {
				return '2.0.0';
			}
			return $value;
		}, 10, 2);
		
		// Test authentication is blocked for vulnerable version
		$result = $mock_wp_saml_auth->do_saml_authentication();
		$this->assertInstanceOf('WP_Error', $result);
		$this->assertEquals('wp_saml_auth_vulnerable_simplesamlphp', $result->get_error_code());
		
		// Remove the filter
		remove_all_filters('wp_saml_auth_option');
	}

	/**
	 * Test the authentication is allowed for secure versions
	 */
	public function test_authentication_allowed() {
		// Mock the WP_SAML_Auth class
		$mock_wp_saml_auth = $this->getMockBuilder('WP_SAML_Auth')
			->setMethods(['get_simplesamlphp_version', 'get_provider'])
			->getMock();
		
		$mock_wp_saml_auth->method('get_simplesamlphp_version')
			->willReturn('2.3.7');
		
		$mock_wp_saml_auth->method('get_provider')
			->willReturn(null);
		
		// Set connection type to simplesamlphp and enforce_min_simplesamlphp_version to true
		add_filter('wp_saml_auth_option', function($value, $option_name) {
			if ('connection_type' === $option_name) {
				return 'simplesamlphp';
			}
			if ('enforce_min_simplesamlphp_version' === $option_name) {
				return true;
			}
			if ('min_simplesamlphp_version' === $option_name) {
				return '2.3.7';
			}
			return $value;
		}, 10, 2);
		
		// Test authentication proceeds for secure version
		// Since we're mocking get_provider to return null, we'll get a WP_Error with a different error code
		$result = $mock_wp_saml_auth->do_saml_authentication();
		$this->assertInstanceOf('WP_Error', $result);
		$this->assertEquals('wp_saml_auth_invalid_provider', $result->get_error_code());
		
		// Remove the filter
		remove_all_filters('wp_saml_auth_option');
	}
}
