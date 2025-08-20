Feature: Admin Notice for SimpleSAMLphp 2.0.0 Vulnerability
  In order to ensure administrators are aware of critical security issues
  As a site administrator
  I need to see an admin notice regarding the SimpleSAMLphp vulnerability

  Scenario: Admin user sees the SimpleSAMLphp vulnerability notice only for SimpleSAMLphp connection type
    Given I log in as an admin
    Then I should be on "/wp-admin/"
    And my connection type is "simplesaml"
    And I should see "Security Recommendation:" in the "div.notice.notice-warning[data-slug='wp-saml-auth'][data-type='simplesamlphp-version-warning']" element
    And I should see "The SimpleSAMLphp version used by the WP SAML Auth plugin (2.0.0) is older than the recommended secure version. Please consider updating to version 2.3.7 or later. Learn more." in the "div.notice.notice-warning[data-slug='wp-saml-auth'][data-type='simplesamlphp-version-warning'] p" element
    And I go to "/wp-admin/options-general.php"
    Then I should see "Security Recommendation:" in the "div.notice.notice-warning[data-slug='wp-saml-auth'][data-type='simplesamlphp-version-warning']" element
    And I should see "The SimpleSAMLphp version used by the WP SAML Auth plugin (2.0.0) is older than the recommended secure version" in the "div.notice.notice-warning[data-slug='wp-saml-auth'] p" element
