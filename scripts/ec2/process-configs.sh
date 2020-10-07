#!/bin/bash

# Acquire the kc-config.xml file, name=value pair files for docker container environment variables, etc from s3
downloadConfigsFromS3() {
  echo "Downloading all configurations for containers from the s3 bucket, landscape ${LANDSCAPE}"
  
  [ ! -d /opt/kuali/s3 ] && mkdir -p /opt/kuali/s3
  cd /opt/kuali/s3
  aws s3 sync --delete \
    --exclude "*" \
    --include "core/*" \
    --include "portal/*" \
    --include "pdf/*" \
    --include "kc/kc-config.xml" \
    s3://${BUCKET_NAME}/${LANDSCAPE}/ .
  mv /opt/kuali/s3/kc/kc-config-rds.xml /opt/kuali/s3/kc/kc-config.xml
  aws s3 cp s3://${BUCKET_NAME}/rice.cer /opt/kuali/s3/kc/
  aws s3 cp s3://${BUCKET_NAME}/rice.keystore /opt/kuali/s3/kc/
}

# The name=value pair files acquired from s3 will have some default entries whose actual values could 
# not have be known ahead of time, but can be looked up now and copied over the defaults here.
processEnvironmentVariableFile() {
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
  
  # Create a script to export all environment variables in the mounted directory before starting node
  createExportFile() {
    local ENV_FILE_FROM_S3="$1"
    if [ ! -f $ENV_FILE_FROM_S3 ] ; then
      echo "ERROR! MISSING $ENV_FILE_FROM_S3"
      exit 1
    else
      cd $(dirname $ENV_FILE_FROM_S3)
      rm -f export.sh
      echo "Creating $(pwd)/export.sh..."
      while read line ; do
        expline="$(getLineExport "$line")" 
        [ -z "$expline" ] && continue
        prop=$(echo "$line" | cut -f1 -d '=')
        # Override some of the existing environment variables
        [ "${prop^^}" == "SHIB_HOST" ] && expline="export SHIB_HOST="
        [ "${prop^^}" == "ROOT_DIR" ]  && expline="export ROOT_DIR=/var/core-temp"
        echo "Setting env var $prop" 
        echo "$expline" >> export.sh
      done < $ENV_FILE_FROM_S3
      
      # In case the file from s3 originated on a windows file system, remove return carriage chars
      sed -i 's/\r//g' export.sh
    fi
  }

  local common_name="$(getCommonName)"

  # Loop over the collection of environment.variables.s3 files.
  for f in $(env | grep 'ENV_FILE_FROM_S3') ; do
    envfile="$(echo $f | cut -d'=' -f2)"

    # Replace the standard kuali-research-[env].bu.edu references with the dns address of this instances load balancer.
    sed -i -r "s/kuali-research.*.bu.edu/$common_name/g" "$envfile"

    # Correct the AWS_S3_BUCKET name value in case it disagrees with the templates parameter by removing it and putting it back with the provided value.
    if grep -iq 'pdf' <<<"$envfile" ; then
      sed -i '/.*AWS_S3_BUCKET.*=.*/d' $envfile
      echo "AWS_S3_BUCKET=$PDF_BUCKET_NAME" >> $envfile
    fi

    # Make sure values are set that permit self-signed certificates to be accepted by the applicable apps.
    if [ "${DNS_NAME,,}" == 'local' ] || [ -z "$DNS_NAME" ] ; then
      if grep -iq 'pdf' <<<"$envfile" ; then
        sed -i '/.*ALLOW_SELF_SIGNED_SSL.*=.*/d' $envfile
        echo "ALLOW_SELF_SIGNED_SSL=true" >> $envfile
      elif grep -iq 'portal' <<<"$envfile" ; then
        sed -i '/.*NODE_TLS_REJECT_UNAUTHORIZED.*=.*/d' $envfile
        echo "NODE_TLS_REJECT_UNAUTHORIZED=0" >> $envfile
      fi 
    fi

    # Create the export.sh file
    createExportFile "$envfile"
  done
    
  exit 0
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

# echo out the base subdomain address that the kuali applications are reachable on.
getCommonName() {
  if [ "${DNS_NAME,,}" == 'local' ] || [ -z "$DNS_NAME" ] ; then
    # There is no route53 or public load balancer name - the ec2 is all alone and can only be reached if 
    # the private subnet it is sitting in is linked to a bu network through a transit gateway attachment
    # and the user has logged on to that bu network before attempting to reach the application, knowing 
    # the private ip address of the ec2 instance and browsing to the app with it: https://[private ip]/kc.
    local cn=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  else
    local cn="${DNS_NAME}"
  fi
  echo $cn | cut -d'/' -f3 # Strips off the "http://" portion and trailing "/"
}

getRdsHostname() {
  local rdsArn=$(
    aws resourcegroupstaggingapi get-resources \
      --resource-type-filters rds \
      --tag-filters 'Key=Name,Values=kuali-oracle-'$LANDSCAPE \
      --output text \
      --query 'ResourceTagMappingList[].{ARN:ResourceARN}' 2> /dev/null
  )
  if [ -n "$rdsArn" ] && [ "${rdsArn,,}" != 'none' ] ; then
    aws rds describe-db-instances \
      --db-instance-identifier $rdsArn \
      --output text \
      --query 'DBInstances[].{addr:Endpoint.Address}' 2> /dev/null
  fi
}

getRdsSecret() {
  [ -n "$RDS_SECRET" ] && echo "$RDS_SECRET" && return 0
  local type="$1"
  RDS_SECRET=$(
    aws secretsmanager get-secret-value \
      --secret-id kuali/$LANDSCAPE/kuali-oracle-rds-${type}-password \
      --output text \
      --query '{SecretString:SecretString}' 2> /dev/null
    )
    echo $RDS_SECRET
}

getRdsAppUsername() {
  getRdsSecret 'app' | jq '.username' | sed 's/"//g'
}

getRdsAppPassword() {
  getRdsSecret 'app' | jq '.password' | sed 's/"//g'
}


case "$TASK" in
  get_configs_from_s3)
    downloadConfigsFromS3 ;;
  create_env_exports_file)
    processEnvironmentVariableFile ;;
  process_kc-config_file)
    processKcConfigFile ;;
esac
