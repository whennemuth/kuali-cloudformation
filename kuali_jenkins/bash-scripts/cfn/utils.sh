#!/bin/bash

JENKINS_HOME=/var/lib/jenkins
JENKINS_CLI_JAR=$JENKINS_HOME/jenkins-cli.jar
PASSWORD_FILE=$JENKINS_HOME/secrets/initialAdminPassword
CRUMB_FILE=$JENKINS_HOME/_cfn-config/crumb
COOKIE_JAR=$JENKINS_HOME/_cfn-config/cookiejar
ADMIN_PASSWORD_RESET=$JENKINS_HOME/_cfn-config/LastAdminPasswordReset

jenkinsIsSecure() {
  local cfgxml=$JENKINS_HOME/config.xml
  if [ -f $cfgxml ] ; then
    local secure=$(grep -Po '(?<=<useSecurity>)[^<]+' $cfgxml)
    if [ "$secure" == 'true' ] ; then
      local strategy=$(grep '<authorizationStrategy' $cfgxml | grep -o 'Unsecured')
      if [ "${strategy,,}" == 'unsecured' ] ; then
        secure='false'
      fi
    fi
  else
    # On first startup, jenkins is secure by default
    local secure='true'
  fi
  [ "$secure" == 'true' ] && true || false
}

# Use this if you don't want to have to include the "-auth username:password" parameter when making jenkins cli function calls.
# This will make the logged in user alway "Anonymous", even if you do pass in -auth or --user parameters to the cli or api respectively.
# Therefore, the /me api endpoint becomes inaccessible to curl calls, so don't forget to turn security back on.
turnOffSecurity() {
  [ ! -f $JENKINS_HOME/config.xml ] && return 0
  sed -i 's/\(<useSecurity>\)true/\1false/' $JENKINS_HOME/config.xml
  restartJenkins
}

getItemFromSecretsManager() {
  local secretId="$1"
  local item="$2"
  aws secretsmanager get-secret-value \
    --secret-id $secretId \
    --output text \
    --query '{SecretString:SecretString}' | jq '.'$item | sed 's/"//g' 2> /dev/null
}

getAdminPasswordFromSecretsManager() {
  getItemFromSecretsManager 'kuali/jenkins/administrator' 'password'
}

getCredentialFromSecretsManager() {
  local key="$1"
  getItemFromSecretsManager 'kuali/jenkins/credentials' "${key}"
}

# If the admin user has had its password reset, then the JENKINS_HOME/secrets/initialAdminPassword is now no good and the new one needs to be used.
tryAdminPassword() {
  if [ -f "$ADMIN_PASSWORD_RESET" ] ; then
    local password="$(getAdminPasswordFromSecretsManager)"
    if [ $? -gt 0 ] || [ -z "$password" ]; then
      err "No admin secret in the secrets manager service (may have not been added yet or permissions to retrieve are lacking)"
    else
      echo "$password"
    fi
  fi
}

getAdminPassword() {
  if jenkinsIsSecure ; then
    local passwd="$(tryAdminPassword)"
    if [ -n "$passwd" ] ; then
      echo "$passwd"
    elif [ -f $PASSWORD_FILE ] ; then
      cat $PASSWORD_FILE
    else
      err "$PASSWORD_FILE does not exist!"
    fi
  fi
}

getAdminUserCliParm() {
  if jenkinsIsSecure ; then
    echo "-auth admin:$(getAdminPassword)"
  fi
}

getAdminUserApiParm() {
  if jenkinsIsSecure ; then
    echo "--user admin:$(getAdminPassword)"
  fi
}

authenticateForCLI() {
  echo "Setting api token credential environment variables"
  local credfile=$JENKINS_HOME/cli-credentials.sh
  [ ! -f $credfile ] && createTokenFile
  source $credfile
}

