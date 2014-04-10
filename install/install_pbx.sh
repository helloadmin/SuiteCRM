ls
#!/bin/bash

# install_pbx

LICENSE=$( cat << DELIM
#------------------------------------------------------------------------------
#
# "THE WAF LICENSE" (version 1)
# This is the Wife Acceptance Factor (WAF) License.  
# jamesdotfsatstubbornrosesd0tcom  wrote this file.  As long as you retain this
# notice you can do whatever you want with it. If you appreciate the work,
# please consider purchasing something from my wife's wishlist. That pays
# bigger dividends to this coder than anything else I can think of ;).  It also
# keeps her happy while she's being ignored; so I can work on this stuff.
#   James Rose
#
# latest wishlist: http://www.stubbornroses.com/waf.html
#
# Credit: Based off of the BEER-WARE LICENSE (REVISION 42) by Poul-Henning Kamp
#
#------------------------------------------------------------------------------
DELIM
)

#---------
#VARIABLES
#---------
#Variables are for the auto installation option.


# to start FreeSWITCH with -nonat option set SETNONAT to y
SETNONAT=n


modules_add=( mod_spandsp mod_dingaling mod_callcenter mod_lcr mod_cidlookup mod_memcache mod_codec2 mod_pocketsphinx mod_xml_cdr mod_say_es )

#-------
#DEFINES
#-------

FSGIT=git://git.freeswitch.org/freeswitch.git
FSSTABLE=true
FSStableVer="v1.2.stable"
#FSStableVer="v1.4.beta"


#right now, make -j not working. see: jira FS-3005
#CORES=$(/bin/grep processor -c /proc/cpuinfo)
CORES=1
FQDN=$(hostname -f)
SRCPATH="/usr/src/freeswitch"
EN_PATH="/usr/local/freeswitch/conf/autoload_configs"

GUI_NAME=suitecrm
FSREV="187abe02af4d64cdedc598bd3dfb1cd3ed0f4a91"
#IF FSCHECKOUTVER is true, FSSTABLE needs to be false
FSCHECKOUTVER=false
INSFREESWITCH=0
UPGFREESWITCH=0

#---------
#FUNCTIONS
#---------

function suitefail2ban {

/bin/cat > /etc/fail2ban/filter.d/$GUI_NAME.conf  <<'DELIM'
# Fail2Ban configuration file
#
# Author: soapee01
#

[Definition]

# Option:  failregex
# Notes.:  regex to match the password failures messages in the logfile. The
#          host must be matched by a group named "host". The tag "<HOST>" can
#          be used for standard IP/hostname matching and is only an alias for
#          (?:::f{4,6}:)?(?P<host>[\w\-.^_]+)
# Values:  TEXT
#
#failregex = [hostname] SuiteCRM: \[<HOST>\] authentication failed
#[hostname] variable doesn't seem to work in every case. Do this instead:
failregex = .* SuiteCRM: \[<HOST>\] authentication failed for
          = .* SuiteCRM: \[<HOST>\] provision attempt bad password for

# Option:  ignoreregex
# Notes.:  regex to ignore. If this regex matches, the line is ignored.
# Values:  TEXT
#
ignoreregex =
DELIM

/bin/grep -i $GUI_NAME /etc/fail2ban/jail.local > /dev/null

if [ $? -eq 0 ]; then
	/bin/echo "SuiteCRM Jail already set"
else
	/bin/cat >> /etc/fail2ban/jail.local  <<DELIM
[$GUI_NAME]

enabled  = true
port     = 80,443
protocol = tcp
filter   = $GUI_NAME
logpath  = /var/log/auth.log
action   = iptables-allports[name=$GUI_NAME, protocol=all]
#          sendmail-whois[name=$GUI_NAME, dest=root, sender=fail2ban@example.org] #no smtp server installed
maxretry = 5
findtime = 600
bantime  = 600	
DELIM
fi
}

function www_permissions {
	#consider not stopping here... it's causing some significant delays, or just pause until it starts back up...
	#/etc/init.d/freeswitch stop
	/usr/sbin/adduser www-data audio
	/usr/sbin/adduser www-data dialout
	/bin/echo "setting FreeSWITCH owned by www-dat.www-data"
	/bin/chown -R www-data.www-data /usr/local/freeswitch
	#remove 'other' permissions on freeswitch
	/bin/chmod -R o-rwx /usr/local/freeswitch/
	#set FreeSWITCH directories full permissions for user/group with group sticky
	/bin/echo "Setting group ID sticky for FreeSWITCH"
	/usr/bin/find /usr/local/freeswitch -type d -exec /bin/chmod u=rwx,g=srx,o= {} \;
	#make sure FreeSWITCH directories have group write
	/bin/echo "Setting Group Write for FreeSWITCH files"
	/usr/bin/find /usr/local/freeswitch -type f -exec /bin/chmod g+w {} \;
	#make sure FreeSWITCH files have group write
	/bin/echo "Setting Group Write for FreeSWITCH directories"
	/usr/bin/find /usr/local/freeswitch -type d -exec /bin/chmod g+w {} \;

	/bin/echo "Changing /etc/init.d/freeswitch to start with user www-data"	
	/bin/sed -i -e s,'USER=freeswitch','USER=www-data', /etc/init.d/freeswitch
	#/etc/init.d/freeswitch start
}



