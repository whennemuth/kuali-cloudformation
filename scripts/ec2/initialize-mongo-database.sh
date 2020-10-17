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
  local using='true'
  if isLocalHost "$DNS_NAME" ; then
    using='false'
  elif [ "${DNS_NAME,,}" == 'local' ] || [ -z "$DNS_NAME" ] ; then
    using='false'
  elif [ -z "$SHIB_HOST" ] ; then
    SHIB_HOST="$(getValueFromEnvVarFile 'SHIB_HOST')"
    [ -z "$SHIB_HOST" ] && using='false'
  fi
  [ $using == 'true' ] && true || false
}


runCommand() {
  echo $cmd
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
  
  if ! shibbolethDataAvailable ; then
    echo "Updating Incommons: No shibboleth data available, cancelling... "
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
      # Clear out the incommons collecion so it can be repopulated.
      runCommand "$(getMongoParameters) --quiet --eval 'db.getCollection("incommons").remove({})'"
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
  getInstitutionRESTCall
}


updateInstitutions() {
  echo "Updating institutions document..."
  local provider="kuali"
  if shibbolethDataAvailable ; then
    provider="saml"
  fi
	local cmd=$(cat << EOF
	$(getMongoParameters) \
    --quiet \
	  --eval 'db.getCollection("institutions")
	    .updateOne(
	      { "name":"Kuali" },        
        {
          \$set: {
            "provider": "$provider",
            "signInExpiresIn" : 1209600000,
            "features.impersonation": true,
            "features.apps": {
              "users": true,
              "research": true
            },
            "idps": [
              {
                "idp": "$SHIB_IDP_METADATA_URL",
                "eppn": "buPrincipal",
                "name": "bu"
              }
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


createUsersCollection() {
 getInstitutionRESTCall
}


updateUsers() {
  echo 'TBD'
}


# A brand new core-development mongo database will not contain the "institutions" and "users" collections.
# Usually, browsing the application and logging in for the first time as admin will trigger the creaton of these
# two collections, but you can accomplish the same by making a rest call to the institution module.
getInstitutionRESTCall() {
  local containerIpAddress=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cor-main)
  curl http://$containerIpAddress:3000/api/v1/institution
}


updateCore() {
  for collection in $COLLECTIONS ; do
    case "${collection,,}" in
      incommons)
        # Updating a non-existent collection in mongodb will cause it to be auto-created, so no need to explicitly create it.
        updateInCommons ;;
      institutions)
        if ! mongoCollectionExists 'institutions' ; then
          createInstitutionsCollection
        fi
        updateInstitutions ;;
      users)
        if ! mongoCollectionExists 'users' ; then
          createUsersCollection
        fi
        updateUsers ;;
    esac
  done
}


initialize() {
  task="${1,,}"
  [ -z "$task" ] && task="${TASK,,}"
  [ -z "$MONGO_URI" ] && [ "${task,,}" != 'test' ] && echo "ERROR! MONGO_DBNAME parameter missing, mongodb initialization cancelled." && exit 1
  if [ "${DNS_NAME,,}" == 'local' ] || [ -z "$DNS_NAME" ] ; then
    # There is no route53 or public load balancer name - a single ec2 is all alone and can only be reached if 
    # the private subnet it is sitting in is linked to a bu network through a transit gateway attachment
    # and the user has logged on to that bu network before attempting to reach the application, knowing 
    # the private ip address of the ec2 instance and browsing to the app with it: https://[private ip]/kc.
    DNS_NAME=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  fi
  SHIB_IDP_METADATA_URL=https://$SHIB_HOST/idp/shibboleth
}


initialize $1

case "$task" in
  test)
    # getMongoParameters
    # getValueFromEnvVarFile 'SHIB_HOST'
    # updateInCommons
    updateInstitutions
    ;;
  update-core)
    updateCore
    ;;
esac