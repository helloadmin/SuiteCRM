<?php

require_once('modules/Users/authentication/SugarAuthenticate/SugarAuthenticate.php');
class GPlusAuthenticate extends SugarAuthenticate 
{
	public $userAuthenticateClass = 'GPlusAuthenticateUser';
	public $authenticationDir = 'GPlusAuthenticate';


	public function GPlusAuthenticate()
	{
		parent::SugarAuthenticate();
	}

}