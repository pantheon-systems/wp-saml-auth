Feature: SAML Login (SimpleSAMLphp 1.18.0)
  In order to verify SimpleSAMLphp 1.18.0 basic authentication works
  As a maintainer
  I need to test basic login functionality

  Scenario: Basic login with employee credentials
    Given I am on "wp-login.php"
    Then print current URL
    And I fill in "username" with "employee"
    And I fill in "password" with "employeepass"
    And I press "submit"
    Then I follow the SAML redirect manually
    Then print current URL
    Then the "email" field should contain "test-em@example.com"