# The JENKINS_HOME/secrets/initialAdminPassword file won't appear immediately after initial start up, so wait for it (it takes a couple of seconds)
waitUntilPasswordIsReady() {
  echo "Checking for $PASSWORD_FILE..."
  local counter=0
  while true ; do
    ((counter++))
    if [ -f $PASSWORD_FILE ] ; then
      echo "Found it!"
      passwd=$(cat $PASSWORD_FILE)
      break;
    fi
    echo "Not found! Trying again..."
    if [ $counter -gt 120 ] ; then
      echo "It's been a minute and the file has not turned up."
      echo "Exiting..."
      exit 1
    fi
    sleep .5
  done
}

# Ostensibly, if the jenkins website is ready, then most everything else is ready.
waitUntilServletContainerIsReady() {
  echo 'Checking jenkins status code...'
  local counter=0
  while true ; do
    ((counter++))
    statuscode="$(curl -I -s http://localhost:8080 $(getAdminUserApiParm) | grep HTTP | awk '{print $2}')"
    echo "Jenkins status code: $statuscode"
    if [ "${statuscode:0:2}" == '20' ] ; then
      echo "Status code $statuscode is what we've been waiting for, Jenkins is ready!"
      break;
    fi
    if [ $counter -gt 60 ] ; then
      echo "It's been a minute and jenkins is not ready."
      echo "Exiting..."
      exit 1
    fi
    sleep 1
  done
}

# Files and state get generated as jenkins is starting up. But, it isn't immediate, so a small wait time is needed.
waitUntilJenkinsIsReady() {
  if jenkinsIsSecure ; then
    if [ ! -f $ADMIN_PASSWORD_RESET ] ; then
      waitUntilPasswordIsReady
    fi
  fi
  waitUntilServletContainerIsReady
  # Wait a little more for good measures
  sleep 5
}

startJenkins() {
  echo "Starting Jenkins..."
  sudo service jenkins start
    # Equivalent to:
    # /etc/alternatives/java \
    #   -Dcom.sun.akuma.Daemon=daemonized \
    #   -Djava.awt.headless=true \
    #   -DJENKINS_HOME=/var/lib/jenkins \
    #   -Dhudson.model.DirectoryBrowserSupport.CSP= \
    #   -jar /usr/lib/jenkins/jenkins.war \
    #   --logfile=/var/log/jenkins/jenkins.log \
    #   --webroot=/var/cache/jenkins/war \
    #   --daemon \
    #   --httpPort=8080 \
    #   --debug=5 \
    #   --handlerCountMax=100 \
    #   --handlerCountMaxIdle=20
  waitUntilJenkinsIsReady
}

restartJenkins() {
  echo "Restarting Jenkins..."
  sudo service jenkins restart
  waitUntilJenkinsIsReady
}

getCLI() {
  # https://www.jenkins.io/doc/book/managing/cli/
  # https://wiki.jenkins.io/display/JENKINS//Starting+and+Accessing+Jenkins

  echo "Getting the jenkins-cli.jar..."
  curl http://localhost:8080/jnlpJars/jenkins-cli.jar -o $JENKINS_CLI_JAR
  chown jenkins:jenkins $JENKINS_CLI_JAR
  chmod +x $JENKINS_CLI_JAR

  # Print cli commands
  # java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 help
}

getNewCrumb() {
  curl -s -L \
  --cookie-jar $COOKIE_JAR \
  -X GET http://localhost:8080/crumbIssuer/api/json $(getAdminUserApiParm) \
  | jq '.crumb' | sed 's/"//g' > $CRUMB_FILE
  cat $CRUMB_FILE
}

# You could use the last crumb that was generated, but to do so you must use it in the same session, which means
# saving session (JSESSION) cookies in the curl cookie jar and reusing them (--cookie $COOKIE_JAR --cookie-jar $COOKIE_JAR).
getLastCrumb() {
  cat $CRUMB_FILE
}

