#!/bin/bash

# Acquire the kc-config.xml file, name=value pair files for docker container environment variables, etc from s3
downloadConfigsFromS3() {

  echo "Downloading all configurations for containers from the s3 bucket, baseline landscape $BASELINE"
  
  [ ! -d /opt/kuali/s3 ] && mkdir -p /opt/kuali/s3
  cd /opt/kuali/s3
  aws s3 sync --delete \
    --exclude "*" \
    --include "core/*" \
    --include "portal/*" \
    --include "pdf/*" \
    --include "kc/kc-config.xml" \
    s3://${TEMPLATE_BUCKET_NAME}/$BASELINE/ .
  # aws s3 cp s3://${TEMPLATE_BUCKET_NAME}/samlMeta.xml ./core/
  aws s3 cp s3://${TEMPLATE_BUCKET_NAME}/rice.cer ./kc/
  aws s3 cp s3://${TEMPLATE_BUCKET_NAME}/rice.keystore ./kc/
}

# The name=value pair files acquired from s3 will have some default entries whose actual values could 
# not have been known ahead of time, but can be looked up now and copied over the defaults here.
processEnvironmentVariableFiles() {
  local common_name="$(getCommonName)"

  # Loop over the collection of environment.variables.s3 files.
  for f in $(env | grep 'ENV_FILE_FROM_S3') ; do
    envfile="$(echo $f | cut -d'=' -f2)"
    if grep -iq 'pdf' <<<"$envfile" ; then
      app='pdf'
    elif grep -iq 'portal' <<<"$envfile" ; then
      app='portal'
    elif grep -iq 'core' <<<"$envfile" ; then
      app='core'
    fi

    # Replace the standard kuali-research-[env].bu.edu references with the dns address of this instances load balancer.
    # sed -i -r "s/kuali-research.*.bu.edu/$common_name/g" "$envfile"
    sed -i -r 's/[a-z]+\.kuali-research.bu.edu/'$common_name'/g' "$envfile"

    # Make changes to environment variable values:
    # 1) Simplify the mongo connection data if localhost
    # 2) Eliminate shibboleth-related entries if localhost or not using known dns with hosted zone
    # 3) Make sure values are set that permit self-signed certificates to be accepted by the applicable apps.
    #    Assumes that if route 53 is not in use, then a load balancer or ec2 instance ip is the app address, which entails self-signed cert.
    case "$app" in
      core)
        if [ -n "$MONGO_EC2_IP" ] || [ -n "$MONGO_URI" ]; then
          removeLine $envfile 'MONGO_PRIMARY_SHARD'
          removeLine $envfile 'MONGO_USER'
          removeLine $envfile 'MONGO_PASS'
          setNewValue $envfile 'MONGO_URI' "mongodb://${MONGO_EC2_IP}:27017/core-development"
          # or... (Would not be setting both MONGO_EC2_IP and MONGO_URI at the same time).
          checkValue $envfile 'MONGO_URI'
        fi

        if [ "${USING_ROUTE53,,}" != 'true' ] ; then
          removeLine $envfile 'SHIB_HOST'
          removeLine $envfile 'BU_LOGOUT_URL'
        else
          # Unless explicit values are provided, shibboleth is out of the picture and core will be its own IDP, and logout url will default to "/apps"
          checkValue $envfile 'SHIB_HOST'
          checkValue $envfile 'BU_LOGOUT_URL'
        fi

        checkValue $envfile 'CORE_HOST' "$common_name"
        # 99% of the time, what's in the env file for the following values already will do, but still providing the option to override here.
        checkValue $envfile 'LANDSCAPE'
        checkValue $envfile 'UPDATE_INSTITUTION'
        checkValue $envfile 'SMTP_HOST'
        checkValue $envfile 'SMTP_PORT'
        checkValue $envfile 'JOBS_SCHEDULER'
        checkValue $envfile 'REDIS_URI'
        checkValue $envfile 'SERVICE_SECRET_1'
        checkValue $envfile 'SERVICE_SECRET_2'
        checkValue $envfile 'AWS_DEFAULT_REGION'
        checkValue $envfile 'START_CMD'
        ;;
      pdf)
        if [ -n "$MONGO_EC2_IP" ] || [ -n "$SPRING_DATA_MONGODB_URI" ] ; then
          setNewValue $envfile 'SPRING_DATA_MONGODB_URI' "mongodb://${MONGO_EC2_IP}:27019/test?retryWrites=true&w=majority"
          # or... (Would not be setting both MONGO_EC2_IP and SPRING_DATA_MONGODB_URI at the same time).
          checkValue $envfile 'SPRING_DATA_MONGODB_URI'
        fi
        if [ "${USING_ROUTE53,,}" == 'false' ] ; then
          setNewValue $envfile 'ALLOW_SELF_SIGNED_SSL' 'true'
        fi
        if [ -n "$AWS_S3_BUCKET" ] ; then
          setNewValue $envfile 'AWS_S3_BUCKET' "$AWS_S3_BUCKET"
          setNewValue $envfile 'AWS_S3_ENABLED' 'true'
        elif [ "$AWS_S3_ENABLED" != 'false' ] ; then
          setNewValue $envfile 'AWS_S3_BUCKET' "kuali-pdf-${LANDSCAPE}"
          setNewValue $envfile 'AWS_S3_ENABLED' 'true'
        fi
        checkValue $envfile 'LANDSCAPE'
        checkValue $envfile 'AWS_S3_BUCKET' $PDF_BUCKET_NAME
        checkValue $envfile 'AUTH_ENABLED' 
        checkValue $envfile 'AUTH_BASEURL' "$common_name"
        checkValue $envfile 'AUTH_SERVICE2SERVICE_SECRETS'
        checkValue $envfile 'MONGO_ENABLED'
        checkValue $envfile 'AWS_REGION'
        ;;
      portal)
        if [ -n "$MONGO_EC2_IP" ] || [ -n "$MONGODB_URI" ]; then
          # removeLine $envfile 'MONGODB_USERNAME'
          # removeLine $envfile 'MONGODB_PASSWORD'
          setNewValue $envfile 'MONGODB_URI' "mongodb://${MONGO_EC2_IP}:27018/res-dashboard"
          # or... (Would not be setting both MONGO_EC2_IP and MONGODB_URI at the same time).
          checkValue $envfile 'MONGODB_URI'
        fi
        if [ "${USING_ROUTE53,,}" == 'false' ] ; then
          setNewValue $envfile 'NODE_TLS_REJECT_UNAUTHORIZED' '0'
        fi
        if [ -n "$CORE_AUTH_BASE_URL" ] ; then
          setNewValue $envfile 'CORE_AUTH_BASE_URL' "$CORE_AUTH_BASE_URL"
        else
          setNewValue $envfile 'CORE_AUTH_BASE_URL' "https://${common_name}"
        fi
        if [ -n "$RESEARCH_URL" ] ; then
          setNewValue $envfile 'RESEARCH_URL' "$RESEARCH_URL"
        else
          setNewValue $envfile 'RESEARCH_URL' "https://${common_name}/kc"
        fi
        if [ -n "$PORTAL_HOST" ] ; then
          setNewValue $envfile 'PORTAL_HOST' "$PORTAL_HOST"
        else
          setNewValue $envfile 'PORTAL_HOST' "https://${common_name}/kc"
        fi
        checkValue $envfile 'MONGODB_USERNAME'
        checkValue $envfile 'MONGODB_PASSWORD'
        checkValue $envfile 'MONGO_DB_NAME'
        checkValue $envfile 'LANDSCAPE'
        checkValue $envfile 'CACHE_RES_REQUESTS'
        checkValue $envfile 'ELASTICSEARCH_URL'
        checkValue $envfile 'ELASTICSEARCH_INDEX_NAME'
        checkValue $envfile 'LOG_LEVEL'
        checkValue $envfile 'NODE_ENV'
        checkValue $envfile 'PORT'
        checkValue $envfile 'REQUEST_LOG_LEVEL'
        checkValue $envfile 'RESEARCH_SECRET'
        checkValue $envfile 'START_CMD'
        checkValue $envfile 'USE_LEGACY_APIS'
        ;;
    esac

    if [ "${CREATE_EXPORT_FILE,,}" == 'true' ] ; then
      # Create the export.sh file
      createExportFile "$envfile"
    fi
  done
}


