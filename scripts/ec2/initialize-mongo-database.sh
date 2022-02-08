#!/bin/bash

# Construct the parameter list for connecting to the mongo database.
# There are several variations on how this is done depending on MONGO_URI
getMongoParameters() {
  local uri=$MONGO_URI
  local dbname=$MONGO_DBNAME
  local replicaset=$MONGO_REPLICASET
  local user=$MONGO_USER
  local password=$MONGO_PASS

  local host=""
  local querystring=""

  # Break down the uri into parts (if possible). It will be reconstituted later.
  if [ ! "$uri" ] ; then
    host='localhost'
  else
    # Temporarily strip off any leading "mongodb://" prefix
    uri="$(echo $uri | sed 's/mongodb:\/\///')"
    if [ ${uri,,} == 'localhost' ] || [ $uri == '127.0.0.1' ] ; then
      host=${uri,,}
    else
      host=$(echo $uri | cut -s -d'/' -f1)
      local db=$(echo $uri | cut -s -d'/' -f2)
      if [ $host ] ; then
        if [ $db ] ; then
          querystring=$(echo $db | cut -s -d'?' -f2)
          if [ ! $dbname ] ; then
            dbname=$(echo $db | cut -s -d'?' -f1)
            [ ! $dbname ] && dbname=$db
          fi
        fi
      else
        host=$(echo $db | cut -s -d'?' -f1)
        querystring=$(echo $db | cut -s -d'?' -f2)
        if [ ! $host ] ; then
          host=$uri
          querystring=$(echo $host | cut -s -d'?' -f2)
          if [ $querystring ] ; then
            host=$(echo $host | cut -s -d'?' -f1)
          fi
        fi
      fi
    fi
  fi

  # Validate database name
  if [ ! $dbname ] ; then
    echo "ERROR! getMongoParameters: mongo database name not specified." && return 1
  fi

  # Determine if uri is for localhost
  isLocalHost "$host" && local localhost="true"

  # Put the uri back together again in a standard format.
  uri="mongodb://$host/$dbname"
  if [ $querystring ] ; then
    local qs=""
    for s in $(echo $querystring | cut -d'&' -f1- --output-delimiter=' ') ; do 
      local name="$(echo $s | cut -s -d'=' -f1)"
      local value="$(echo $s | cut -s -d'=' -f2)"
      # Flag the fact that replicaset is in the querystring so it can be made the first querystring argument, which
      # is what the mongo command line client seems to want.
      [ "${name,,}" == "replicaset" ] && local rs="$value" && continue;
      # Exclude ssl as a parameter on the querystring. The mongo command line client wants it as an --ssl switch instead.
      # NOTE: Mongoose needs it as a querystring, which is why it would appear in the querystring in the first place.
      [ "${name,,}" == "ssl" ] && [ "${value,,}" == "true" ] && local ssl="true" && continue;
      [ $qs ] && qs="$qs&$name=$value" || qs="$name=$value"
    done
    [ $replicaset ] && local rs="$replicaset"
    if [ $rs ] ; then
      [ $qs ] && qs="replicaSet=$rs&$qs" || qs="replicaSet=$rs"
    fi
    [ $qs ] && uri="$uri?$qs"
  fi 

  # Build the mongo command with parameters based on the type of host.
  # local cmd="mongo --verbose "
  local cmd="mongo "
  if [ $localhost ] || [ ! "$password" ]; then
    cmd="$cmd --host \"$uri\""
  else
    cmd="$cmd --host \"$uri\""
    [ $ssl ] && cmd="$cmd --ssl"
    cmd="$cmd --authenticationDatabase admin"
    cmd="$cmd --username $user"
    cmd="$cmd --password $password"
  fi

  printf "$cmd"
  return 0
}


getValueFromEnvVarFile() {
  local envname=$1

  if [ -f "$ENV_FILE_FROM_S3_CORE" ] ; then
    local retval="$(eval 'source $ENV_FILE_FROM_S3_CORE 2> /dev/null && echo $'$envname'')"
    if [ -z "$retval" ] ; then 
      local exportfile="$(dirname $ENV_FILE_FROM_S3_CORE)/export.sh"
      if [ -f "$exportfile" ] ; then
        retval="$(eval 'source '$exportfile' 2> /dev/null && echo $'$envname'')"
      fi
    fi
  fi

  echo "$retval"
}


