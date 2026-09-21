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
	Then I follow the SAML redirect manually
    Then print current URL
    Then the "email" field should contain "test-em@example.com"

  Scenario: Redirects between WordPress and SAML student
    Given I am on "wp-login.php"
    Then print current URL
    And I fill in "username" with "student"
    And I fill in "password" with "studentpass"
    And I press "submit"
	Then I follow the SAML redirect manually
    Then print current URL
    Then the "email" field should contain "test-student@example.com"

  Scenario: Errors on an invalidpassword
    Given I am on "wp-login.php"
    Then print current URL
    And I fill in "username" with "student"
    And I fill in "password" with "invalidpass"
    And I press "submit"
    Then print current URL
    And I should see "Incorrect username or password"

  # SITE-6023: provision the victim via SAML so a real WordPress user exists
  # with the unaccented email (collationvictim@example.com). This runs in the
  # default suite (after the upstream core suite), so it does not perturb the
  # core tests' assumption of a clean user list.
  Scenario: A victim provisions via SAML
    Given I am on "wp-login.php"
    Then print current URL
    And I fill in "username" with "collationvictim"
    And I fill in "password" with "collationvictimpass"
    And I press "submit"
    Then I follow the SAML redirect manually
    Then print current URL
    And the "email" field should contain "collationvictim@example.com"

  # SITE-6023: the collationattacker IdP account asserts an accented variant
  # (collátionvictim@example.com) of the victim's email
  # (collationvictim@example.com) provisioned above. An accent-insensitive DB
  # collation makes get_user_by() return the victim, so without the fix the
  # attacker would be authenticated as the victim. The plugin must reject the
  # near-match instead.
  Scenario: Rejects a SAML login whose email only matches by collation
    Given I am on "wp-login.php"
    Then print current URL
    And I fill in "username" with "collationattacker"
    And I fill in "password" with "collationattackerpass"
    And I press "submit"
    Then I follow the SAML redirect manually
    Then print current URL
    And I should see "SAML attribute does not exactly match the existing user"
