<?php

namespace PantheonSystems\WPSamlAuth\Behat;

use Behat\Behat\Context\Context;
use Behat\Behat\Context\SnippetAcceptingContext;
use Behat\MinkExtension\Context\MinkContext;
use Behat\Behat\Hook\Scope\BeforeScenarioScope;

/**
 * This class replaces PantheonSystems\PantheonWordPressUpstreamTests\Behat\AdminLogIn
 * However it does not actually extend it so as to avoid unecessary coupling.
 */
class AdminLogIn implements Context, SnippetAcceptingContext {

    /** @var \Behat\MinkExtension\Context\MinkContext */
    private $minkContext;

    /** @BeforeScenario */
    public function gatherContexts(BeforeScenarioScope $scope)
    {
        $environment = $scope->getEnvironment();
        $this->minkContext = $environment->getContext('Behat\MinkExtension\Context\MinkContext');
    }

    /**
     * @Given I log in as an admin
     */
    public function ILogInAsAnAdmin()
    {
        $this->minkContext->visit('wp-login.php');
        $this->minkContext->fillField('username', getenv('WORDPRESS_ADMIN_USERNAME'));
        $this->minkContext->fillField('password', getenv('WORDPRESS_ADMIN_PASSWORD'));
        $this->minkContext->pressButton('submit');

		// Follow any meta or JS-based redirect manually
    	$this->followSamlRedirectManually();

        $this->minkContext->assertPageAddress("wp-admin/");
    }

	/**
	 * @Then I follow the SAML redirect manually
	 */
	public function followSamlRedirectManually()
	{
		$html = $this->minkContext->getSession()->getPage()->getContent();

		if (preg_match('/<meta http-equiv="refresh" content="\d+;url=([^"]+)"/i', $html, $matches)) {
			$redirectUrl = html_entity_decode($matches[1]);
			$this->minkContext->visit($redirectUrl);
		} elseif (preg_match('/window\.location\s*=\s*"([^"]+)"/i', $html, $matches)) {
			// Handle JS-based redirects in <script>
			$redirectUrl = html_entity_decode($matches[1]);
			$this->minkContext->visit($redirectUrl);
		} else {
			throw new \Exception('No meta refresh or window.location redirect found in response');
		}
	}

}