isLocalHost() {
  # Determine if uri is for localhost
  retval=$(echo "${1,,}" | grep -iP '((localhost)|(127\.0\.0\.1))(:\d+)?')
}


shibbolethDataAvailable() {
  if [ -z "$SHIB_HOST" ] ; then
    SHIB_HOST="$(getValueFromEnvVarFile 'SHIB_HOST')"
  fi
  [ -n "$SHIB_HOST" ] && true || false
}

shibbolethDataApplicable() {
  if shibbolethDataAvailable ; then
    [ "$USING_ROUTE53" == 'true' ] && applicable='true'
  fi
  [ -n "$applicable" ] && true || false
}


runCommand() {
  echo "$cmd"
  [ "${DEBUG,,}" != 'true' ] && [ ! "${1,,}" == 'ignore-debug' ] && eval $cmd
}


mongoCollectionExists() {
  local collectionName=$1
  cmd=$(cat << EOF
	match=\$($(getMongoParameters) \
    --quiet \
    --eval 'db.runCommand( { listCollections: 1.0, nameOnly: true } )' | grep "$collectionName"
    )
EOF
	)
  runCommand
  [ "$match" ] && true || false
}


updateInCommons() {
  
  if ! shibbolethDataApplicable ; then
    echo "No shibboleth data available, cannot update incommons collection, cancelling... "
    return 0
  fi

  # What does the shibboleth IDP say the cert is?
  cert=$(
    curl $SHIB_IDP_METADATA_URL \
      | awk '/<ds:X509Certificate>/,/<\/ds:X509Certificate>/' \
      | awk '!/.*ds:X509Certificate.*/' \
      | awk '{print}' ORS=''
  )

  if [ -n "$cert" ] ; then
    if mongoCollectionExists 'incommons' ; then
      echo "Clearing out the incommons collecion and repopulating..."
      local cmd="$(getMongoParameters) --quiet --eval 'db.getCollection(\"incommons\").remove({})'"
      runCommand "$cmd"
    fi
    local cmd=$(cat << EOF
    $(getMongoParameters) \
      --quiet \
      --eval 'db.getCollection("incommons")
        .insertOne({ 
          "idp": "$SHIB_IDP_METADATA_URL", 
          "cert": "$cert", 
          "entryPoint": "https://$SHIB_HOST/idp/profile/SAML2/Redirect/SSO" 
        }
      )'
EOF
    )
    runCommand "$cmd"
  else
    echo "WARNING! Could not acquire shibboleth idp certificate value from $SHIB_IDP_METADATA_URL"
  fi
}

createInstitutionsCollection() {
  echo 'Triggering Creating institution collection creation...'
  makeCollectionRESTCall 'api/v1/institution'
}

createUsersCollection() {
  echo 'Triggering Creating users collection creation...'
  makeCollectionRESTCall 'api/v1/users'
}

getIdp() {
  if shibbolethDataApplicable ; then
    cat << EOF
    {
      "idp": "$SHIB_IDP_METADATA_URL",
      "eppn": "buPrincipal",
      "name": "bu"
    }
EOF
  fi
}

updateInstitutions() {
  echo "Updating institutions document..."
  local provider="kuali"
  local issuer="localhost"
  local idp="$(getIdp)"
  if [ -n "$idp" ] ; then
    provider="saml"
    issuer="$ENTITY_ID"
  fi
  # NOTE: samlIssuerUrl is looked for here first, and the fallback value would be what you set for auth.samlIssuerUrl in local.js
	local cmd=$(cat << EOF
	$(getMongoParameters) \
    --quiet \
	  --eval 'db.getCollection("institutions")
	    .updateOne(
	      { "name":"Kuali" },        
        {
          \$set: {
            "provider": "$provider",
            "samlIssuerUrl": "$issuer",
            "signInExpiresIn" : 1209600000,
            "features.impersonation": true,
            "features.apps": {
              "users": true,
              "research": true
            },
            "idps": [
              $idp
            ],
            "validRedirectHosts": [
              "$DNS_NAME",
              "localhost",
              "127.0.0.1"
            ]
          }
        }           
      )'
EOF
	)
  runCommand "$cmd"
}

