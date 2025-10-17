<?php
namespace SimpleSAML\Auth;

/**
 * Very small stub of SimpleSAML\Auth\Simple for unit tests.
 * Methods implemented as no-ops unless a test overrides behavior via globals.
 */
class Simple {
    /** @var string */
    protected $source;

    /** @var array<string,mixed> */
    protected static $attributes = [
        'uid'                     => ['student'],
        'mail'                    => ['student@example.org'],
        'eduPersonAffiliation'    => ['student'],
    ];

    /** @var bool */
    protected static $authenticated = false;

    public function __construct($source) {
        $this->source = $source;
    }

    /** Allow tests to programmatically set attributes/auth state. */
    public static function __setAttributes(array $attrs): void {
        self::$attributes = $attrs;
    }
    public static function __setAuthenticated(bool $yes): void {
        self::$authenticated = $yes;
    }

    public function isAuthenticated(): bool {
        return self::$authenticated;
    }

    public function requireAuth(array $params = []): void {
        // In a browser this would redirect; in tests we just force "logged-in".
        self::$authenticated = true;
    }

    public function login(array $params = []): void {
        self::$authenticated = true;
    }

    public function logout(array $params = []): void {
        self::$authenticated = false;
    }

    /**
     * Return SAML attributes. Tests can override via __setAttributes().
     *
     * @return array<string,array<int,string>>
     */
    public function getAttributes(): array {
        return self::$attributes;
    }
}