# Create a script that can be invoked to put credentials into the environment so as to properly authenticate cli/api calls.
# Exposes the admin users api token by saving it in a file - ok in this setup, but would be insecure in others.
createTokenFile() {
  rm -f $COOKIE_JAR
  local tokenName=${1:-'admin-api-token'}
  local credfile=$JENKINS_HOME/cli-credentials.sh
  echo "Creating $credfile..."
  echo "set +x" > $credfile
  echo "export JENKINS_USER_ID=admin" >> $credfile
  echo "export JENKINS_API_TOKEN=$(getApiToken $tokenName)" >> $credfile
  # cat $credfile
}

getApiToken() {
  local tokenName="$1"
  curl -s -L \
    --cookie $COOKIE_JAR \
    --cookie-jar $COOKIE_JAR \
    -d "newTokenName=$tokenName" \
    -H "Jenkins-Crumb: $(getNewCrumb)" \
    http://localhost:8080/me/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken $(getAdminUserApiParm) \
    | jq '.data.tokenValue' | sed 's/"//g'
}

resetAdminPassword() {
  local cfg="$JENKINS_HOME/users/$(ls -1 $JENKINS_HOME/users | grep 'admin_')/config.xml"
  [ ! -f "$cfg" ] && echo "No such admin user config file: $cfg" && return 1
  echo "Resetting admin password configuration: $cfg"
  local method=${1:-'sha256'}
  local password=$(getAdminPasswordFromSecretsManager) 
  case $method in
    sha256)
      # Use of the sha256 method does not seem to work - cloudbees may have phased it out at some point in the release history.
      local digest=$(echo -n "$password{admin}" | /usr/bin/sha256sum | awk '{print $1}')
      local phash="admin:$digest"
      ;;
    bcrypt)
      if [ -z "$(npm ls | grep 'bcrypt')" ] ; then
        echo "bcrypt not found as a package, installing..."
        if [ -z "$(npm ls | grep 'node-pre-gyp')" ] ; then
          # Without this package installed, the bcrypt install fails with a missing node_modules/bcrypt/lib directory
          # This does not seem to happen if you install bcrypt globally (but you have to navigate use npm link for the 
          # module to be visible within the current node project folder)
          echo "node-pre-gyp not found as a package, installing..."
          npm install node-pre-gyp
          ln -s $(find $(pwd) -type f -iname node-pre-gyp) /usr/bin/node-pre-gyp
          echo "node-pre-gyp version: $(node-pre-gyp --version)"
        fi
        npm install bcrypt
      fi
      javascript="$(cat <<EOF
        const bcrypt = require('bcrypt');
        bcrypt.genSalt(10, 'a', function(err, salt) {
          bcrypt.hash("$password", salt, function(err, hash) {
            if(err) {
              console.log(err.name + ': ' + err.message);
            }
            else {
              console.log('#jbcrypt:', hash);
            }   
          });
        });
EOF
      )"
      local phash=$(node -pe "$javascript" | sed 's/ //g' | tail -1)
      ;;
    esac
    sed -i "s|<passwordHash>.*</passwordHash>|<passwordHash>$phash</passwordHash>|" $cfg                    
    echo "$(grep '<passwordHash>' $cfg)"
    echo "$(date)" > $ADMIN_PASSWORD_RESET
}

login() {
  local username=${1:-'admin'}
  # Use crumb in header, maintain the same session (using session cookie) and post a first-time login attempt
  curl -s -L \
    --cookie $COOKIE_JAR \
    --cookie-jar $COOKIE_JAR \
    -d j_username=$username \
    -d j_password=$(getAdminPassword) \
    -H "Jenkins-Crumb: $(getNewCrumb)" \
    http://localhost:8080/j_spring_security_check $(getAdminUserApiParm)
}

whoAmI() {
  java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 who-am-i
}

IAmLoggedIn() {
  [ -z "$(whoAmI | grep -i 'anonymous')" ] && true || false
}

err(){
  echo "E: $*" >>/dev/stderr
}