# Create a script to export all environment variables in the mounted directory before starting node
createExportFile() {
  # Turn a name=value line into an "export name='value'" line
  getLineExport() {
    local line=$(echo -n "$1" | xargs) # Use xargs to trim the line.
    # Return an empty string if the line is a properties file comment
    [ "${line:0:1}" == "#" ] && echo "" && exit 0;
    [ -z "$line" ] && echo "" && exit 0;
    if [ -n "$(echo $testline | grep -P '\x22')" ] ; then
      echo "export $line"
    else
      # Put double quotes around the exported variable value
      echo "export $(echo $line | sed 's/=/="/1')\""
    fi
  }
  
  local envfile="$1"
  if [ ! -f $envfile ] ; then
    echo "ERROR! MISSING $envfile"
    exit 1
  else
    cd $(dirname $envfile)
    rm -f export.sh
    echo "Creating $(pwd)/export.sh..."
    while read line ; do
      expline="$(getLineExport "$line")" 
      [ -z "$expline" ] && continue
      prop=$(echo "$line" | cut -f1 -d '=')
      # Override some of the existing environment variables
      # [ "${prop^^}" == "SHIB_HOST" ] && expline="export SHIB_HOST="
      # [ "${prop^^}" == "ROOT_DIR" ]  && expline="export ROOT_DIR=/var/core-temp"
      echo "Setting env var $prop" 
      echo "$expline" >> export.sh
    done < $envfile
    
    # In case the file from s3 originated on a windows file system, remove return carriage chars
    sed -i 's/\r//g' export.sh
  fi
}


