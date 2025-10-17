<?php
/**
 * Minimal SimpleSAMLphp stubs for unit tests.
 * These cover only the methods our tests exercise.
 */

namespace SimpleSAML\Auth;

class Simple {
    private static $authed = false;
    private $sp;
    public function __construct($sp) { $this->sp = $sp; }
    public static function reset() { self::$authed = false; }
    public function isAuthenticated() { return self::$authed; }
    public function requireAuth(array $params = []) { self::$authed = true; }
    public function logout($returnTo = null) { self::$authed = false; }
    public function getAttributes() {
        // Attributes used by tests (mapping, role, etc.)
        return [
            'uid'                   => ['employee'],
            'mail'                  => ['test-em@example.com'],
            'eduPersonAffiliation'  => ['employee'],
        ];
    }
}

// Optional: very light stubs that some codepaths may touch.
namespace SimpleSAML;
class Configuration {
    public static function getInstance() { return new self(); }
}
namespace SimpleSAML\Utils;
class HTTP {
    public static function redirectTrustedURL($url) { /* no-op in unit tests */ }
}