function build_modules {
	#bandaid
	sed -i -e "s/applications\/mod_voicemail_ivr/#applications\/mod_voicemail_ivr/" $SRCPATH/modules.conf
	#------------
	#  new way v2
	#------------
	#find the default modules - redundant really...
	modules_comp_default=( `/bin/grep -v ^$ /usr/src/freeswitch/modules.conf |/bin/grep -v ^# | /usr/bin/tr '\n' ' '` )
	#add the directory prefixes to the modules in array so the modules we wish to add will compile
	module_count=`echo ${#modules_add[@]}`
	index=0
	while [ "$index" -lt "$module_count" ]
	do
			modules_compile_add[$index]=`/bin/grep ${modules_add[$index]} $SRCPATH/modules.conf | sed -e "s/#//g"`
			let "index = $index + 1"
	done

	modules_compile=( ${modules_comp_default[*]} ${modules_compile_add[*]} )


	#BUILD MODULES.CONF for COMPILER
	echo
	echo
	echo "Now enabling modules for compile in $SRCPATH/modules.conf"
	index=0
	module_count=`echo ${#modules_compile[@]}`
	#get rid of funky spacing in modules.conf
	/bin/sed -i -e "s/ *//g" $SRCPATH/modules.conf
	while [ "$index" -lt "$module_count" ]
	do
			grep ${modules_compile[$index]} $SRCPATH/modules.conf > /dev/null
			if [ $? -eq 0 ]; then
					#module is present in file. see if we need to enable it
					grep '#'${modules_compile[$index]} $SRCPATH/modules.conf > /dev/null
					if [ $? -eq 0 ]; then
							/bin/sed -i -e s,'#'${modules_compile[$index]},${modules_compile[$index]}, $SRCPATH/modules.conf
							/bin/echo "     [ENABLED] ${modules_compile[$index]}"
					else
							/bin/echo "     ${modules_compile[$index]} ALREADY ENABLED!"
					fi
			else
					#module is not present. Add to end of file
					#/bin/echo "did not find ${modules_compile[$index]}"
					/bin/echo ${modules_compile[$index]} >> $SRCPATH/modules.conf
					/bin/echo "     [ADDED] ${modules_compile[$index]}"
			fi

			let "index = $index + 1"
	done
	#--------------
	#end new way v2
	#--------------
}

function enable_modules {
	#------------
	#  new way v2
	#------------
	#ENABLE MODULES for FreeSWITCH
	#
	echo
	echo
	echo "Now enabling modules for FreeSWITCH in $EN_PATH/modules.conf.xml"
	index=0
	module_count=`echo ${#modules_add[@]}`
	#get rid of any funky whitespace
	/bin/sed -i -e s,'<!-- *<','<!--<', -e s,'> *-->','>-->', $EN_PATH/modules.conf.xml
	while [ "$index" -lt "$module_count" ]
	do
		#more strangness to take care of, example:
		#Now enabling modules for FreeSWITCH in /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml
		#[ADDED] ../../libs/freetdm/mod_freetdm
		modules_add[$index]=`/bin/echo ${modules_add[$index]} | /bin/sed -e 's/.*mod_/mod_/'`
		grep ${modules_add[$index]} $EN_PATH/modules.conf.xml > /dev/null
		if [ $? -eq 0 ]; then
			#module is present in file, see if we need to enable it.
			grep  '<!--<load module="'${modules_add[$index]}'"/>-->' $EN_PATH/modules.conf.xml > /dev/null
			if [ $? -eq 0 ]; then
				#/bin/echo "found ${modules_compile[$index]}"
				/bin/sed -i -e s,'<!--<load module="'${modules_add[$index]}'"/>-->','<load module="'${modules_add[$index]}'"/>', \
				  $EN_PATH/modules.conf.xml
				/bin/echo "     [ENABLED] ${modules_add[$index]}"
			else
				/bin/echo "     ${modules_add[$index]} ALREADY ENABLED!"
			fi
        else
			#not in file. we need to add, and will do so below <modules> tag at top of file
			/bin/sed -i -e s,'<modules>','&\n <load module="'${modules_add[$index]}'"/>',  $EN_PATH/modules.conf.xml
			/bin/echo "     [ADDED] ${modules_add[$index]}"
		fi

		let "index = $index + 1"
	done

	#--------------
	#end new way v2
	#--------------
}

function freeswitch_logfiles {
	/bin/echo
	/bin/echo "       SEE: /etc/cron.daily/freeswitch_log_rotation"
	/bin/cat > /etc/cron.daily/freeswitch_log_rotation <<'DELIM'
#!/bin/bash
# logrotate replacement script
# put in /etc/cron.daily
# don't forget to make it executable
# you might consider changing /usr/local/freeswitch/conf/autoload_configs/logfile.conf.xml
#  <param name="rollover" value="0"/>

#number of days of logs to keep
NUMBERDAYS=30
FSPATH="/usr/local/freeswitch"

$FSPATH/bin/fs_cli -x "fsctl send_sighup" |grep '+OK' >/tmp/rotateFSlogs
if [ $? -eq 0 ]; then
       #-cmin 2 could bite us (leave some files uncompressed, eg 11M auto-rotate). Maybe -1440 is better?
       find $FSPATH/log/ -name "freeswitch.log.*" -cmin -2 -exec gzip {} \;
       find $FSPATH/log/ -name "freeswitch.log.*.gz" -mtime +$NUMBERDAYS -exec /bin/rm {} \;
       chown www-data.www-data $FSPATH/log/freeswitch.log
       chmod 660 $FSPATH/log/freeswitch.log
       logger FreeSWITCH Logs rotated
       /bin/rm /tmp/rotateFSlogs
else
       logger FreeSWITCH Log Rotation Script FAILED
       mail -s '$HOST FS Log Rotate Error' root < /tmp/rotateFSlogs
       /bin/rm /tmp/rotateFSlogs
fi
DELIM

	/bin/chmod 755 /etc/cron.daily/freeswitch_log_rotation

	/bin/echo "Now dropping 10MB limit from FreeSWITCH"
	/bin/echo "  This is so the rotation/compression part of the cron script"
	/bin/echo "  will work properly."
	/bin/echo "  SEE: /usr/local/freeswitch/conf/autoload_configs/logfile.conf.xml"

	# <param name="rollover" value="10485760"/>
	/bin/sed /usr/local/freeswitch/conf/autoload_configs/logfile.conf.xml -i -e s,\<param.*name\=\"rollover\".*value\=\"10485760\".*/\>,\<\!\-\-\<param\ name\=\"rollover\"\ value\=\"10485760\"/\>\ INSTALL_SCRIPT\-\-\>,g
}