# The kc-config.xml file downloaded from s3 will have placeholders for certain parameter values that
# could not have been known ahead of time, but can be looked up now and filled out in the file.
# EXAMPLE kc-config.xml SNIPPET:
#   <param name="application.host">APPLICATION_HOST</param>
#   <param name="datasource.url">jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS_LIST=(FAILOVER=OFF)(LOAD_BALANCE=OFF)(ADDRESS=(PROTOCOL=TCP)(HOST=KUALI_DB_HOST)(PORT=1521)))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=kuali)))</param>
#   <param name="datasource.username">KUALI_DB_USERNAME</param>
#   <param name="datasource.password">KUALI_DB_PASSWORD</param>
processKcConfigFile() {
  sed -i "s/APPLICATION_HOST/$(getCommonName)/"         /opt/kuali/s3/kc/kc-config.xml
  sed -i "s/KUALI_DB_HOST/$(getRdsHostname)/"           /opt/kuali/s3/kc/kc-config.xml
  sed -i "s/KUALI_DB_USERNAME/$(getRdsAppUsername)/"    /opt/kuali/s3/kc/kc-config.xml
  sed -i "s/KUALI_DB_PASSWORD/$(getRdsAppPassword)/"    /opt/kuali/s3/kc/kc-config.xml
}

# There is no environment variables file downloaded from s3 for the kc docker container to mount to.
# Instead, these variables were put into the environment of this running script, so put them as name=value pairs into a file for mounting.
createKcEnvironmentVariableFile() {
  echo "LANDSCAPE=$LANDSCAPE" > $TARGET_FILE
  echo "NEW_RELIC_LICENSE_KEY=$NEW_RELIC_LICENSE_KEY" >> $TARGET_FILE
  echo "NEW_RELIC_AGENT_ENABLED=$NEW_RELIC_AGENT_ENABLED" >> $TARGET_FILE
  echo "NEW_RELIC_INFRASTRUCTURE_ENABLED=$NEW_RELIC_INFRASTRUCTURE_ENABLED" >> $TARGET_FILE
  echo "JAVA_ENV=$JAVA_ENV" >> $TARGET_FILE
  echo "DNS_NAME=$DNS_NAME" >> $TARGET_FILE

  if [ "${CREATE_EXPORT_FILE,,}" == 'true' ] ; then
    # Create the export.sh file
    createExportFile "$TARGET_FILE"
  fi
}

