<?php
namespace SimpleSAML\Auth;

class Simple {
	private $authed = false; // default: NOT authenticated
	private $attrs;

	public function __construct($sp) {
		$this->attrs = [
			'uid'         => ['testuser'],
			'mail'        => ['testuser@example.com'],
			'givenName'   => ['Test'],
			'sn'          => ['User'],
			'displayName' => ['Test User'],
		];
		if ($env = getenv('WPSA_TEST_SAML_ATTRS')) {
			$json = json_decode($env, true);
			if (is_array($json)) {
				foreach ($json as $k => $v) {
					$this->attrs[$k] = is_array($v) ? array_values($v) : [$v];
				}
			}
		}
		$forced = getenv('WPSA_TEST_SAML_AUTHED');
		if ($forced !== false) $this->authed = (bool)(int)$forced;
	}

	public function requireAuth(): void {
		$forced = getenv('WPSA_TEST_SAML_AUTHED');
		$this->authed = ($forced !== false) ? (bool)(int)$forced : true;
	}

	public function isAuthenticated(): bool { return $this->authed; }
	public function getAttributes(): array { return $this->attrs; }
	public function logout($params = []) { $this->authed = false; return true; }
}
