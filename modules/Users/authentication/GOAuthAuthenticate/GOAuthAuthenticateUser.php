<?php
require_once('modules/Users/authentication/SugarAuthenticate/SugarAuthenticateUser.php');
require_once 'include/google-api-php-client/src/Google_Client.php';
require_once 'include/google-api-php-client/src/contrib/Google_Oauth2Service.php';

// To be included in the sugar config config.php file

//  'gplus' => 
//  array (
//      'client_id' => '',
//    'client_secret' => ''
//  ), 

//  The client_id and client_secret must be generated from https://console.developers.google.com.
// These values are specific for each install and include the domain

class GOAuthAuthenticateUser extends SugarAuthenticateUser
{
    public $client;	// Google client
    public $oauth2;	// Google oAuth client

    public function __construct()
    {
		if(isset($GLOBALS['sugar_config']['gplus']['client_id'])) {
			$this->client = new Google_Client();
			$this->client->setClientId($GLOBALS['sugar_config']['gplus']['client_id']);
			$this->client->setClientSecret($GLOBALS['sugar_config']['gplus']['client_secret']);
			$this->client->setRedirectUri($GLOBALS['sugar_config']['site_url']."/?module=Users&action=GoAuth");
			$this->client->setApprovalPrompt("auto");
			$this->client->setScopes(array('https://www.googleapis.com/auth/userinfo.email','https://www.googleapis.com/auth/userinfo.profile'));
			$this->oauth2 = new Google_Oauth2Service($this->client);
		}
    }


	public function logout()
	{
		unset($_SESSION['goauth_token']);
  		$this->client->revokeToken();
	}
   
		
	public function loginAuthenticate2()
    {
 		$goauth_user = $this->oauth2->userinfo->get();

        if (!empty($goauth_user))	// if user from Google cloud  is found
        {
            global $db;
            // auth info
            $auth_id = $goauth_user['id'];
            $auth_email = $goauth_user['email'];
			$auth_given_name = $goauth_user['given_name'];
			$auth_family_name = $goauth_user['family_name'];
			$auth_picture = $goauth_user['picture'];
			$auth_hd = $goauth_user['hd'];
			
            // get sugar user from google user
			
			//  User status of Active should also be included in this look up
            $row = $db->fetchByAssoc($db->query("SELECT * FROM users WHERE user_name = '{$auth_email}' AND authenticate_id = '{$auth_id}'"));
            if ($row && $row['id'] && $row['user_name'])
            {
				//  Set Session Variable for CRM Logged in status				
                $_SESSION['login_error'] = '';
                $_SESSION['waiting_error'] = '';
                $_SESSION['hasExpiredPassword'] = '0';
                $this->loadUserOnSession($row['id']);

                $user = new User();
                $user->retrieve($row['id']);
                $user->setPreference('loginfailed','0');
                $user->savePreferencesToDB();
                return true;
            }
            else  // if user exists with the same email address but doesn't have the google oauth id set for it yet.
			{
				//  User status of Active should also be included in this look up
			    $row = $db->fetchByAssoc($db->query("SELECT * FROM users WHERE user_name = '{$auth_email}'"));
				if ($row && $row['id'] && $row['user_name'])
				{
					//  Set Session Variable for CRM Logged in status
					$_SESSION['login_error'] = '';
					$_SESSION['waiting_error'] = '';
					$_SESSION['hasExpiredPassword'] = '0';
					$this->loadUserOnSession($row['id']);
	
					$user_hash = (md5($GLOBALS['GPlusConfigs']['token_hash_pwd'] . $auth_id));
	
					$user = new User();
					$user->retrieve($row['id']);

					// First time logged on as an Google oAuth user.  Update corrisponding crm user values
					$user->authenticate_id = $auth_id;
					$user->user_name = $auth_email;
					$user->user_hash = $user_hash;
					$user->first_name = $goauth_user['given_name'];
					$user->last_name = $goauth_user['family_name'];
					$user->email1 = $goauth_user['email'];
					$user->description = $goauth_user['picture'];
//					$user->sip_id = $goauth_user['email'];
					
//					$user->status = 'Active';			// If status is not Active - that doesn't mean it should log in
//					$user->employee_status = 'Active';		// We should check this and if its not active then not authorize login.
					$id = $user->save();

					$user->setPreference('loginfailed','0');
					$user->savePreferencesToDB();
					return true;
				}
	
				else
				{
					//  Valid account not found to login.  We should throw an error here.
					$_SESSION['login_error'] = 'Please contact an administrator to setup up your email address associated to this account';
					return false;
				}
			}
        } else 
		{
		//  G oAuth Failure.  No user profile has been returned
		$_SESSION['login_error'] = 'Your Google authentication has failed.';
		return false;
		
		}
    }
}