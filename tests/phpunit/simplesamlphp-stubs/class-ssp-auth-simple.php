<?php
namespace SimpleSAML\Auth;

/**
 * Tiny SimpleSAMLphp stub for unit tests.
 * - Implements requireAuth() used by the plugin.
 * - Always "authenticated" unless a test manipulates via filters.
 * - Attributes come from 'wp_saml_auth_attributes' (with a safe baseline).
 * - logout() just flags that it was called; plugin logic should check the option.
 */
class Simple {
    public static $last_instance = null;
    public static $logout_called = false;

    private $idp;
    private $authenticated = true;

    public function __construct($idp = null) {
        $this->idp = $idp;
        self::$last_instance = $this;
    }

    public function isAuthenticated() {
        return $this->authenticated;
    }

    public function requireAuth(array $params = []) {
        // In real SSP this would redirect. Here, just mark as authenticated.
        $this->authenticated = true;
    }

    public function login(array $params = []) {
        $this->authenticated = true;
    }

    public function logout(array $params = []) {
        // The plugin should check the 'allow_slo' option before calling us.
        // If it does call us, record that it happened so tests can assert.
        self::$logout_called = true;
    }

    public function getAttributes() {
        $attrs = [
            'uid'                  => ['student'],
            'mail'                 => ['student@example.org'],
            'eduPersonAffiliation' => ['student'],
        ];

        if (function_exists('apply_filters')) {
            $maybe = apply_filters('wp_saml_auth_attributes', $attrs);
            if (is_array($maybe) && !empty($maybe)) {
                $attrs = $maybe;
            }
        }
        return $attrs;
    }
}
