# Contributing

The best way to contribute to the development of this plugin is by participating on the GitHub project:

https://github.com/pantheon-systems/wp-saml-auth

Pull requests and issues are welcome!

You may notice there are two sets of tests running, on two different services:

* Travis CI runs the [PHPUnit](https://phpunit.de/) test suite, which mocks interactions with SimpleSAMLphp.
* Circle CI runs the [Behat](http://behat.org/) test suite against a Pantheon site, to ensure the plugin's compatibility with the Pantheon platform. This includes configuring a fully-functional instance of SimpleSAMLphp.

Both of these test suites can be run locally, with a varying amount of setup.

PHPUnit requires the [WordPress PHPUnit test suite](https://make.wordpress.org/core/handbook/testing/automated-testing/phpunit/), and access to a database with name `wordpress_test`. If you haven't already configured the test suite locally, you can run `bash bin/install-wp-tests.sh wordpress_test root '' localhost`.

Behat requires a Pantheon site. Once you've created the site, you'll need [install Terminus](https://github.com/pantheon-systems/terminus#installation), and set the `TERMINUS_TOKEN`, `TERMINUS_SITE`, and `TERMINUS_ENV` environment variables. Then, you can run `./bin/behat-prepare.sh` to prepare the site for the test suite.

## Release Process

1. Update plugin version in `package.json`, `README.md`, `readme.txt`, and `wp-saml-auth.php`.
2. Update the Changelog with the latest changes.
3. Create a PR against the `master` branch.
4. After all tests pass and you have received approval from a CODEOWNER (including resolving any merge conflicts), merge the PR into `master`.
5. Wait for CI to build and push a new tag.
6. Confirm that the necessary assets are present in the newly created tag, and test on a WP install if desired.
7. Publish a new release using the latest tag. Publishing a release will kick off `wordpress-plugin-deploy.yml` and release the plugin to wp.org. If you do not want a tag to be publised to wp.org, do not publish a release from it.