<?php
namespace SimpleSAML\Auth;

/**
 * Very small SimpleSAMLphp stub used by unit tests.
 * Defaults to "NOT authenticated".
 */
class Simple {
    private $authenticated = false; // <-- default unauthenticated

    /**
     * Default attributes (only used if a test authenticates and does not override).
     */
    private $attributes = [
        'uid'                  => ['student'],
        'mail'                 => ['test-student@example.com'],
        'eduPersonAffiliation' => ['student'],
    ];

    public function __construct( $source = null ) {
        // Allow tests to override via filters, but do NOT force a default here.
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

    /**
     * Simulate IdP auth requirement. For unit tests we only flip to true
     * when explicitly asked to (e.g., a test or filter says so).
     */
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

    /**
     * Only fire the logout hook if we are actually authenticated.
     * The logout test expects "no call" when not authenticated.
     */
    public function logout( array $params = [] ) {
        if ( $this->isAuthenticated() ) {
            \do_action( 'wp_saml_auth_test_logout_called', $params );
        }
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
