Feature: SAML Login
  In order to verify SimpleSAMLphp interacts with WordPress
  As a maintainer
  I need to use the examplepass provided by SimpleSAMLphp

  Scenario: Redirects between WordPress and SAML
    Given I am on "wp-login.php"
    Then print current URL
    And I fill in "username" with "employee"
    And I fill in "password" with "employeepass"
    And I press "submit"
    Then print current URL
    Then the "email" field should contain "test-em@example.com"

  Scenario: Redirects between WordPress and SAML student
    Given I am on "wp-login.php"
    Then print current URL
    And I fill in "username" with "student"
    And I fill in "password" with "studentpass"
    And I press "submit"
    Then print current URL
    Then the "email" field should contain "test-student@example.com"
