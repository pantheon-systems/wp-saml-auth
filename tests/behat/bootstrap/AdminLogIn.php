<?php

namespace PantheonSystems\WPSamlAuth\Behat;

use Behat\Behat\Context\Context;
use Behat\Behat\Context\SnippetAcceptingContext;
use Symfony\Component\DomCrawler\Crawler;
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
	public function followSamlRedirectManually() {
		$session = $this->minkContext->getSession();
		$html = $session->getPage()->getContent();

		// Print response for debugging
		$this->minkContext->printLastResponse();

		// Step 1: Meta refresh
		if (preg_match('/<meta http-equiv="refresh" content="\d+;url=([^"]+)"/i', $html, $matches)) {
			$this->minkContext->visit(html_entity_decode($matches[1]));
			return;
		}

		// Step 2: JS redirect
		if (preg_match('/window\.location\s*=\s*"([^"]+)"/i', $html, $matches)) {
			$this->minkContext->visit(html_entity_decode($matches[1]));
			return;
		}

		// Step 3: SAML form postback
		if (preg_match('/<form[^>]+action="([^"]+saml_acs[^"]*)"[^>]*method="post"[^>]*>.*?<\/form>/is', $html, $formMatch)) {
			$actionUrl = html_entity_decode($formMatch[1]);

			// ✅ Updated regex to capture *all* inputs, not just hidden
			preg_match_all('/<input[^>]+name="([^"]+)"[^>]*value="([^"]*)"?/i', $html, $inputs, PREG_SET_ORDER);

			$formFields = [];
			foreach ($inputs as $input) {
				$formFields[$input[1]] = html_entity_decode($input[2]);
			}

			$client = $session->getDriver()->getClient();
			$client->request('POST', $actionUrl, $formFields);
			return;
		}

		throw new \Exception('No meta refresh, JS redirect, or SAML post-back form found in response');
	}

}