# Issue an ssm command to the mongo ec2 instance to import users.
importUsers() {
  echo "Importing users..."
  if [ -z "$MONGO_INSTANCE_ID" ] ; then
    echo "ERROR! Expected MONGO_EC2_ID environment variable but was not set."
    echo "Cannot send ssm command to import users."
    return 0
  elif [ "${USER_IMPORT_MONGODB,,}" == 'true' ] ; then
    local args="mongodb $BASELINE"
  elif [ -z "$USER_IMPORT_FILE" ] ; then
    local args="s3 $USER_IMPORT_FILE"
  else
    echo "No mongo database or s3 file specified for user import!"
    echo "Users collection in cor-main will have only the admin user."
    return 0
  fi

  local cmd="aws --region \"${AWS_DEFAULT_REGION:-"us-east-1"}\" ssm send-command \
    --instance-ids \"$MONGO_INSTANCE_ID\" \
    --document-name \"AWS-RunShellScript\" \
    --comment \"Command issued to mongo ec2 to import users to cor-main container\" \
    --parameters commands=\"sh -x /opt/kuali/import.cor-main-users.sh $args 2>&1 > /var/log/import-users.log\" \
    --output text \
    --query \"Command.CommandId\""

  echo "Sending ssm command to mongo ec2 instance to run script that imports users:"
  echo " "
  echo $cmd
  echo " "
  eval "$cmd"
}

getToken() {
  local serverIP="$1"
  local port="$2"
  [ -n "$TOKEN" ] && echo "$TOKEN" && return 0
  TOKEN="$(curl \
    -X POST \
    -H "Authorization: Basic $(echo -n "admin:admin" | base64 -w 0)" \
    -H "Content-Type: application/json" \
    "http://${serverIP}:${port}/api/v1/auth/authenticate" \
    | sed 's/token//g' \
    | sed "s/[{}\"':]//g" \
    | sed "s/[[:space:]]//g")"
  echo "$TOKEN"
}

# A brand new core-development mongo database will not contain the "institutions" and "users" collections.
# Usually, browsing the application and logging in for the first time as admin will trigger the creaton of these
# two collections, but you can accomplish the same by making a rest call to the institution module.
makeCollectionRESTCall() {

  local path="$1"

  echo "Making $path REST call to cor-main container to trigger auto-create of the associated collection..."

  # Using the name of the cor-main docker container, set a global variable to the value of its ID
  setContainerId() {
    CONTAINER_SHORT_NAME=${1:-'cor-main'}
    CONTAINER_ID=$(docker ps -f name=${CONTAINER_SHORT_NAME} -q 2> /dev/null)
    echo "docker ps -f name=${CONTAINER_SHORT_NAME} -q ..."
    echo "Container \"$CONTAINER_SHORT_NAME\" ID: $CONTAINER_ID"
    if [ -z "$CONTAINER_ID" ] && [ -z "$1" ]; then
      # If the container is not named "cor-main", then we are running in an ecs stack, which names containers after a portion of the docker.
      # image name. The -f filter will return partial matches, so as long as the container name has "kuali-core" in it, the ID will be found.
      setContainerId 'kuali-core'
    fi
    [ -n "$CONTAINER_ID" ] && true || false
  }

  # Inspect the cor-main docker container for its network ip address and set a global variable with its value.
  setContainerIpAddress() {
    for attempt in {1..240} ; do
      echo "$(whoami) running docker ps ..."
      docker ps
      if setContainerId ; then
        CONTAINER_IP_ADDRESS=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID 2> /dev/null)
        break;
      fi
      echo "Looks like core container isn't running yet, attempt $((attempt+1))..."
      sleep 5
    done
    [ -z "$CONTAINER_IP_ADDRESS" ] && echo "ERROR! It's been an 20 minutes with no success getting the core docker container ID. Quitting."
    [ -n "$CONTAINER_IP_ADDRESS" ] && true || false
  }

  # Hit the cor-main api with the basic path to trigger the app to auto-create the collection if it's not there.
  attemptCurl() {
    local retval=$(curl http://$CONTAINER_IP_ADDRESS:3000/$path 2>&1)
    local code=$?
    [ $code -ne 0 ] && return $code
    if [ -n "$(echo "$retval" | grep -i 'Unauthorized')" ] ; then
      # Can't perform a GET, so must do a POST with a bearer token
      curl \
        -i \
        -X GET \
        "http://$CONTAINER_IP_ADDRESS:3000/$path" \
        --header "Content-Type: application/json" \
        --header "Authorization: Bearer $(getToken $CONTAINER_IP_ADDRESS '3000')"
    fi
  }

  makeRESTCall() {
    for attempt in {1..30} ; do
      echo "Attempting $path REST call to $CONTAINER_SHORT_NAME container to trigger auto-create of institutions and/or users collection(s)..."
      echo "curl http://$CONTAINER_IP_ADDRESS:3000/$path"
      local reply=$(attemptCurl)
      local code=$?
      echo "$code: $reply"
      if [ $code -ne 0 ] || [ -n "$(grep -i 'connection refused' <<< $reply)" ] ; then
        echo "Looks like $CONTAINER_SHORT_NAME container isn't ready yet, attempt $((attempt+1))..."
        sleep 2
      else
        return 0
      fi
    done
    echo "It's been a minute with no success contacting the $CONTAINER_SHORT_NAME container. Quitting."
  }

  if setContainerIpAddress ; then
    makeRESTCall
  fi
}


