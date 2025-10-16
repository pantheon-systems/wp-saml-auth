<?php
/**
 * Minimal SimpleSAMLphp mock used by the test suite.
 * Loaded via auto_prepend_file from bin/phpunit-bootstrap.sh.
 */

namespace SimpleSAML\Auth;

class Simple {
    /** @var bool */
    private $authed = false;

    /** @var array<string,array<int,string>> */
    private $attributes = [];

    /** @var string|null */
    private $idp;

    /**
     * @param string|null $source
     */
    public function __construct($source = null) {
        $this->idp = $source ?: 'mock-idp';
        // sensible defaults used by tests
        $this->attributes = [
            'uid'         => ['sam.user'],
            'mail'        => ['sam.user@example.com'],
            'givenName'   => ['Sam'],
            'sn'          => ['User'],
            'displayName' => ['Sam User'],
            'eduPersonAffiliation' => ['member'],
        ];
    }

    public function isAuthenticated() {
        return $this->authed;
    }

    public function requireAuth(array $params = []) {
        $this->authed = true;
        return true;
    }

    public function login(array $params = []) {
        $this->authed = true;
        return true;
    }

    public function logout($returnTo = null) {
        $this->authed = false;
        return true;
    }

    /** @return array<string,array<int,string>> */
    public function getAttributes() {
        return $this->attributes;
    }

    /** Allow tests to override attributes easily */
    public function setAttributes(array $attrs) {
        $this->attributes = $attrs;
    }

    public function getAuthData($key) {
        if ($key === 'saml:sp:IdP') {
            return $this->idp;
        }
        return null;
    }
}
