<?php
require_once 'modules/Users/authentication/GOAuthAuthenticate/GOAuthAuthenticateUser.php';
require_once 'include/google-api-php-client/src/Google_Client.php';
require_once 'include/google-api-php-client/src/contrib/Google_Oauth2Service.php';

class ViewGOAuth extends SugarView
{
	public function __construct()
	{
		parent::SugarView();
	}
	
	public function display()
	{
		$auth = new GOAuthAuthenticateUser();

		if (isset($_REQUEST['logout'])) {	// this is part of template code and should be remove.  Logic should be moved to standard CRM logout routings
			$auth->logout();
			return;
		}

		if (isset($_GET['code'])) {		//  This is the return from the google page and setting the appropriate session within this sites context
			  if(!isset($_SESSION['goauth_token'])){		//for testing, if authenticate is called a second time with the same "code" it will fail
				  $auth->client->authenticate($_GET['code']);
			  }
			$_SESSION['goauth_token'] = $auth->client->getAccessToken();
			$redirect = 'http://' . $_SERVER['HTTP_HOST'] . $_SERVER['PHP_SELF'] . "?module=Users&action=GoAuth";
			SugarApplication::redirect(filter_var($redirect, FILTER_SANITIZE_URL));
			return;
		}

		if (isset($_SESSION['goauth_token'])) {		//  Previously google authorized.  Set google objects
			$auth->client->setAccessToken($_SESSION['goauth_token']);
		}


		if ($auth->client->getAccessToken()) { // this is logged in with Google
			if ($auth->loginAuthenticate2()) {	// check Authentication and set CRM Login Session
				$_SESSION['goauth_token'] = $auth->client->getAccessToken();
				$redirect = 'http://' . $_SERVER['HTTP_HOST'] . $_SERVER['PHP_SELF'];	
				SugarApplication::redirect(filter_var($redirect, FILTER_SANITIZE_URL));	//  Logged in.  Now lets go to the default page - index.php
				return;
			} else {
				//  Google oAuth is good but login error with CRM.  - Check $_SESSION['login_error']
				return;
			}
		} else {	// This is the redirection to the Google Login page
			SugarApplication::redirect(filter_var($auth->client->createAuthUrl(), FILTER_SANITIZE_URL));
			return;
		}
	}
}