case $1 in
	fix-https)
		nginxconfig
	;;

	fix-permissions)
		/etc/init.d/freeswitch stop
		www_permissions
		/etc/init.d/freeswitch start
	;;

	installpbx)
		INSFREESWITCH=1
		UPGFREESWITCH=0
	;;


	upgradepbx)
		INSFREESWITCH=0
		UPGFREESWITCH=1
	;;


	version)
		/bin/echo "  "$VERSION
		/bin/echo
		/bin/echo "$LICENSE"
		exit 0
	;;

	-v)
		/bin/echo "  "$VERSION
		/bin/echo
		/bin/echo "$LICENSE"
		exit 0
	;;

	--version)
		/bin/echo "  "$VERSION
		/bin/echo
		/bin/echo "$LICENSE"
		exit 0
	;;
	--help)
		/bin/echo
		/bin/echo "This script should be called as:"
		/bin/echo "  installpbx option1 option2"
		/bin/echo
		/bin/echo "    option1:"
		/bin/echo "      installpbx"
		/bin/echo "      upgradepbx"
		/bin/echo "      fix-https"
		/bin/echo "      fix-permissions"
		/bin/echo "      version|--version|-v"
		/bin/echo
		/bin/echo "    option2:"
		/bin/echo "      user: option waits in certain places for the user to check for errors"
		/bin/echo "            it is interactive and prompts you about what to install"
		/bin/echo "      auto: tries an automatic install. Get a cup of coffee, this will"
		/bin/echo "            take a while. FOR THE BRAVE!"
		/bin/echo 
		/bin/echo "      EXAMPLE"
		/bin/echo "         installpbx installpbx user"
		/bin/echo 
		exit 0
	;;
	*)
		INSFREESWITCH=1
		UPGFREESWITCH=0
	;;
esac

case $2 in
	user)
		DEBUG=1
	;;
	*)
		DEBUG=0
	;;
esac


#---------------------
#   ENVIRONMENT CHECKS
#---------------------
#check for root
if [ $EUID -ne 0 ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ ! -s /usr/bin/lsb_release ]; then
	/bin/echo "Tell your upstream distro to include lsb_release"
	/bin/echo
	apt-get upgrade && apt-get -y install lsb-release
fi

#check for internet connection
/usr/bin/wget -q --tries=10 --timeout=5 http://www.google.com -O /tmp/index.google &> /dev/null
if [ ! -s /tmp/index.google ]; then
	echo "No Internet connection. Exiting."
	/bin/rm /tmp/index.google
	#exit 1
else
	echo "Internet connection is working, continuing!"
	/bin/rm /tmp/index.google
fi


#----------------------
#END ENVIRONMENT CHECKS
#----------------------

