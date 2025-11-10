<?php
namespace SimpleSAML\Auth;

class Simple {
	/** @var bool */
	private $authed = false; // default: NOT authenticated (matches your tests)
	/** @var array<string,array<int,string>> */
	private $attrs;

	public function __construct($sp) {
		$this->attrs = [
			'uid'         => ['testuser'],
			'mail'        => ['testuser@example.com'],
			'givenName'   => ['Test'],
			'sn'          => ['User'],
			'displayName' => ['Test User'],
		];

		// Optional per-test overrides via env
		$envAttrs = getenv('WPSA_TEST_SAML_ATTRS');
		if ($envAttrs) {
			$json = json_decode($envAttrs, true);
			if (is_array($json)) {
				foreach ($json as $k => $v) {
					$this->attrs[$k] = is_array($v) ? array_values($v) : [$v];
				}
			}
		}

		$forced = getenv('WPSA_TEST_SAML_AUTHED');
		if ($forced !== false) {
			$this->authed = (bool)(int)$forced;
		}
	}

	/** Simulate SSO flow: flip to authed=true unless forced via env */
	public function requireAuth(): void {
		$forced = getenv('WPSA_TEST_SAML_AUTHED');
		$this->authed = ($forced !== false) ? (bool)(int)$forced : true;
	}

	public function isAuthenticated(): bool {
		return $this->authed;
	}

	/** @return array<string, array<int, string>> */
	public function getAttributes(): array {
		return $this->attrs;
	}

	public function logout($params = []) {
		$this->authed = false;
		return true;
	}
}
