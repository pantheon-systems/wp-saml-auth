<?php
/**
 * SimpleSAMLphp stub for PHPUnit tests.
 *
 * This stub provides a mock SimpleSAML_Auth_Simple class for testing
 * without requiring the full SimpleSAMLphp library.
 */
class SimpleSAML_Auth_Simple {
	// Start unauthenticated – tests expect false before SAML login and after logout.
	private $authed = false;
	private $attrs;

	/**
	 * Constructor.
	 *
	 * @param string $sp Service provider identifier. Unused but present to match SimpleSAMLphp API signature.
	 */
	public function __construct($sp) {
		// Default attributes as a fallback.
		$this->attrs = [
			'uid'         => ['testuser'],
			'mail'        => ['testuser@example.com'],
			'givenName'   => ['Test'],
			'sn'          => ['User'],
			'displayName' => ['Test User'],
		];

		// Prefer the test's "current SAML user" if provided.
		if (isset($GLOBALS['wp_saml_auth_current_user']) && is_array($GLOBALS['wp_saml_auth_current_user'])) {
			$this->attrs = $GLOBALS['wp_saml_auth_current_user'];
		}

		// Optional env-based attribute override.
		if ($json = getenv('WPSA_TEST_SAML_ATTRS')) {
			$decoded = json_decode($json, true);
			if (is_array($decoded)) {
				$this->attrs = array_map(
					fn($v) => is_array($v) ? array_values($v) : [$v],
					$decoded
				);
			}
		}

		// Optional explicit auth override.
		if (($forced = getenv('WPSA_TEST_SAML_AUTHED')) !== false) {
			$this->authed = (bool)(int)$forced;
		}
	}

	public function requireAuth(): void {
		// When the plugin forces SAML login, mark as authenticated and
		// refresh attributes from the test global if present.
		if (isset($GLOBALS['wp_saml_auth_current_user']) && is_array($GLOBALS['wp_saml_auth_current_user'])) {
			$this->attrs = $GLOBALS['wp_saml_auth_current_user'];
		}

		$this->authed = true;

		// Env override wins if explicitly set.
		if (($forced = getenv('WPSA_TEST_SAML_AUTHED')) !== false) {
			$this->authed = (bool)(int)$forced;
		}
	}

	public function isAuthenticated(): bool {
		return $this->authed;
	}

	public function getAttributes(): array {
		return $this->attrs;
	}

	/**
	 * Logs out the user.
	 *
	 * @param array $params Unused. Present to match the SimpleSAMLphp API signature.
	 * @return bool Always returns true.
	 */
	public function logout($params = []) {
		$this->authed = false;
		return true;
	}
}