#---------------------------------------
#       INSTALL    FREESWITCH
#---------------------------------------
if [ $INSFREESWITCH -eq 1 ]; then

	/bin/echo "Upgrading the system, and adding the necessary dependencies for a FreeSWITCH compile"
	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue..."
	fi

	/usr/bin/apt-get update
	/usr/bin/apt-get -y upgrade

		/usr/bin/apt-get -y install ssh vim git-core subversion build-essential \
		autoconf automake libtool libncurses5 libncurses5-dev libjpeg-dev ssh \
		screen htop pkg-config bzip2 curl libtiff4-dev ntp \
		time bison libssl-dev \
		unixodbc libmyodbc unixodbc-dev libtiff-tools

	LDRUN=0
	/bin/echo -ne "Waiting on ldconfig to finish so bootstrap will work"
	while [ $LDRUN -eq 0 ]
	do
			echo -ne "."
			sleep 1
			/usr/bin/pgrep -f ldconfig > /dev/null
			LDRUN=$?
	done

	/bin/echo
	/bin/echo
	/bin/echo "ldconfig is finished"
	/bin/echo

	if [ ! -e /tmp/install_suite_status ]; then
		touch /tmp/install_suite_status
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	#-----------------
	# Databases
	#-----------------
	#Lets ask... sqlite or postgresql -- for user option only

		/bin/echo -ne "Installing PostgeSQL"

		#update repository for postgres 9.3 ...
		/bin/echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > /etc/apt/sources.list.d/pgdg.list
		wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | sudo apt-key add -
		/usr/bin/apt-get update
		/usr/bin/apt-get -y install postgresql-9.3 libpq-dev

		/bin/su -l postgres -c "/usr/bin/createuser -s -e freeswitch"
		/bin/su -l postgres -c "/usr/bin/createdb -E UTF8 -T template0 -O freeswitch freeswitch"
		PGSQLPASSWORD="dummy"
		PGSQLPASSWORD2="dummy2"
		while [ $PGSQLPASSWORD != $PGSQLPASSWORD2 ]; do
		/bin/echo
		/bin/echo
		/bin/echo "THIS PROBABLY ISN'T THE MOST SECURE THING TO DO."
		/bin/echo "IT IS; HOWEVER, AUTOMATED. WE ARE STORING THE PASSWORD"
		/bin/echo "AS A BASH VARIABLE, AND USING ECHO TO PIPE IT TO"
		/bin/echo "psql. THE COMMAND USED IS:"
		/bin/echo
		/bin/echo "/bin/su -l postgres -c \"/bin/echo 'ALTER USER freeswitch with PASSWORD \$PGSQLPASSWORD;' | psql freeswitch\""
		/bin/echo
		/bin/echo "AFTERWARDS WE OVERWRITE THE VARIABLE WITH RANDOM DATA"
		/bin/echo
		/bin/echo "The pgsql username is freeswitch"
		/bin/echo "The pgsql database name is freeswitch"
		/bin/echo "Please provide a password for the freeswitch user"
		#/bin/stty -echo
		read -s -p "  Password: " PGSQLPASSWORD
		/bin/echo
		/bin/echo "Let's repeat that"
		read -s -p "  Password: " PGSQLPASSWORD2
		/bin/echo
		#/bin/stty echo
		done

		/bin/su -l postgres -c "/bin/echo \"ALTER USER freeswitch with PASSWORD '$PGSQLPASSWORD';\" | /usr/bin/psql freeswitch"
		/bin/echo "overwriting pgsql password variable with random data"
		PGSQLPASSWORD=$(/usr/bin/head -c 512 /dev/urandom)
		PGSQLPASSWORD2=$(/usr/bin/head -c 512 /dev/urandom)

	#------------------------
	# GIT FREESWITCH
	#------------------------
	/bin/grep 'git_done' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "Git Already Done. Skipping"	
	else
		
		cd /usr/src
		if [ "$FSSTABLE" == true ]; then
			echo "installing stable $FSStableVer of FreeSWITCH"
			/usr/bin/time /usr/bin/git clone -b $FSStableVer $FSGIT
			cd /usr/src/freeswitch
			/usr/bin/git checkout $FSStableVer
			if [ $? -ne 0 ]; then
				#git had an error
				/bin/echo "GIT ERROR"
				exit 1
			fi
		else
			echo "going dev branch.  Hope this works for you."
			/usr/bin/time /usr/bin/git clone $FSGIT
			if [ $? -ne 0 ]; then
				#git had an error
				/bin/echo "GIT ERROR"
				exit 1
			fi

			if [ $FSCHECKOUTVER == true ]; then
				echo "OK we'll check out FreeSWITCH version $FSREV"
				cd /usr/src/freeswitch
				/usr/bin/git checkout $FSREV
				if [ $? -ne 0 ]; then
					#git checkout had an error
					/bin/echo "GIT CHECKOUT ERROR"
					exit 1
				fi
			fi
			/bin/echo "git_done" >> /tmp/install_suite_status
		fi
	fi

	if [ -e /usr/src/FreeSWITCH ]; then
		/bin/ln -s /usr/src/FreeSWITCH /usr/src/freeswitch
	elif [ -e /usr/src/freeswitch.git ]; then
		/bin/ln -s /usr/src/freeswitch.git /usr/src/freeswitch
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	#------------------------
	# BOOTSTRAP FREESWITCH
	#------------------------
	/bin/grep 'bootstrap_done' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "Bootstrap already done. skipping"
	else
		#might see about -j option to bootstrap.sh
		/etc/init.d/ssh start
		cd /usr/src/freeswitch
		/bin/echo
		/bin/echo "FreeSWITCH Downloaded"
		/bin/echo 
		/bin/echo "Bootstrapping."
		/bin/echo
		#next line failed (couldn't find file) not sure why.
		#it did run fine a second time.  Go figure (really).
		#ldconfig culprit?
		if [ $CORES -gt 1 ]; then 
			/bin/echo "  multicore processor detected. Starting Bootstrap with -j"
			if [ $DEBUG -eq 1 ]; then
				/bin/echo
				read -p "Press Enter to continue (check for errors)"
			fi
			/usr/bin/time /usr/src/freeswitch/bootstrap.sh -j
		else 
			/bin/echo "  singlecore processor detected. Starting Bootstrap sans -j"
			if [ $DEBUG -eq 1 ]; then
				/bin/echo
				read -p "Press Enter to continue (check for errors)"
			fi
			/usr/bin/time /usr/src/freeswitch/bootstrap.sh
		fi

		if [ $? -ne 0 ]; then
			#bootstrap had an error
			/bin/echo "BOOTSTRAP ERROR"
			exit 1
		else
			/bin/echo "bootstrap_done" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	#------------------------
	# build modules.conf 
	#------------------------
	/bin/grep 'build_modules' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "Modules.conf Already edited"	
	else
		#file exists and has been edited
		build_modules
		#check exit status
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: Failed to enable build modules in modules.conf."
			exit 1
		else
			/bin/echo "build_modules" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	#------------------------
	# CONFIGURE FREESWITCH 
	#------------------------
	/bin/grep 'config_done' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "FreeSWITCH already Configured! Skipping."
	else
		/bin/echo
		/bin/echo -ne "Configuring FreeSWITCH. This will take a while [~15 minutes]"
		/bin/sleep 1
		/bin/echo -ne " ."
		/bin/sleep 1
		/bin/echo -ne " ."
		/bin/sleep 1
		/bin/echo -ne " ."

		/usr/bin/time /usr/src/freeswitch/configure --enable-core-pgsql-support --enable-zrtp

		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: FreeSWITCH Configure ERROR."
			exit 1
		else
			/bin/echo "config_done" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	if [ -a /etc/init.d/freeswitch ]; then
		/bin/echo " In case of an install where FS exists (iso), stop FS"
		/etc/init.d/freeswitch stop
	fi


	#------------------------
	# COMPILE FREESWITCH 
	#------------------------
	/bin/grep 'compile_done' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "FreeSWITCH already Compiled! Skipping."
	else
		#might see about -j cores option to make...

		/bin/echo
		/bin/echo -ne "Compiling FreeSWITCH. This might take a LONG while [~30 minutes]"
		/bin/sleep 1
		/bin/echo -ne "."
		/bin/sleep 1
		/bin/echo -ne "."
		/bin/sleep 1
		/bin/echo -ne "."

		#making sure pwd is correct
		cd /usr/src/freeswitch
		if [ $CORES -gt 1 ]; then 
			/bin/echo "  multicore processor detected. Compiling with -j $CORES"
			#per anthm compile the freeswitch core first, then the modules.
			/usr/bin/time /usr/bin/make -j $CORES core
			/usr/bin/time /usr/bin/make -j $CORES
		else 
			/bin/echo "  singlecore processor detected. Starting compile sans -j"
			/usr/bin/time /usr/bin/make 
		fi

		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: FreeSWITCH Build Failure."
			exit 1
		else
			/bin/echo "compile_done" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	#------------------------
	# INSTALL FREESWITCH 
	#------------------------
	/bin/grep 'install_done' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "FreeSWITCH already Installed! Skipping."
	else
		#dingaling/ubuntu has an issue. let's edit the file...
		#"--mode=relink gcc" --> "--mode=relink gcc -lgnutls" 

		#tls no longer required for dingaling, so this weird issue doesn't happen. now uses openssl.
