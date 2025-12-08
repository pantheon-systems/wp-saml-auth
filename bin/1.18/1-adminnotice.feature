Feature: Admin Notice for SimpleSAMLphp 1.18 Vulnerability
  In order to ensure administrators are aware of critical security issues
  As a site administrator
  I need to see an admin notice regarding the SimpleSAMLphp vulnerability

  Scenario: Admin user sees the SimpleSAMLphp vulnerability notice
    Given I log in as an admin
    Then I should be on "/wp-admin/"
    And my connection type is "simplesamlphp"
    And I should see "Security Alert:" in the "div.notice.notice-error[data-slug='wp-saml-auth'][data-type='simplesamlphp-critical-vulnerability']" element
    And I should see "The SimpleSAMLphp version used by the WP SAML Auth plugin (1.18.4) has a critical security vulnerability (CVE-2023-26881). Please update to version 2.0.0 or later. Learn more." in the "div.notice.notice-error[data-slug='wp-saml-auth'][data-type='simplesamlphp-critical-vulnerability'] p" element
    And I go to "/wp-admin/options-general.php"
    Then I should see "Security Alert:" in the "div.notice.notice-error[data-slug='wp-saml-auth'][data-type='simplesamlphp-critical-vulnerability']" element
    And I should see "The SimpleSAMLphp version used by the WP SAML Auth plugin (1.18.4) has a critical security vulnerability (CVE-2023-26881)" in the "div.notice.notice-error[data-slug='wp-saml-auth'] p" element
