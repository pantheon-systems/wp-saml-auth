Feature: Admin Notice for SimpleSAMLphp 1.18.0 Vulnerability
  In order to ensure administrators are aware of critical security issues
  As a site administrator
  I need to see a critical security alert regarding SimpleSAMLphp 1.18.0

  Scenario: Admin user sees the SimpleSAMLphp 1.18.0 critical vulnerability notice
    Given I log in as an admin
    Then I should be on "/wp-admin/"
    And my connection type is "simplesamlphp"
    And I should see "Security Alert:" in the "div.notice.notice-error[data-slug='wp-saml-auth'][data-type='simplesamlphp-critical-vulnerability']" element
    And I should see "The SimpleSAMLphp version used by the WP SAML Auth plugin (1.18.0) has a critical security vulnerability (CVE-2023-26881)" in the "div.notice.notice-error[data-slug='wp-saml-auth'][data-type='simplesamlphp-critical-vulnerability'] p" element