#		/bin/grep 'lgnutls' /usr/src/freeswitch/src/mod/endpoints/mod_dingaling/mod_dingaling.la > /dev/null
#		if [ $? -eq 0 ]; then
#			/bin/echo "dingaling fix already applied."
#		else
#			/bin/sed -i -e s,'--mode=relink gcc','--mode=relink gcc -lgnutls', /usr/src/freeswitch/src/mod/endpoints/mod_dingaling/mod_dingaling.la
#		fi
		cd /usr/src/freeswitch
		if [ $CORES -gt 1 ]; then 
			/bin/echo "  multicore processor detected. Installing with -j $CORES"
			/usr/bin/time /usr/bin/make -j $CORES install
		else 
			/bin/echo "  singlecore processor detected. Starting install sans -j"
			/usr/bin/time /usr/bin/make install
		fi
		#/usr/bin/time /usr/bin/make install

		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: FreeSWITCH INSTALL Failure."
			exit 1
		else
			/bin/echo "install_done" >> /tmp/install_suite_status
		fi
	fi

	#------------------------
	# FREESWITCH  HD SOUNDS
	#------------------------
	/bin/grep 'sounds_done' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "FreeSWITCH HD SOUNDS DONE! Skipping."
	else
		/bin/echo
		/bin/echo -ne "Installing FreeSWITCH HD sounds (16/8khz). This will take a while [~10 minutes]"
		/bin/sleep 1
		/bin/echo -ne "."
		/bin/sleep 1
		/bin/echo -ne "."
		/bin/sleep 1
		/bin/echo "."
		cd /usr/src/freeswitch
		if [ $CORES -gt 1 ]; then 
			/bin/echo "  multicore processor detected. Installing with -j $CORES"
			/usr/bin/time /usr/bin/make -j $CORES hd-sounds-install
		else 
			/bin/echo "  singlecore processor detected. Starting install sans -j"
			/usr/bin/time /usr/bin/make hd-sounds-install
		fi
		#/usr/bin/time /usr/bin/make hd-sounds-install

		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: FreeSWITCH make cdsounds-install ERROR."
			exit 1
		else
			/bin/echo "sounds_done" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi


	#------------------------
	# FREESWITCH  MOH
	#------------------------
	/bin/grep 'moh_done' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "FreeSWITCH MOH DONE! Skipping."
	else
		/bin/echo
		/bin/echo -ne "Installing FreeSWITCH HD Music On Hold sounds (16/8kHz). This will take a while [~10 minutes]"
		/bin/sleep 1
		/bin/echo -ne "."
		/bin/sleep 1
		/bin/echo -ne "."
		/bin/sleep 1
		/bin/echo "."

		cd /usr/src/freeswitch
		if [ $CORES -gt 1 ]; then 
			/bin/echo "  multicore processor detected. Installing with -j $CORES"
			/usr/bin/time /usr/bin/make -j $CORES hd-moh-install
		else 
			/bin/echo "  singlecore processor detected. Starting install sans -j"
			/usr/bin/time /usr/bin/make hd-moh-install
		fi
		#/usr/bin/make hd-moh-install

		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: FreeSWITCH make cd-moh-install ERROR."
			exit 1
		else
			/bin/echo "moh_done" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	#------------------------
	# FREESWITCH INIT
	#------------------------
	#no need for tmp file. already handled...
	/bin/echo
	/bin/echo "Configuring /etc/init.d/freeswitch"

	/bin/grep local /etc/init.d/freeswitch > /dev/null
	if [ $? -eq 0 ]; then
		#file exists and has been edited
		/bin/echo "/etc/init.d/freeswitch already edited, skipping"
	elif [ -e /usr/src/freeswitch/debian/freeswitch.init ]; then
		/bin/sed /usr/src/freeswitch/debian/freeswitch.init -e s,opt,usr/local, >/etc/init.d/freeswitch
	else
		/bin/sed /usr/src/freeswitch/debian/freeswitch-sysvinit.freeswitch.init  -e s,opt,usr/local, >/etc/init.d/freeswitch
		#DAEMON
		/bin/sed -i /etc/init.d/freeswitch -e s,^DAEMON=.*,DAEMON=/usr/local/freeswitch/bin/freeswitch,

		#DAEMON_ARGS
		/bin/sed -i /etc/init.d/freeswitch -e s,'^DAEMON_ARGS=.*','DAEMON_ARGS="-u www-data -g www-data -rp -nc -nonat"',

		#PIDFILE
		/bin/sed -i /etc/init.d/freeswitch -e s,^PIDFILE=.*,PIDFILE=/usr/local/freeswitch/run/\$NAME.pid,

		#WORKDIR
		/bin/sed -i /etc/init.d/freeswitch -e s,^WORKDIR=.*,WORKDIR=/usr/local/freeswitch/lib/,
	fi

	if [ $? -ne 0 ]; then
		#previous had an error
		/bin/echo "ERROR: Couldn't edit FreeSWITCH init script."
		exit 1
	fi

	/bin/chmod 755 /etc/init.d/freeswitch
	/bin/echo "enabling FreeSWITCH to start at boot"
	/bin/mkdir /etc/freeswitch
	/bin/touch /etc/freeswitch/freeswitch.xml

	/bin/grep true /etc/default/freeswitch > /dev/null
	if [ $? -eq 0 ]; then
		#file exists and has been edited
		/bin/echo "/etc/default/freeswitch already edited, skipping"
	else
		if [ -e /usr/src/freeswitch/debian/freeswitch-sysvinit.freeswitch.default ]; then
			/bin/sed /usr/src/freeswitch/debian/freeswitch-sysvinit.freeswitch.default -e s,false,true, > /etc/default/freeswitch
			if [ $? -ne 0 ]; then
					#previous had an error
					/bin/echo "ERROR: Couldn't edit freeswitch RC script."
					exit 1
			fi
		else
			/bin/sed /usr/src/freeswitch/debian/freeswitch.default -e s,false,true, > /etc/default/freeswitch
			if [ $? -ne 0 ]; then
				#previous had an error
				/bin/echo "ERROR: Couldn't edit freeswitch RC script."
				exit 1
			fi
		fi
		if [ $DEBUG -eq 1 ]; then
			/bin/echo "Checking for a public IP Address..."

			PUBLICIP=no

			#turn off the auto-nat when we start freeswitch.
			#nasty syntax. searches for 10.a.b.c or 192.168.x.y addresses in ifconfig.
			/sbin/ifconfig | \
			/bin/grep 'inet addr:' | \
			/usr/bin/cut -d: -f2 | \
			/usr/bin/awk '{ print $1}' | \
			while read IPADDR; do
				echo "$IPADDR" | \
				/bin/grep -e '^10\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$' \
					-e '^192\.168\.[0-9]\{1,3\}\.[0-9]\{1,3\}$' \
					-e '^127.0.0.1$'
					#-e '^172\.[16-31]\.[0-9]\{1,3\}\.[0-9]\{1,3\}' \

				if [ $? -ne 0 ]; then
					PUBLICIP=yes
				fi
			done

			case "$PUBLICIP" in 
				[Yy]*)
					if [ $DEBUG -eq 1 ]; then  
						/bin/echo "You appear to have a public IP address."
						/bin/echo " I can make sure FreeSWITCH starts with"
						/bin/echo " the -nonat option (starts quicker)."
						/bin/echo 
						read -p "Would you like for me to do this (y/n)? " SETNONAT
					fi
				
				;;

				*)
					/bin/echo "Dynamic IP. leaving FreeSWITCH for aggressive nat"
					SETNONAT=no
				;;
			esac
		fi

		case "$SETNONAT" in
			[Yy]*)
				/bin/sed /etc/default/freeswitch -i -e s,'FREESWITCH_PARAMS="-nc"','FREESWITCH_PARAMS="-nc -nonat"',
				/bin/echo "init script set to start 'freeswitch -nc -nonat'"
			;;

			*)
				/bin/echo "OK, not using -nonat option."
			;;
		esac
		/bin/echo
		/usr/sbin/update-rc.d -f freeswitch defaults
	fi

	/bin/echo

	#don't do this.  If freeswitch is a machine name, it really screws this test.  It
	#won't hurt to adduser a second time anyhow.
	#/bin/grep freeswitch /etc/passwd > /dev/null
	#if [ $? -eq 0 ]; then
		#user already exists
	#	/bin/echo "FreeSWITCH user already exists, skipping..."
	#else
	/bin/echo "adding freeswitch user"
	/usr/sbin/adduser --disabled-password  --quiet --system \
		--home /usr/local/freeswitch \
		--gecos "FreeSWITCH Voice Platform" --ingroup daemon \
		freeswitch

	if [ $? -ne 0 ]; then
		#previous had an error
		/bin/echo "ERROR: Failed adding freeswitch user."
		exit 1
	fi
	#fi

	/usr/sbin/adduser freeswitch audio
	/usr/sbin/groupadd freeswitch


	/bin/chown -R freeswitch:daemon /usr/local/freeswitch/

	/bin/echo "removing 'other' permissions on freeswitch"
	/bin/chmod -R o-rwx /usr/local/freeswitch/
	/bin/echo
	cd /usr/local/
	/bin/chown -R freeswitch:daemon /usr/local/freeswitch
	/bin/echo "FreeSWITCH directories now owned by freeswitch.daemon"
	/usr/bin/find freeswitch -type d -exec /bin/chmod u=rwx,g=srx,o= {} \;
	/bin/echo "FreeSWITCH directories now sticky group. This will cause any files created"
	/bin/echo "  to default to the daemon group so FreeSWITCH can read them"
	/bin/echo
	/bin/ln -s /usr/local/freeswitch/bin/fs_cli /usr/local/bin/


	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		/bin/echo "Press Enter to continue (check for errors)"
		read
	fi

	#------------------------
	# enable modules.conf.xml
	#------------------------
	/bin/grep 'enable_modules' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "Modules.conf.xml Already enabled"
	else
		#file exists and has been edited
		enable_modules
		#check exit status
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: Failed to enable modules in modules.conf.xml."
			exit 1
		else
			/bin/echo "enable_modules" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		read -p "Press Enter to continue (check for errors)"
	fi

	#-----------------
	#Setup logrotate
	#-----------------
