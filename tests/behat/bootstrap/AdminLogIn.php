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
     * @Given my connection type is :arg1
     */
	public function myConnectionTypeIs($arg1)
	 {
	 	// checks the connection type for adminNotice behat test
	 	global $connection_type;
	 	$connection_type = $arg1;
	 }

	/**
	 * @Then I follow the SAML redirect manually
	 */
	public function followSamlRedirectManually() {
		$session = $this->minkContext->getSession();
		$html = $session->getPage()->getContent();

		$this->minkContext->printLastResponse(); // Optional debugging

		// Meta refresh
		if (preg_match('/<meta http-equiv="refresh" content="\d+;url=([^"]+)"/i', $html, $matches)) {
			$this->minkContext->visit(html_entity_decode($matches[1]));
			return;
		}

		// JS redirect
		if (preg_match('/window\.location\s*=\s*"([^"]+)"/i', $html, $matches)) {
			$this->minkContext->visit(html_entity_decode($matches[1]));
			return;
		}

		// DOM parsing
		$crawler = new Crawler($html);
		$form = $crawler->filter('form')->first();

		if (!$form->count()) {
			throw new \Exception('No form found to submit SAML response.');
		}

		$action = $form->attr('action');
		$inputs = $form->filter('input');

		$formFields = [];
		foreach ($inputs as $input) {
			$name = $input->getAttribute('name');
			$value = $input->getAttribute('value') ?? '';
			if ($name) {
				$formFields[$name] = $value;
			}
		}

		// Submit using Goutte client
		$client = $session->getDriver()->getClient();
		$client->request('POST', $action, $formFields);
	}
	
}