updateCore() {
  for collection in $COLLECTIONS ; do
    case "${collection,,}" in
      incommons)
        # Updating a non-existent collection in mongodb will cause it to be auto-created, so no need to explicitly create it.
        updateInCommons ;;
      institutions)
        if ! mongoCollectionExists 'institutions' ; then
          triggerCollectionCreation 
        fi
        updateInstitutions ;;
      users)
        if ! mongoCollectionExists 'users' ; then
          createUsersCollection
        fi
        importUsers ;;
    esac
  done
}


initialize() {
  task="${1,,}"
  [ -z "$task" ] && task="${TASK,,}"
  if [ -z "$MONGO_URI" ] && [ "${task,,}" != 'test' ] ; then
    echo "MONGO_URI parameter missing. This indicates the mongodb is already configured and populated."
    echo "Mongodb initialization/configuration cancelled."
    exit 0
  fi
  if [ "${DNS_NAME,,}" == 'local' ] || [ -z "$DNS_NAME" ] ; then
    # There is no route53 or public load balancer name - a single ec2 is all alone and can only be reached if 
    # the private subnet it is sitting in is linked to a bu network through a transit gateway attachment
    # and the user has logged on to that bu network before attempting to reach the application, knowing 
    # the private ip address of the ec2 instance and browsing to the app with it: https://[private ip]/kc.
    # Dummy (Institutions.provider='kuali') authentication is the only option.
    DNS_NAME=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  else
    DNS_NAME=$(echo "$DNS_NAME" | sed -E 's/\.$//') # Strip off trailing dot (if exists).
    # If we are using route53, ssl certificate for and an official dns name, which means we don't have to use dummy auth,
    # that is provided the institutions and incommons collections tables are properly updated.
  fi
  [ -z "$USING_ROUTE53" ] && USING_ROUTE53='false'
  if shibbolethDataApplicable ; then
    SHIB_IDP_METADATA_URL=https://$SHIB_HOST/idp/shibboleth
  fi
  [ -z "$ENTITY_ID" ] && ENTITY_ID="https://$DNS_NAME/shibboleth"

  echo " "
  echo "-----------------------------------------------------"
  echo "    PARAMETERS:"
  echo "-----------------------------------------------------"
  echo "TASK: $TASK"
  echo "DNS_NAME: $DNS_NAME"
  echo "USING_ROUTE53: $USING_ROUTE53"
  echo "ENTITY_ID: $ENTITY_ID"
  echo "DEBUG: $DEBUG"
  echo "COLLECTIONS: $COLLECTIONS"
  echo "BASELINE: $BASELINE"
  echo "LANDSCAPE: $LANDSCAPE"
  echo "SHIB_HOST: $SHIB_HOST"
  echo "AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
  echo "MONGO_INSTANCE_ID: $MONGO_INSTANCE_ID"
  echo "MONGO_URI: $MONGO_URI"
  echo "USER_IMPORT_MONGODB: $USER_IMPORT_MONGODB"
  echo "USER_IMPORT_FILE: $USER_IMPORT_FILE"
  echo "ENV_FILE_FROM_S3_CORE: $ENV_FILE_FROM_S3_CORE"
  echo " "
}


initialize $1

case "$task" in
  test)
    # getMongoParameters
    # getValueFromEnvVarFile 'SHIB_HOST'
    updateInCommons
    # updateInstitutions
    ;;
  update-core)
    updateCore
    ;;
  import-users)
    importUsers
    ;;
esac