#	if [ -a /etc/logrotate.d/freeswitch ]; then
	if [ -a /etc/cron.daily/freeswitch_log_rotation ]; then
		/bin/echo "Logrotate for FreeSWITCH Already Done!"

		#call log script creation function
		freeswitch_logfiles
	fi

	#-----------------
	#harden FreeSWITCH
	#-----------------
	/bin/echo -ne "HARDENING"
	sleep 1
	/bin/echo -ne " ."
	sleep 1
	/bin/echo -ne " ."
	sleep 1
	/bin/echo -ne " ."

	/usr/bin/apt-get -y install fail2ban
	/bin/echo
	/bin/echo "Checking log-auth-failures"
	/bin/grep log-auth-failures /usr/local/freeswitch/conf/sip_profiles/internal.xml > /dev/null
	if [ $? -eq 0 ]; then
		#see if it's uncommented
		/bin/grep log-auth-failures /usr/local/freeswitch/conf/sip_profiles/internal.xml | /bin/grep '<!--' > /dev/null
		if [ $? -eq 1 ]; then
			#Check for true
			/bin/grep log-auth-failures /usr/local/freeswitch/conf/sip_profiles/internal.xml |/bin/grep true > /dev/null
			if [ $? -eq 0 ]; then
				/bin/echo "     [ENABLED] log-auth-failures - Already Done!"
			else
				#it's false and uncommented, change it to true
				/bin/sed -i -e s,'<param name="log-auth-failures" value="false"/>','<param name="log-auth-failures" value="true"/>', \
					/usr/local/freeswitch/conf/sip_profiles/internal.xml
				/bin/echo  "     [ENABLED] log-auth-failures - Was False!"
			fi
		else 
			# It's commented
			# check for true
			/bin/grep log-auth-failures /usr/local/freeswitch/conf/sip_profiles/internal.xml |/bin/grep true > /dev/null
			if [ $? -eq 0 ]; then
				#it's commented and true
				/bin/sed -i -e s,'<!-- *<param name="log-auth-failures" value="true"/>','<param name="log-auth-failures" value="true"/>', \
					-e s,'<param name="log-auth-failures" value="true"/> *-->','<param name="log-auth-failures" value="true"/>', \
					-e s,'<!--<param name="log-auth-failures" value="true"/>','<param name="log-auth-failures" value="true"/>', \
					-e s,'<param name="log-auth-failures" value="true"/>-->','<param name="log-auth-failures" value="true"/>', \
					/usr/local/freeswitch/conf/sip_profiles/internal.xml
				/bin/echo  "     [ENABLED] log-auth-failures - Was Commented!"
			else
				#it's commented and false.
				/bin/sed -i -e s,'<!-- *<param name="log-auth-failures" value="false"/>','<param name="log-auth-failures" value="true"/>', \
					-e s,'<param name="log-auth-failures" value="false"/> *-->','<param name="log-auth-failures" value="true"/>', \
					-e s,'<!--<param name="log-auth-failures" value="false"/>','<param name="log-auth-failures" value="true"/>', \
					-e s,'<param name="log-auth-failures" value="false"/>-->','<param name="log-auth-failures" value="true"/>', \
					/usr/local/freeswitch/conf/sip_profiles/internal.xml
				/bin/echo  "     [ENABLED] log-auth-failures - Was Commented and False!"
			fi
		fi
	else
		#It's not present...
		/bin/sed -i -e s,'<settings>','&\n <param name="log-auth-failures" value="true"/>', \
			/usr/local/freeswitch/conf/sip_profiles/internal.xml
		/bin/echo  "     [ENABLED] log-auth-failures - Wasn't there!" 
	fi

	if [ -a /etc/fail2ban/filter.d/freeswitch.conf ]; then
		/bin/echo "fail2ban filter for freeswitch already done!"

	else
		/bin/cat > /etc/fail2ban/filter.d/freeswitch.conf  <<"DELIM"
