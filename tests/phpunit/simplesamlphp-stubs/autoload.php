<?php
namespace SimpleSAML\Auth;

class Simple {
	private $authenticated = true; // <-- default: authenticated

	/**
	 * Default attributes match tests expecting a 'student' user.
	 */
	private $attributes = [
		'uid'                  => ['student'],
		'mail'                 => ['test-student@example.com'],
		'eduPersonAffiliation' => ['student'],
	];

	public function __construct( $source = null ) {
		// Allow tests to override via filter; default true otherwise.
		$auth = \apply_filters( 'wp_saml_auth_test_is_authenticated', null );
		if ( $auth !== null ) {
			$this->authenticated = (bool) $auth;
		}
		$attrs = \apply_filters( 'wp_saml_auth_test_attributes', null );
		if ( \is_array( $attrs ) ) {
			$this->attributes = $this->normalize_attributes( $attrs );
		}
	}

	public function isAuthenticated() {
		$maybe = \apply_filters( 'wp_saml_auth_test_is_authenticated', null );
		return $maybe !== null ? (bool) $maybe : $this->authenticated;
	}

	public function requireAuth( array $params = [] ) {
		$this->authenticated = true;
	}

	public function getAttributes() {
		$maybe = \apply_filters( 'wp_saml_auth_test_attributes', null );
		if ( \is_array( $maybe ) ) {
			return $this->normalize_attributes( $maybe );
		}
		return $this->attributes;
	}

	public function logout( array $params = [] ) {
		\do_action( 'wp_saml_auth_test_logout_called', $params );
		return null;
	}

	private function normalize_attributes( $attrs ) {
		$out = [];
		foreach ( $attrs as $k => $v ) {
			$out[ $k ] = \is_array( $v ) ? array_values( $v ) : [ (string) $v ];
		}
		return $out;
	}
}