# The following characters need to be escaped to maintain valid xml
# "   &quot;
# '   &apos;
# <   &lt;
# >   &gt;
# &   &amp;
escapeXml() {
  echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

# Find out from s3 or secrets manager what the value of a password, token, or key is for a specificed
# credential and inject the value into the xml configuration file for that credential.
injectSecretIntoCredFile() {
  local credxml="$1"

  getCredentialsFileId() {
    grep -oP '(?<=<id>).*(?=</id>)' $credxml
  }

  local id="$(getCredentialsFileId $credxml)"

  # Identify if a credentials xml file is one that has a private ssh key.
  isAPrivateKeyCredentialsFile() {
    [ -n "$(grep -o '<privateKey>' $credxml)" ] && true || false
  }

  # Identify if a credentials xml file is one that has a password.
  isAPasswordCredentialsFile() {
    [ -n "$(grep -o '<password>' $credxml)" ] && true || false
  }

  # Inject the content of a private key for ssh access into a credentials file.
  injectPrivateKeyIntoCredentialsFile() {
    local id="$(getCredentialsFileId $credxml | grep -ioP '(kc)|(rice)')"
    case "$id" in
      kc)
        local keyfile='/var/lib/jenkins/.ssh/bu_github_id_kc_rsa' ;;
      rice)
        local keyfile='/var/lib/jenkins/.ssh/bu_github_id_rice_rsa' ;;
    esac
    if [ -n "$keyfile" ] && [ -f "$keyfile" ] ; then
      echo "Injecting the content of $keyfile into $credxml..."
      start="$(grep -Po '^.*<privateKey>' $credxml)"
      local key="$(cat $keyfile)"
      end="$(grep -Po '</privateKey>.*$' $credxml)"
      echo "${start}${key}${end}" > $credxml
    else
      echo "ERROR! Could not determine private key [keyfile:$keyfile, credentialsFile: $credxml]"
    fi
  }

  # Look up and inject a password value into a name/password credential file
  injectPrivatePasswordIntoCredentialsFile() {
    case "$id" in
      'admin')
        local password="$(getAdminPasswordFromSecretsManager)"
        ;;
      'credentials.kualico.github.pat')
        local password="$(getCredentialFromSecretsManager '"credentials-kualico-github-pat"."password"')"
        ;;
      'credentials.kualico.github')
        local password="$(getCredentialFromSecretsManager '"credentials-kualico-github"."password"')"
        ;;
      'credentials.kualico.dockerhub')
        local password="$(getCredentialFromSecretsManager '"credentials-kualico-dockerhub"."password"')"
        ;;
    esac
    if [ -n "$password" ] ; then
      echo "Injecting the password for $id into $credxml..."
      start="$(grep -Po '^.*<password>' $credxml)"
      password="$(escapeXml "$password")"
      end="$(grep -Po '</password>.*$' $credxml)"
      echo "${start}${password}${end}" > $credxml
    else
      echo "ERROR! Could not determine password of $id for $credxml"
    fi
  }

  # Look up and inject into the specified credentials file the value of a secret.
  injectPrivateSecretIntoCredentialsFile() {
    case "$id" in
      'credentials.bu.github.token')
        local secret="$(getCredentialFromSecretsManager '"credentials-bu-github-token"."token"')"
        ;;
      'credentials.newrelic.license.key')
        local secret="$(getCredentialFromSecretsManager '"credentials-newrelic-license-key"."token"')"
        ;;
    esac
    if [ -n "$secret" ] ; then
      echo "Injecting the secret for $id into $credxml..."
      start="$(grep -Po '^.*<secret>' $credxml)"
      secret="$(escapeXml "$secret")"
      end="$(grep -Po '</secret>.*$' $credxml)"
      echo "${start}${secret}${end}" > $credxml
    else
      echo "ERROR! Could not determine secret of $id for $credxml"
    fi
  }


  if isAPrivateKeyCredentialsFile ; then
    echo "$credxml needs a private key (id=$id)."
    injectPrivateKeyIntoCredentialsFile
  elif isAPasswordCredentialsFile ; then
    echo "$credxml needs a password (id=$id)."
    injectPrivatePasswordIntoCredentialsFile
  else
    echo "$credxml needs a secret (id=$id)."
    injectPrivateSecretIntoCredentialsFile
  fi
}