# echo out the base subdomain address that the kuali applications are reachable on.
getCommonName() {
  if [ "${DNS_NAME,,}" == 'local' ] || [ -z "$DNS_NAME" ] ; then
    # There is no route53 or public load balancer name - a single ec2 is all alone and can only be reached if 
    # the private subnet it is sitting in is linked to a bu network through a transit gateway attachment
    # and the user has logged on to that bu network before attempting to reach the application, knowing 
    # the private ip address of the ec2 instance and browsing to the app with it: https://[private ip]/kc.
    local cn=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  else
    local cn="${DNS_NAME}"
  fi
  echo $cn | cut -d'/' -f3 # Strips off the "http://" portion and trailing "/"
}

removeLine() {
  local file=$1
  local name=$2
  local comment=$3
  if [ "$comment" == 'true' ] ; then
    sed -i 's/^\([^#]*'$name'.*=.*\)/# \1/' $file
  else 
    sed -i '/.*'$name'.*=.*/d' $envfile
  fi
}

setNewValue() {
  local file=$1
  local name=$2
  local newvalue="$3"
  local comment=$4
  removeLine $file $name $comment
  echo "$name=$newvalue" >> $file
}

checkValue() {
  local file=$1
  local name=$2
  local value="$3"
  [ -z "$value" ] &&  eval "local value=\$$name"
  [ -z "$value" ] && return 0
  setNewValue $file $name "$value"
}

getRdsHostname() {
  [ -n "$RDS_HOSTNAME" ] && echo "$RDS_HOSTNAME" && return 0
  local rdsArn=$(
    aws resourcegroupstaggingapi get-resources \
      --resource-type-filters rds \
      --tag-filters 'Key=Name,Values=kuali-oracle-'$LANDSCAPE \
      --output text \
      --query 'ResourceTagMappingList[].{ARN:ResourceARN}' | grep -vi 'snapshot' 2> /dev/null
  )
  if [ -n "$rdsArn" ] && [ "${rdsArn,,}" != 'none' ] ; then
    RDS_HOSTNAME=$(
      aws rds describe-db-instances \
        --db-instance-identifier $rdsArn \
        --output text \
        --query 'DBInstances[].{addr:Endpoint.Address}' 2> /dev/null
      )
  fi
  echo $RDS_HOSTNAME
}

getRdsSecret() {
  [ -n "$RDS_SECRET" ] && echo "$RDS_SECRET" && return 0
  local type="$1"
  RDS_SECRET=$(
    aws secretsmanager get-secret-value \
      --secret-id kuali/$BASELINE/kuali-oracle-rds-${type}-password \
      --output text \
      --query '{SecretString:SecretString}' 2> /dev/null
    )
    echo $RDS_SECRET
}

getRdsAppUsername() {
  [ -n "$RDS_USERNAME" ] && echo "$RDS_USERNAME" && return 0
  RDS_USERNAME=$(getRdsSecret 'app' | jq '.username' | sed 's/"//g')
  echo $RDS_USERNAME
}

getRdsAppPassword() {
  [ -n "$RDS_PASSWORD" ] && echo "$RDS_PASSWORD" && return 0
  RDS_PASSWORD=$(getRdsSecret 'app' | jq '.password' | sed 's/"//g')
  echo $RDS_PASSWORD
}

printEnvironment() {
  echo " "
  echo "Environment:"
  env
  echo " "
}

printEnvironment

DNS_NAME=$(echo "$DNS_NAME" | sed -E 's/\.$//') # Strip off trailing dot (if exists).

case "$TASK" in
  get_configs_from_s3)
    downloadConfigsFromS3 ;;
  process_env_files)
    processEnvironmentVariableFiles ;;
  create_kc_env_file)
    createKcEnvironmentVariableFile ;;
  process_kc-config_file)
    processKcConfigFile ;;
esac