# Fail2Ban configuration file
#
# Author: Rupa SChomaker
#

[Definition]

# Option:  failregex
# Notes.:  regex to match the password failures messages in the logfile. The
#          host must be matched by a group named "host". The tag "<HOST>" can
#          be used for standard IP/hostname matching and is only an alias for
#          (?:::f{4,6}:)?(?P<host>[\w\-.^_]+)
# Values:  TEXT
#
failregex = \[WARNING\] sofia_reg.c:\d+ SIP auth failure \(REGISTER\) on sofia profile \'\w+\' for \[.*\] from ip <HOST>
            \[WARNING\] sofia_reg.c:\d+ SIP auth failure \(INVITE\) on sofia profile \'\w+\' for \[.*\] from ip <HOST>

# Option:  ignoreregex
# Notes.:  regex to ignore. If this regex matches, the line is ignored.
# Values:  TEXT
#
ignoreregex =
DELIM

/bin/cat > /etc/fail2ban/filter.d/freeswitch-dos.conf  <<"DELIM"
# Fail2Ban configuration file
#
# Author: soapee01
#

[Definition]

# Option:  failregex
# Notes.:  regex to match the password failures messages in the logfile. The
#          host must be matched by a group named "host". The tag "<HOST>" can
#          be used for standard IP/hostname matching and is only an alias for
#          (?:::f{4,6}:)?(?P<host>[\w\-.^_]+)
# Values:  TEXT
#
failregex = \[WARNING\] sofia_reg.c:\d+ SIP auth challenge \(REGISTER\) on sofia profile \'\w+\' for \[.*\] from ip <HOST>

# Option:  ignoreregex
# Notes.:  regex to ignore. If this regex matches, the line is ignored.
# Values:  TEXT
#
ignoreregex =
DELIM

	fi

	#see if we've done this before (as in an ISO was made
	#with this script but the source wasn't included
	#so we have to reinstall...
	/bin/grep freeswitch /etc/fail2ban/jail.local > /dev/null
	if [ $? -ne 0 ]; then
		#add the following stanzas to the end of our file (don't overwrite)
		/bin/cat >> /etc/fail2ban/jail.local  <<'DELIM'
[freeswitch-tcp]
enabled  = true
port     = 5060,5061,5080,5081
protocol = tcp
filter   = freeswitch
logpath  = /usr/local/freeswitch/log/freeswitch.log
action   = iptables-allports[name=freeswitch-tcp, protocol=all]
maxretry = 5
findtime = 600
bantime  = 600
#          sendmail-whois[name=FreeSwitch, dest=root, sender=fail2ban@example.org] #no smtp server installed

[freeswitch-udp]
enabled  = true
port     = 5060,5061,5080,5081
protocol = udp
filter   = freeswitch
logpath  = /usr/local/freeswitch/log/freeswitch.log
action   = iptables-allports[name=freeswitch-udp, protocol=all]
maxretry = 5
findtime = 600
bantime  = 600
#          sendmail-whois[name=FreeSwitch, dest=root, sender=fail2ban@example.org] #no smtp server installed

[freeswitch-dos]
enabled = true
port = 5060,5061,5080,5081
protocol = udp
filter = freeswitch-dos
logpath = /usr/local/freeswitch/log/freeswitch.log
action = iptables-allports[name=freeswitch-dos, protocol=all]
maxretry = 50
findtime = 30
bantime  = 6000
DELIM

	else
		/bin/echo"fail2ban jail.local for freeswitch already done!"
	fi

	#problem with the way ubuntu logs ssh failures [fail2ban]
	#  Failed password for root from 1.2.3.4 port 22 ssh2
	#  last message repeated 5 times
	#  SOLUTION: Turn off RepeatedMsgReduction in rsyslog.
	/bin/echo "Turning off RepeatedMsgReduction in /etc/rsyslog.conf"
	#not sure what the deal is with the single quotes here. Fixed in v4.4.0
	#/bin/sed -i ‘s/RepeatedMsgReduction\ on/RepeatedMsgReduction\ off/’ /etc/rsyslog.conf
	/bin/sed -i 's/RepeatedMsgReduction\ on/RepeatedMsgReduction\ off/' /etc/rsyslog.conf
	/etc/init.d/rsyslog restart

	#bug in fail2ban.  If you see this error
	#2011-02-27 14:11:42,326 fail2ban.actions.action: ERROR  iptables -N fail2ban-freeswitch-tcp
	#http://www.fail2ban.org/wiki/index.php/Fail2ban_talk:Community_Portal#fail2ban.action.action_ERROR_on_startup.2Frestart

	/bin/grep -A 1 'time.sleep(0\.1)' /usr/bin/fail2ban-client |/bin/grep beautifier > /dev/null
	if [ $? -ne 0 ]; then
		/bin/sed -i -e s,beautifier\.setInputCmd\(c\),'time.sleep\(0\.1\)\n\t\t\tbeautifier.setInputCmd\(c\)', /usr/bin/fail2ban-client
		#this does slow the restart down quite a bit.
	else
		/bin/echo '   time.sleep(0.1) already added to /usr/bin/fail2ban-client'
	fi
	#still may have a problem with logrotate causing missing new FS log files.
	#should see log lines such as:
	#2011-02-13 06:37:59,889 fail2ban.filter : INFO   Log rotation detected for /usr/local/freeswitch/log/freeswitch.log
	/etc/init.d/freeswitch start
	/etc/init.d/fail2ban restart

	/bin/echo "     fail2ban for ssh enabled by default"
	/bin/echo "     Default is 3 failures before your IP gets blocked for 600 seconds"
	/bin/echo "      SEE http://wiki.freeswitch.org/wiki/Fail2ban"

	/bin/echo
	/bin/echo
	/bin/echo "FreeSWITCH Installation Completed. Have Fun!"
	/bin/echo

	suitefail2ban
	/etc/init.d/fail2ban restart


fi

#---------------------------------------
#     DONE INSTALLING FREESWITCH
#---------------------------------------




#------------------------------------
#       UPGRADE FREESWITCH
#------------------------------------

