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

		$this->minkContext->printLastResponse(); // for debugging

		// Try meta refresh
		if (preg_match('/<meta http-equiv="refresh" content="\d+;url=([^"]+)"/i', $html, $matches)) {
			$this->minkContext->visit(html_entity_decode($matches[1]));
			return;
		}

		// Try JS redirect
		if (preg_match('/window\.location\s*=\s*"([^"]+)"/i', $html, $matches)) {
			$this->minkContext->visit(html_entity_decode($matches[1]));
			return;
		}

		// Try submitting the login form manually
		$crawler = new Crawler($html);
		$form = $crawler->filter('form[name="f"]');

		if ($form->count() > 0) {
			$action = $form->attr('action');

			$formData = [
				'username' => getenv('WORDPRESS_ADMIN_USERNAME'),
				'password' => getenv('WORDPRESS_ADMIN_PASSWORD'),
			];

			// Submit the form manually using the Goutte driver
			$client = $session->getDriver()->getClient();
			$client->request('POST', $action, $formData);
			return;
		}

		throw new \Exception('No meta refresh, JS redirect, or login form found in response');
	}

}