if [ $UPGFREESWITCH -eq 1 ]; then

	#------------------------
	# build modules.conf 
	#------------------------
	/bin/grep 'build_modules' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "Modules.conf Already edited"	
	else
		#file exists and has been edited
		build_modules
		#check exit status
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: Failed to enable build modules in modules.conf."
			exit 1
		else
			/bin/echo "build_modules" >> /tmp/install_suite_status
		fi
	fi
	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		/bin/echo "Press Enter to continue (check for errors)"
		read
	fi

	#------------------------
	# make current 
	#------------------------
	/bin/grep 'made_current' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "Modules.conf Already edited"	
	else
		/bin/echo
		/bin/echo ' going to run make curent'
		/bin/echo "   Make current completely cleans the build environment and rebuilds FreeSWITCH™"
		/bin/echo "   so it runs a long time. However, it will not overwrite files in a pre-existing"
		/bin/echo '   "conf" directory. Also, the clean targets leave the "modules.conf" file.'
		/bin/echo "   This handles the git pull, cleanup, and rebuild in one step"
		/bin/echo '       src: http://wiki.freeswitch.org/wiki/Installation_Guide'
		cd /usr/src/freeswitch
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "/usr/src/freeswitch does not exist"
			exit 1
		fi
		cd /usr/src/freeswitch

		#get on the 1.2.x release first...
		echo
		echo
		echo "Checking to see which version of FreeSWITCH you are on"
		git status |grep "1.2"
		if [ $? -ne 0 ]; then
			echo "It appears that you are currently on the FreeSWITCH Git Master branch, or no branch."
			echo "  We currently recommend that you switch to the 1.2.x branch,"
			echo "  since 1.4 [master] may not be very stable."
			echo
			read -p "Shall we change to the 1.2.x branch [Y/n]? " YESNO
		else
			YESNO="no"
		fi

		case $YESNO in
				[Nn]*)
						echo "OK, staying on current...."
						FSSTABLE=false
				;;

				*)
						echo "OK, switching to 1.2.x."
						FSSTABLE=true
				;;
		esac

		if [ $FSSTABLE == true ]; then
			echo "OK we'll now use the 1.2.x stable branch"
			cd /usr/src/freeswitch
			
			#odd edge case, I think from a specific version checkout
				# git status
				# Not currently on any branch.
				# Untracked files:
				#   (use "git add <file>..." to include in what will be committed)
				#
				#       src/mod/applications/mod_httapi/Makefile

			git status |grep -i "not currently"
			if [ $? -eq 0 ]; then
				echo "You are not on master branch.  We have to fix that first"
				/usr/bin/git checkout master
				if [ $? -ne 0 ]; then
					#git checkout had an error
					/bin/echo "GIT CHECKOUT to 1.2.x ERROR"
					exit 1
				fi
			fi

			#/usr/bin/time /usr/bin/git clone -b $FSStableVer git://git.freeswitch.org/freeswitch.git
			/usr/bin/git pull
			if [ $? -ne 0 ]; then
				#git checkout had an error
				/bin/echo "GIT PULL to 1.2.x ERROR"
				exit 1
			fi
			/usr/bin/git checkout $FSStableVer
			if [ $? -ne 0 ]; then
				#git checkout had an error
				/bin/echo "GIT CHECKOUT to 1.2.x ERROR"
				exit 1
			fi
			#/usr/bin/git checkout master
			#if [ $? -ne 0 ]; then
			#	#git checkout had an error
			#	/bin/echo "GIT CHECKOUT to 1.2.x ERROR"
			#	exit 1
			#fi

		else
			echo "staying on dev branch.  Hope this works for you."
		fi

		cd /usr/src/freeswitch
		echo "reconfiguring mod_spandsp"
		make spandsp-reconf

		if [ $CORES > "1" ]; then 
			/bin/echo "  multicore processor detected. Upgrading with -j $CORES"
			/usr/bin/time /usr/bin/make -j $CORES current
		else 
			/bin/echo "  singlecore processor detected. Starting upgrade sans -j"
			/usr/bin/time /usr/bin/make current
		fi
		#/usr/bin/make current
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "make current error"
			exit 1
		fi

		if [ $DEBUG -eq 1 ]; then
			/bin/echo
			/bin/echo "I'm going to stop here and wait.  FreeSWITCH has now been compiled and is ready to install"
			/bin/echo "but in order to do this we need to stop FreeSWITCH [which will dump any active calls]."
			/bin/echo "This should not take too long to finish, but we should try and time things correctly."
			/bin/echo "The current status of your switch is:"
			/bin/echo
			/usr/local/freeswitch/bin/fs_cli -x status
			/bin/echo
			/bin/echo -n "Press Enter to continue the upgrade."
			read
		fi

		/etc/init.d/freeswitch stop
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "Init ERROR, couldn't stop Freeswitch"
			exit 1
		fi
		/usr/bin/make install
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "INSTALL ERROR!"
			exit 1
		else 
			/bin/echo "made_current" >> /tmp/install_suite_status
		fi
	fi

	#------------------------
	# enable modules.conf.xml
	#------------------------
	/bin/grep 'enable_modules' /tmp/install_suite_status > /dev/null
	if [ $? -eq 0 ]; then
		/bin/echo "Modules.conf.xml Already enabled"
	else
		#file exists and has been edited
		enable_modules
		#check exit status
		if [ $? -ne 0 ]; then
			#previous had an error
			/bin/echo "ERROR: Failed to enable modules in modules.conf.xml."
			exit 1
		else
			/bin/echo "enable_modules" >> /tmp/install_suite_status
		fi
	fi

	if [ $DEBUG -eq 1 ]; then
		/bin/echo
		/bin/echo "Press Enter to continue (check for errors)"
		read
	fi

	#check for logrotate and change to cron.daily
	if [ -a /etc/logrotate.d/freeswitch ]; then
		/bin/echo "System configured for logrotate, changing"
		/bin/echo "   to new way."
		/bin/rm /etc/logrotate.d/freeswitch
		/etc/init.d/logrotate restart
		freeswitch_logfiles
	fi

	/etc/init.d/freeswitch start
fi
#------------------------------------
#    DONE UPGRADING FREESWITCH
#------------------------------------



/bin/echo "Checking to see if FreeSWITCH is running!"
/usr/bin/pgrep freeswitch
if [ $? -ne 0 ]; then
	/etc/init.d/freeswitch start
else
	/bin/echo "    DONE!"
fi

exit 0

---------
#CHANGELOG
#---------

#v1 2014 March 06
# was first cut
