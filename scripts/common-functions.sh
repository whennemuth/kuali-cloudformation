#!/bin/bash

cmdfile=last-cmd.sh

BASELINE_LANDSCAPES=('sb' 'ci' 'qa' 'stg' 'prod')

declare -A kualiTags=(
  [Service]='research-administration'
  [Function]='kuali'
)

outputHeading() {
  local border='*******************************************************************************'
  echo ""
  echo "$border"
  echo "       $1"
  echo "$border"
}

windows() {
  [ -n "$(ls /c/ 2> /dev/null)" ] && true || false
}

isNumeric() {
  [ -n "$(grep -P '^\d+$' <<< "$1")" ] && true || false
}

err(){
  std_err "Error: $*"
}

std_err() {
  echo "$*" >>/dev/stderr
}

isCurrentDir() {
  local askDir="$1"
  # local thisDir="$(pwd | grep -oP '[^/]+$')"  # Will blow up if run on mac (-P switch)
  local thisDir="$(pwd | awk 'BEGIN {RS="/"} {print $1}' | tail -1)"
  [ "$askDir" == "$thisDir" ] && true || false
}

parseArgs() {
  for nv in $@ ; do
    [ -z "$(grep '=' <<< $nv)" ] && continue;
    name="$(echo $nv | cut -d'=' -f1)"
    value="$(echo $nv | cut -d'=' -f2-)"
    if [ "${name^^}" != 'SILENT' ] && [ "$SILENT" != 'true' ] ; then
      echo "${name^^}=$value"
    fi
    eval "${name^^}=$value" 2> /dev/null || true
  done
  if [ -n "$PROFILE" ] ; then
    export AWS_PROFILE=$PROFILE 
    [ "$SILENT" != 'true' ] && echo "export AWS_PROFILE=$PROFILE"
  # elif [ -z "$DEFAULT_PROFILE" ] ; then
  #   if [ "$task" != 'validate' ] ; then
  #     echo "Not accepting a blank profile. If you want the default then use \"profile='default'\" or default_profile=\"true\""
  #     exit 1
  #   fi
  fi
}

setDefaults() {
  # Set explicit defaults first
  [ -z "$LANDSCAPE" ] && LANDSCAPE="${defaults['LANDSCAPE']}" || LANDSCAPE="${LANDSCAPE,,}"
  if isABaselineLandscape && [ -z "$BASELINE" ] ; then
    BASELINE=$LANDSCAPE
    echo "BASELINE=$BASELINE"
  fi
  [ -z "$GLOBAL_TAG" ] && GLOBAL_TAG="${defaults['GLOBAL_TAG']}"
  for k in ${!defaults[@]} ; do
    [ -n "$(eval 'echo $'$k)" ] && continue; # Value is not empty, so no need to apply default
    local val="${defaults[$k]}"
    if grep -q '\$' <<<"$val" ; then
      eval "val=$val"
    elif [ ${val:0:14} == 'getLatestImage' ] ; then
      [ "$task" == 'delete-stack' ] && continue;
      val="$($val)"
    fi
    local evalstr="[ -z \"\$$k\" ] && $k=\"$val\""
    eval "$evalstr"
    [ "$SILENT" != 'true' ] && echo "$k = $val"
  done

  # Set contingent defaults second
  tempath="$(dirname "$TEMPLATE")"
  if [ "$tempath" != "." ] ; then
    TEMPLATE_PATH=$tempath
    # Strip off the directory path and reduce down to file name only.
    TEMPLATE=$(echo "$TEMPLATE" | grep -oP '[^/]+$')
    [ "$SILENT" != 'true' ] && echo "TEMPLATE = $TEMPLATE"
  fi
  # Trim off any trailing forward slashes
  TEMPLATE_PATH=$(echo "$TEMPLATE_PATH" | sed 's/\/*$//')
  [ "$SILENT" != 'true' ] && echo "TEMPLATE_PATH = $TEMPLATE_PATH"
  # Get the http location of the bucket path 
  BUCKET_URL="$(echo "$TEMPLATE_BUCKET_PATH" | sed 's/s3:\/\//https:\/\/s3.amazonaws.com\//')"
  [ "$SILENT" != 'true' ] && echo "BUCKET_URL = $BUCKET_URL"
  # Fish out just the bucket name from the larger bucket path
  TEMPLATE_BUCKET_NAME="$(echo "$TEMPLATE_BUCKET_PATH" | grep -oP '(?<=s3://)([^/]+)')"
  [ "$SILENT" != 'true' ] && echo "TEMPLATE_BUCKET_NAME = $TEMPLATE_BUCKET_NAME"
}

# Validate one or all cloudformation yaml templates.
validateStack() {

  local silent="$1"
  local singlefile="$2"
  local root=$(pwd)
    
  [ -d "$TEMPLATE_PATH" ] && cd $TEMPLATE_PATH
  rm -f $root/validate.valid 2> /dev/null
  rm -f $root/validate.invalid 2> /dev/null

  # find . -type f -iname "*.yaml" | \
  while read line; do \
    local f=$(printf "$line" | sed 's/^.\///'); \
    [ -n "$TEMPLATE" ] && [ "$TEMPLATE" != "$f" ] && continue;
    printf "validating $f";

    validate "$f" >> $root/validate.valid 2>> $root/validate.invalid
    if [ $? -gt 0 ] ; then
      echo $f >> $root/validate.invalid
    fi
    echo " "
  done <<< "$([ -n "$singlefile" ] && echo $singlefile || find . -type f -iname "*.yaml")"
  cd $root
  if [ -z "$silent" ] ; then
    cat $root/validate.valid
  fi
  if isValidationError "$root/validate.invalid" ; then
    cat $root/validate.invalid
    rm -f $root/validate.invalid 2> /dev/null
    rm -f $root/validate.valid 2> /dev/null
    exit 1
  else
    rm -f $root/validate.invalid 2> /dev/null
    rm -f $root/validate.valid 2> /dev/null
    echo "SUCCESS! (no errors found)"
  fi
}

isValidationError() {
  local errfile="$1"
  local err='false'
  if [ -f $errfile ] && [ -n "$(cat $errfile)" ]; then
    # A template over 51200 will show up as an error, but will be ok as long as it is obtained from an s3 bucket when running stack operation. 
    [ -z "$(cat $errfile | grep 'Member must have length less than or equal to 51200')" ] && err='true'
  fi
  [ $err == 'true' ] && true || false
}

# Validate a single cloudformation yaml file
validate() {
  local template="$1"
  printf "\n\n$template:" && \
  aws cloudformation validate-template --template-body "file://./$template"
}

# Upload one or all cloudformation yaml templates to s3
uploadStack() {
  validateStack silent

  [ $? -gt 0 ] && exit 1

  if [ -n "$TEMPLATE" ] ; then
    if [ -f $TEMPLATE ] ; then
      echo "aws s3 cp $TEMPLATE $TEMPLATE_BUCKET_PATH/" > $cmdfile
    elif [ -f $TEMPLATE_PATH/$TEMPLATE ] ; then
      echo "aws s3 cp $TEMPLATE_PATH/$TEMPLATE $TEMPLATE_BUCKET_PATH/" > $cmdfile
    else
      echo "$TEMPLATE not found!"
      exit 1
    fi
  else
    cat <<-EOF > $cmdfile
    aws s3 cp $TEMPLATE_PATH $TEMPLATE_BUCKET_PATH \\
      --exclude=* \\
      --include=*.yaml \\
      --recursive
EOF
  fi

  if [ "$DEBUG" ] ; then
    cat $cmdfile
    return 0
  fi
  
  # Create an s3 bucket for the app if it doesn't already exist
  if ! bucketExists "$TEMPLATE_BUCKET_NAME" ; then
    aws s3 mb s3://$TEMPLATE_BUCKET_NAME
  fi

  # if [ "$PROMPT" == 'false' ] ; then
  #   echo "\nExecuting the following command(s):\n\n$(cat $cmdfile)\n"
  #   local answer='y'
  # else
  #   printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
  #   read answer
  # fi
  # [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."

  sh $cmdfile
}

# Add on key=value parameter entry to the construction of an aws cli function call to 
# perform a create/update stack action.
addParameter() {
  local cmdfile="$1"
  local key="$2"
  local value="$3"
  [ -n "$(cat $cmdfile | grep 'ParameterKey')" ] && local comma=","
  cat <<-EOF >> $cmdfile
        ${comma}{
          "ParameterKey" : "$key",
          "ParameterValue" : "$value"
        }
EOF
}

# Add on key=value parameter entry to the construction of an aws cli function call to 
# perform a create/update stack action.
add_parameter() {
  eval 'local value=$'$3
  [ -z "$value" ] && return 0
  addParameter "$1" "$2" "$value"
}

# Add on key=value tag entry to the construction of an aws cli function call to 
# perform a create/update stack action.
addTag() {
  local cmdfile="$1"
  local key="$2"
  local value="$3"
  [ -n "$(cat $cmdfile | grep '\"Key\" :')" ] && local comma=","
  cat <<-EOF >> $cmdfile
        ${comma}{
          "Key" : "$key",
          "Value" : "$value"
        }
EOF
}

addStandardTags() {
  addTag $cmdfile 'Service' ${kualiTags['Service']}
  addTag $cmdfile 'Function' ${kualiTags['Function']}
  addTag $cmdfile 'Landscape' "$LANDSCAPE"
  if [ -n "$BASELINE" ] ; then
    addTag $cmdfile 'Baseline' "$BASELINE"
  fi
}

# Issue an ssm command to an ec2 instance to re-run its init functionality from it's metadata.
metaRefresh() {
  getInstanceId() (
    aws cloudformation describe-stack-resources \
      --stack-name $FULL_STACK_NAME \
      --logical-resource-id $LOGICAL_RESOURCE_ID \
      --output text \
      --query 'StackResources[0].{pri:PhysicalResourceId}'
  )

  local instanceId="$(getInstanceId)"
  
  if [ -z "$instanceId" ] ; then
    echo "ERROR! Cannot determine instanceId in stack \"$FULL_STACK_NAME\""
    exit 1
  else
    echo "instanceId = $instanceId"
  fi

  printf "Enter the name of the configset to run: "
  read configset
  # NOTE: The following does not seem to work properly:
  #       --parameters commands="/opt/aws/bin/cfn-init -v --configsets $configset --region "us-east-1" --stack "ECS-EC2-test" --resource $LOGICAL_RESOURCE_ID"
  # Could be a windows thing, or could be a complexity of using bash to execute python over through SSM.
	cat <<-EOF > $cmdfile
	aws ssm send-command \\
		--instance-ids "${instanceId}" \\
		--document-name "AWS-RunShellScript" \\
		--comment "Implementing cloud formation metadata changes on ec2 instance $LOGICAL_RESOURCE_ID ($instanceId)" \\
		--parameters \\
		'{"commands":["/opt/aws/bin/cfn-init -v --configsets '"$configset"' --region \"us-east-1\" --stack \"$FULL_STACK_NAME\" --resource $LOGICAL_RESOURCE_ID"]}'
	EOF

  if [ "$DEBUG" ] ; then
    cat $cmdfile
    exit 0
  fi

  printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
  read answer
  [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."
}

checkKeyPair() {
  if [ -n "$KEYPAIR_NAME" ] ; then
    case "$action" in
      create-stack)
        # Prompt to create the keypair, even if it already exists (offer choice to replace with new one).
        createEc2KeyPair $KEYPAIR_NAME
        [ -f "$KEYPAIR_NAME" ] && chmod 600 $KEYPAIR_NAME
        ;;
      update-stack)
        # Create the keypair without prompting, but only if it does not already exist
        if ! keypairExists $KEYPAIR_NAME ; then
          createEc2KeyPair $KEYPAIR_NAME
          [ -f "$KEYPAIR_NAME" ] && chmod 600 $KEYPAIR_NAME
        fi
        ;;
    esac
  else
    echo "No keypairs associated with ec2 instance(s) - use ssm start-session method for shell access."
  fi
}

keypairExists() {
  local keyname="$1"
  aws ec2 describe-key-pairs --key-names $keyname > /dev/null 2>&1
  [ $? -eq 0 ] && true || false
}

keypairInUse() {
  local keyname="$1"
  local searchResult="$(
    aws ec2 describe-instances \
      --output text \
      --query 'Reservations[].Instances[?KeyName==`'$keyname'`]'.{KeyName:KeyName} 
  )"
  [ -n "$searchResult" ] && true || false
}

# Create a public/private keypair
createEc2KeyPair() {
  local keyname="$1"
  local cleanup="$2"
  # Create an s3 bucket for the app if it doesn't already exist
  
  if ! bucketExists "$TEMPLATE_BUCKET_NAME" ; then
    aws s3 mb s3://$TEMPLATE_BUCKET_NAME
  fi

  if keypairExists $keyname ; then
    [ "$PROMPT" == 'false' ] && return 0
    if ! askYesNo "$keyname already exists upstream, replace it?" ; then
      return 0
    fi
    aws ec2 delete-key-pair --key-name $keyname
  fi

  # Generate the keypair
  ssh-keygen -b 2048 -t rsa -f $keyname -q -N ""

  # Import the keypair to aws ec2 keypairs
  if [ -n "$(aws ec2 import-key-pair help | grep 'tag-specifications')" ] ; then
    local tagspec="--tag-specifications ResourceType=key-pair,Tags=[{Key=Name,Value=$keyname}]"
    local filespec="fileb://./$keyname.pub"
  else
    local filespec="file://./$keyname.pub"
    echo "You're using an older version of the aws cli - imported keypair will have no tags"
  fi

  echo "Importing $keyname ..."
  aws ec2 import-key-pair \
    --key-name "$keyname" \
    $tagspec \
    --public-key-material $filespec
    
  # Upload the private key to the s3 bucket
  aws s3 cp ./$keyname s3://$TEMPLATE_BUCKET_NAME/
  # Remove the keypair locally
  if [ -n "$cleanup" ] ; then
    rm -f $keyname && rm -f $keyname.pub
  elif [ -f $keyname ] ; then
    chmod 600 $keyname
  fi
}

printCertLookupSteps() {
  cat <<EOF

-------------------------------------------------
        SPECIFY SSL CERTIFICATE
-------------------------------------------------        
  The arn for the ssl certificate is not specified.
  Will search in the following order and prompt for ok to take actions.
  (NOTE: You can cancel everything at this point - (CTRL+C)):
    --------------------------------------------------------
        ACM CERTIFICATE
    --------------------------------------------------------
    1) If USING_ROUTE53=false, go to step 7
    2) Use cli to find out if a certificate with the following CN (common name) 
       exists in acm and get its arn.
         CN: *.$CN
    3) If not found, identify 3 files in current directory that can combine for 
       certificate import.
    4) If files found, prompt for import to acm to create new certificate entry.
    5) If not accepted by user for import, search s3 in a known location for similar 
       files and download to temp directory.
    6) If files downloaded from s3 pass the same test, prompt user again.
    --------------------------------------------------------
        SELF-SIGNED CERTIFICATE (IAM SERVER CERTIFICATE)
    --------------------------------------------------------
    7) If user does not accept, or not using route53, prompt to use a self-signed certificate.
    8) If user accepts, look for a self-signed certificate in iam by the expected name.
    9) If found, prompt the user if they want to continue to use it or.
    10) If not accepted, prompt the user if they want to have a new self-signed 
       certificate created and uploaded to iam.
    11) If not accepted, exit - there are no other options and cannot proceed 
        with out a certificate.

EOF
}

# Search the acm service for a certificate that matches the specified domain name.
getAcmCertArn() {
  local domainName="$1"
  local arn=$(
    aws acm list-certificates \
      --output text \
      --query 'CertificateSummaryList[?DomainName==`'$domainName'`].{arn:CertificateArn}' 2> /dev/null)
  echo "$arn"
}

# Search the acm service for a certificate that matches the supplied criteria and set the global CERTIFICATE_ARN variable if a match is found.
# If no match is found, search the local file system relative to the current location for component files that can be idenfified as able to be
# successfully combined for upload as an acm certificate. If found, upload and set CERTIFICATE_ARN with the resulting arn.
setAcmCertArn() {
  local domainName="$1"
  [ "$LANDSCAPE" != 'prod' ] && domainName="*.$domainName"
  local arn="$(getAcmCertArn $domainName)"
  [ -n "$arn" ] && CERTIFICATE_ARN="$arn" && return 0

  local checkS3=${2:-'true'}
  local keyfiles=0
  local certfiles=0
  local chainfiles=0

  echo "Searching $(pwd) for cert & key files..."

  # 1) Check for cert files
  for f in $(grep -irxE '\-+BEGIN CERTIFICATE\-+' *.* | cut -d':' -f1 | uniq) ; do
    if isAChainFile $f ; then
      local chainfile=$f
      ((chainfiles++))
    elif isACertFile $f ; then
      # Make sure the certificate file is for the domain we want it to be.
      local certDomain="$(openssl x509 -text -noout -in $f | grep -ioP '(?<=CN=)[^\s]*\.[a-z]{2,3}' | uniq)"
      if [ "$domainName" == "$certDomain" ] ; then
        local certfile=$f
        ((certfiles++))
      else
        echo "Found $f, but has mismatching domain/common name:"
        echo "   $f"
        echo "   Need: $domainName"
        echo "   Found: $certDomain"
      fi
    fi
  done

  # 2) Check for key file
  if [ $((certfiles+chainfiles)) -eq 2 ] ; then
    for f in $(grep -irxE '\-+BEGIN RSA PRIVATE KEY\-+' *.* | cut -d':' -f1 | uniq) ; do
      if isAKeyFile $f ; then
        local keyfile=$f
        ((keyfiles++))
      fi
    done
  fi
  
  # 3) If one of each file type was found, there can be no confusion, so ask to import these to acm.
  if [ $((certfiles+chainfiles+keyfiles)) -eq 3 ] ; then
    if askImportCertToAcm ; then
      echo "Importing new certificate to acm..."
      CERTIFICATE_ARN=$(importCertToAcm)
      [ $? -gt 0 ] && exit 1
      # Add tags to the certificate
      echo "Applying tags to new certificate in acm..."
      aws acm add-tags-to-certificate \
        --certificate-arn $CERTIFICATE_ARN \
        --tags \
            Key=Name,Value=$domainName \
            Key=Function,Value=${kualiTags['Service']} \
            Key=Service,Value=${kualiTags['Function']} \
            Key=Landscape,Value=$LANDSCAPE

    elif [ "$checkS3" == 'true' ] ; then
      if askYesNo "Check S3 for these files instead?" ; then
        downloadAcmCertsFromS3 'import' "$domainName"
      fi
    fi
  else
    if askYesNo "Insufficient, unqualified, or no certificate/key files found in $(pwd)\nCheck s3 for them?" ; then
      downloadAcmCertsFromS3 'import' "$domainName"
    fi
  fi
}

askImportCertToAcm() {
  cat <<EOF

Found 3 files that look like what we need to import to acm for ssl cert.
The load balancer is lacking a certificate in acm. If these correspond to 
the $LANDSCAPE landscape, they can be imported to acm:
  1) Keyfile:           $(pwd)/$keyfile
  2) Root certificate:  $(pwd)/$certfile
  3) Certificate chain: $(pwd)/$chainfile
    
EOF
  askYesNo "Import these files to acm?" && true || false
}

downloadAcmCertsFromS3() {
  local setArn="$1"
  local domainName="$2"
  echo "Searching $BASELINE folder in s3 bucket for cert & key files..."
  local files=$(
    aws s3 ls s3://$TEMPLATE_BUCKET_NAME/$BASELINE/$domainName \
      --recursive \
      | awk '{print $4}' \
      | grep -E '^([^/]+/){1}[^/]+\.((cer)|(crt)|(key))' 2> /dev/null
  )
  local tempdir='_cert_files_from_s3'
  rm -rf $tempdir
  for path in $files ; do
    [ ! -d $tempdir ] && mkdir $tempdir
    aws s3 cp s3://$TEMPLATE_BUCKET_NAME/$path $tempdir/
  done
  if [ $(ls -1 $tempdir/ | wc -l) -ge 3 ] ; then
    if [ "$setArn" ] ; then
      cd $tempdir
      setAcmCertArn $domainName 'false'
      cd - 1> /dev/null
      rm -rf $tempdir
    fi
  fi
}

# Import the 3 component files (cerficate, key, and chain file) to acm as a new certificate.
importCertToAcm() {
  case $(awsVersion) in
    1)
      aws acm import-certificate \
        --certificate file://$certfile \
        --private-key file://$keyfile \
        --certificate-chain file://$chainfile \
        --output text 2> /dev/null | grep -Po 'arn:aws:acm[^\s]*'
      ;;
    2)
      aws acm import-certificate \
        --certificate fileb://$certfile \
        --private-key fileb://$keyfile \
        --certificate-chain fileb://$chainfile \
        --output text 2> /dev/null | grep -Po 'arn:aws:acm[^\s]*'
      ;;
  esac
}

isACertFile() {
  local certfile="$1"
  if [ -f $certfile ] ; then
    local hasBeginCert="$(head -n 1 $certfile | grep -xE '\-+BEGIN CERTIFICATE\-+')"
    if [ "$hasBeginCert" ] ; then
      local hasEndCert="$(tail -n 1 $certfile | grep -xE '\-+END CERTIFICATE\-+')"
    fi
  fi
  ([ "$hasBeginCert" ] && [ "$hasEndCert" ]) && true || false
}

isAKeyFile() {
  local keyfile="$1"
  if [ -f $keyfile ] ; then
    local hasBeginKey="$(head -n 1 $keyfile | grep -xE '\-+BEGIN RSA PRIVATE KEY\-+')"
    if [ "$hasBeginKey" ] ; then
      local hasEndKey="$(tail -n 1 $keyfile | grep -xE '\-+END RSA PRIVATE KEY\-+')"
    fi
  fi
  ([ "$hasBeginKey" ] && [ "$hasEndKey" ]) && true || false
}

isAChainFile() {
  local chainfile="$1"
  local beginMarkers=0
  local endMarkers=0
  if isACertFile $chainfile ; then
    beginMarkers=$(grep -irxE '\-+BEGIN CERTIFICATE\-+' $chainfile | wc -l)
    endMarkers=$(grep -irxE '\-+END CERTIFICATE\-+' $chainfile | wc -l)
  fi
  ([ $beginMarkers -eq 3 ] && [ $endMarkers -eq 3 ]) && true || false
}

# Starting point for determining the arn of a certificate to be used in ssl encryption for the web application.
# The certificate search will occur first in the acm service, and if not found the iam server certificates service.
setCertArn() {
  [ -n "$CERTIFICATE_ARN" ] && return 0
  # printCertLookupSteps
  if [ "${USING_ROUTE53,,}" == 'true' ] ; then
    setAcmCertArn "$HOSTED_ZONE"
    [ -z "$CERTIFICATE_ARN" ] && echo "Acm service has no entry for $HOSTED_ZONE."
  else
    echo "Not using route53, which requires a self-signed certificate (which is permissable with iam certificate, but not acm certificate)"
  fi
  if [ -z "$CERTIFICATE_ARN" ] ; then
    if [ "${PROMPT,,}" == 'false' ] || askYesNo "Use a self-signed, iam based server certificate instead?" ; then
      [ "${PROMPT,,}" != 'false' ] && printCertLookupSteps
      setSelfSignedCertArn
    fi
  fi
  if [ -z "$CERTIFICATE_ARN" ] ; then
    printf "Cannot proceed without a server certificate.\nCancelling..."
    exit 1
  fi 
  echo "Using certificate: $CERTIFICATE_ARN"
}

# Print out the arn of the self signed certificate if it exists in iam.
getSelfSignedArn() {
  local certname="$1"
  [ -n "$CERTIFICATE_ARN" ] && echo "$CERTIFICATE_ARN" && return 0

  aws \
    iam list-server-certificates \
    --output text \
    --query 'ServerCertificateMetadataList[?ServerCertificateName==`'$certname'`].{Arn:Arn}' 2> /dev/null
}

# Set a value for global variable CERTIFICATE_ARN. The value will be the arn of an iam server certificate.
# The certificate will either pre-exist in iam, or will be created and uploaded to iam.
setSelfSignedCertArn() {
  [ -n "$CERTIFICATE_ARN" ] && return 0

  if [ "${USING_ROUTE53,,}" == 'true' ] ; then
    [ "$LANDSCAPE" == 'prod' ] && local certname="$HOSTED_ZONE" || local certname="wildcard.$HOSTED_ZONE"
  elif [ -n "$GLOBAL_TAG" ] ; then
    local certname="${GLOBAL_TAG}-${LANDSCAPE}-cert"
  else
    local certname="kuali-cert-${LANDSCAPE}"
  fi

  printf "\nChecking iam for server certificate: $certname...\n"
  CERTIFICATE_ARN="$(getSelfSignedArn $certname)"
  
  if [ -n "$CERTIFICATE_ARN" ] ; then
    echo "Found arn for self-signed certificate: $CERTIFICATE_ARN"
    if [ "${PROMPT,,}" != 'false' ] ; then
      select choice in \
        'Use this self-signed certificate' \
        'Replace with a new self-signed certificate' \
        'Exit the process.' ; do 
          case $REPLY in
            1) 
              break ;;
            2) 
              echo "Deleting existing iam server certificate..."
              aws iam delete-server-certificate --server-certificate-name $certname
              createSelfSignedCertificate $certname
              break
              ;;
            3) 
              exit 0 ;;
            *) echo "Valid selections are 1, 2, 3"
          esac
      done;
    fi
  elif [ "${PROMPT,,}" == 'false' ] || askYesNo "No self-signed certificate found. Create and upload a new one?" ; then
    createSelfSignedCertificate $certname
  fi
}

# Create and upload to ACM a self-signed certificate in preparation for stack creation (will be used by the application load balancer)
createSelfSignedCertificate() {
  local certname="$1"

  local commonName="*.amazonaws.com"
  if [ "${USING_ROUTE53,,}" == 'true' ] ; then
    commonName="$HOSTED_ZONE"
    [ "$LANDSCAPE" != 'prod' ] && commonName="*.$commonName"
  fi
  # Create the key pair
  openssl req -newkey rsa:2048 \
    -x509 \
    -sha256 \
    -days 3650 \
    -nodes \
    -out ./${LANDSCAPE}-self-signed.crt \
    -keyout ./${LANDSCAPE}-self-signed.key \
    -subj "/C=US/ST=MA/L=Boston/O=BU/OU=IST/CN=$commonName"

  # openssl req -new -x509 -nodes -sha256 -days 365 -key my-private-key.pem -outform PEM -out my-certificate.pem

  # Upload to IAM and record the arn of the resulting resource

  # WARNING!
  # For some reason cloudformation returns a "CertificateNotFound" error when the arn of a certificate uploaded to acm
  # is used to configure the listener for ssl. However, it has no problem with an arn of uploaded iam server certificates.
  # 
  # aws acm import-certificate \
  #   --certificate file://${GLOBAL_TAG}-self-signed.crt \
  #   --private-key file://${GLOBAL_TAG}-self-signed.key \
  #   --tags Key=Name,Value=${certname} \
  #   --output text| grep -Po 'arn:aws:acm[^\s]*' > ${GLOBAL_TAG}-self-signed.arn

  # Before uploading the certificate, you can check if it exists already:
  #    aws iam list-server-certificates
  # And delete it if found:
  #    aws iam delete-server-certificate --server-certificate-name [cert name]
  echo "Uploading self-signed certificate to iam..."
  CERTIFICATE_ARN=$(
    aws iam upload-server-certificate \
    --server-certificate-name ${certname} \
    --certificate-body file://${LANDSCAPE}-self-signed.crt \
    --private-key file://${LANDSCAPE}-self-signed.key \
    --output text 2> /dev/null | grep -Po 'arn:aws:iam[^\s]*'
  )

  # Create an s3 bucket for the app if it doesn't already exist
  if ! bucketExists "$TEMPLATE_BUCKET_NAME" ; then
    aws s3 mb s3://$TEMPLATE_BUCKET_NAME
  fi

  # Upload the cert and keyset to the s3 bucket
  # aws s3 cp ./${LANDSCAPE}-self-signed.crt s3://$TEMPLATE_BUCKET_NAME/self-signed-certs/
  # aws s3 cp ./${LANDSCAPE}-self-signed.key s3://$TEMPLATE_BUCKET_NAME/self-signed-certs/ 
}


# Get the id of the default vpc in the account. (Assumes there is only one default)
getDefaultVpcId() {
  local id=$(aws ec2 describe-vpcs \
    --output text \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' 2> /dev/null)
  [ ! "$id" ] && return 1
  [ "${id,,}" == 'none' ] && return 1
  echo $id
}

# Get the id of the internet gateway within the specified vpc
getInternetGatewayId() {
  local vpcid="$1"
  if [ -n "$vpcid" ] ; then
    local gw=$(aws ec2 describe-internet-gateways \
      --output text \
      --query 'InternetGateways[].[InternetGatewayId, Attachments[].VpcId]' \
      | grep -B 1 $vpcid \
      | grep 'igw' 2> /dev/null)
  fi
  [ ! "$gw" ] && return 1
  [ "${gw,,}" == 'none' ] && return 1
  echo $gw
}

getTransitGatewayId() {
  local vpcId="$1"
  local matches=()

  for tgw in $(aws \
    ec2 describe-transit-gateways \
    --output text --query 'TransitGateways[*].[TransitGatewayId]'
  ) ; do
    for state in $(aws ec2 describe-transit-gateway-attachments \
      --output text \
      --query 'TransitGatewayAttachments[?TransitGatewayId==`'$tgw'`&&ResourceId==`'$vpcId'`].State'
    ); do
      if [ "${state,,}" == "available" ] ; then
        matches=(${matches[@]} $tgw)
      fi 
    done
  done

  [ ${#matches[@]} -eq 1 ] && echo ${matches[0]}
}

getVpcId() {
  local subnetId="$1"
  aws \
    ec2 describe-subnets \
    --subnet-ids $subnetId \
    --output text \
    --query 'Subnets[].VpcId' 2> /dev/null
}

# Get a "Y/y" or "N/n" response from the user to a question.
askYesNo() {
  local answer="n";
  while true; do
    printf "$1 [y/n]: "
    read yn
    case $yn in
      [Yy]* ) answer="y"; break;;
      [Nn]* ) break;;
      * ) echo "Please answer yes or no.";;
    esac
  done
  if [ $answer = "y" ] ; then true; else false; fi
}

# The BUAWS Cloud Infrastructure account will have 6 subnets (2 tagged as "World", 4 tagged as "Campus")
isBuCloudInfAccount() {
  local subnets=$(
    aws resourcegroupstaggingapi get-resources \
      --resource-type-filters ec2:subnet \
      --tag-filters 'Key=Network,Values=Campus,World' \
      --output text \
      --query 'ResourceTagMappingList[].{ARN:ResourceARN}' | wc -l 2> /dev/null
  )
  [ $subnets -eq 6 ] && true || false
}


# Provided a base identifier and one or two filters, lookup subnets matching the filter(s) and make variable assignments from
# some of the subnet properties. The variables names will start with the base identifier (ie: for base id "PUBLIC_SUBNET", cidr: "PUBLIC_SUBNET1_CIDR") 
getSubnets() {
  local globalVar="$1"
  local filter1="$2"
  local filter2="$3"

  while read subnet ; do
    local az="$(echo "$subnet" | awk '{print $1}')"
    local cidr="$(echo "$subnet" | awk '{print $2}')"
    local subnetId="$(echo "$subnet" | awk '{print $3}')"
    local vpcId="$(echo "$subnet" | awk '{print $4}')"
    if [ -n "$vpcId" ] && [ -z "$(grep -i 'VpcId' $cmdfile)" ]; then        
      echo "VpcId="$vpcId"" >> $cmdfile
      echo "VPC_ID="$vpcId"" >> $cmdfile
    fi
    if [ -z "$(eval echo "\$${globalVar}1")" ] ; then
      if [ "$(eval echo "\$${globalVar}2")" != "$subnetId" ] ; then
        echo "Found first $(echo ${globalVar,,} | sed 's/_/ /'): $subnet"
        eval "${globalVar}1="$subnetId""
        echo "${globalVar}1="$subnetId"" >> $cmdfile
        echo "${globalVar}1_AZ="$az"" >> $cmdfile
        echo "${globalVar}1_CIDR="$cidr"" >> $cmdfile
        continue
      fi
    fi
    if [ -z "$(eval echo "\$${globalVar}2")" ] ; then
      if [ "$(eval echo "\$${globalVar}1")" != "$subnetId" ] ; then
        echo "Found second $(echo ${globalVar,,} | sed 's/_/ /'): $subnet"
        eval "${globalVar}2="$subnetId""
        echo "${globalVar}2="$subnetId"" >> $cmdfile
        echo "${globalVar}2_AZ="$az"" >> $cmdfile
        echo "${globalVar}2_CIDR="$cidr"" >> $cmdfile
      fi
    fi
  done <<< "$(
    aws ec2 describe-subnets \
      --filters $filter1 $filter2 \
      --output text \
      --query 'sort_by(Subnets, &AvailabilityZone)[*].{VpcId:VpcId,SubnetId:SubnetId,AZ:AvailabilityZone,CidrBlock:CidrBlock}'
  )"
}

# Ensure that there are 6 subnets are specified (2 campus subnets, 2 private subnets and 2 public subnets).
# If any are not provided, then look them up with the cli against their tags and assign them accordingingly.
# If any are provided, look them up to validate that they exist as subnets.
checkSubnets() {
  # Clear out the last command file
  printf "" > $cmdfile

  getSubnets \
    'CAMPUS_SUBNET' \
    'Name=tag:Network,Values=Campus' \
    'Name=tag:aws:cloudformation:logical-id,Values=CampusSubnet1,CampusSubnet2'

  getSubnets \
    'PRIVATE_SUBNET' \
    'Name=tag:Network,Values=Campus' \
    'Name=tag:aws:cloudformation:logical-id,Values=PrivateSubnet1,PrivateSubnet2'

  getSubnets \
    'PUBLIC_SUBNET' \
    'Name=tag:Network,Values=World'

  cat ./$cmdfile
  source ./$cmdfile

  # Count how many subnets have values
  local subnets=$(grep -P '_SUBNET\d=' $cmdfile | wc -l)
  if [ $subnets -lt 6 ] ; then
    # Some subnets might have been explicitly provided by the user as a parameter, but look those up to verify they exist.
    if [ -z "$(grep 'PRIVATE_SUBNET1' $cmdfile)" ] ; then
      subnetExists "$PRIVATE_SUBNET1" && ((subnets++)) && echo "PRIVATE_SUBNET1=$PRIVATE_SUBNET1"
    fi    
    if [ -z "$(grep 'CAMPUS_SUBNET1' $cmdfile)" ] ; then
      subnetExists "$CAMPUS_SUBNET1" && ((subnets++)) && echo "CAMPUS_SUBNET1=$CAMPUS_SUBNET1"
    fi
    if [ -z "$(grep 'PUBLIC_SUBNET1' $cmdfile)" ] ; then
      subnetExists "$PUBLIC_SUBNET1" && ((subnets++)) && echo "PUBLIC_SUBNET1=$PUBLIC_SUBNET1"
    fi
    if [ -z "$(grep 'PRIVATE_SUBNET2' $cmdfile)" ] ; then
      subnetExists "$PRIVATE_SUBNET2" && ((subnets++)) && echo "PRIVATE_SUBNET2=$PRIVATE_SUBNET2"
    fi    
    if [ -z "$(grep 'CAMPUS_SUBNET2' $cmdfile)" ] ; then
      subnetExists "$CAMPUS_SUBNET2" && ((subnets++)) && echo "CAMPUS_SUBNET2=$CAMPUS_SUBNET2"
    fi
    if [ -z "$(grep 'PUBLIC_SUBNET2' $cmdfile)" ] ; then
      subnetExists "$PUBLIC_SUBNET2" && ((subnets++)) && echo "PUBLIC_SUBNET2=$PUBLIC_SUBNET2"
    fi
    # If we still don't have a total of 6 subnets then exit with an error code
  fi
  [ $subnets -lt 6 ] && echo "ERROR! Must have 6 subnets (2 public, 2 campus, 2 private)\n1 or more are missing and could not be found with cli."
  [ $subnets -lt 6 ] && false || true
}


# We are running against the "Legacy" kuali aws account, so an adapted version of checkSubnets is needed.
# -------------------------------------------------------------------------------------------------------
# Ensure that there are 4 subnets are specified (2 application subnets and 2 database subnets).
# If any are not provided, then look them up with the cli against their tags and assign them accordingingly.
# If any are provided, look them up to validate that they exist as subnets.
checkSubnetsInLegacyAccount() {
  # Clear out the last command file
  printf "" > $cmdfile

  getSubnets \
    'CAMPUS_SUBNET' \
    'Name=tag:Network,Values=application' \
    'Name=tag:Environment,Values='$BASELINE

  getSubnets \
    'PRIVATE_SUBNET' \
    'Name=tag:Network,Values=database' \
    'Name=tag:Environment,Values='$BASELINE

  getSubnets \
    'PRIVATE_SUBNET' \
    'Name=tag:Network,Values=database' \
    'Name=tag:Environment2,Values='$BASELINE

  source ./$cmdfile

  # Count how many application subnets have values
  local appSubnets=$(grep -P 'CAMPUS_SUBNET\d=' $cmdfile | wc -l)
  if [ $appSubnets -lt 2 ] ; then
    # Some subnets might have been explicitly provided by the user as a parameter, but look those up to verify they exist.
    if [ -z "$(grep 'CAMPUS_SUBNET1' $cmdfile)" ] ; then
      subnetExists "$CAMPUS_SUBNET1" && ((appSubnets++)) && echo "CAMPUS_SUBNET1=$CAMPUS_SUBNET1"
    fi
    if [ -z "$(grep 'CAMPUS_SUBNET2' $cmdfile)" ] ; then
      subnetExists "$CAMPUS_SUBNET2" && ((appSubnets++)) && echo "CAMPUS_SUBNET2=$CAMPUS_SUBNET2"
    fi
    # We can have less than two application subnets, but must have at least one.
  fi

  # Count how many database subnets have values
  local dbSubnets=$(grep -P 'PRIVATE_SUBNET\d=' $cmdfile | wc -l)
  if [ $dbSubnets -lt 2 ] ; then
    # Some subnets might have been explicitly provided by the user as a parameter, but look those up to verify they exist.
    if [ -z "$(grep 'PRIVATE_SUBNET1' $cmdfile)" ] ; then
      subnetExists "$PRIVATE_SUBNET1" && ((dbSubnets++)) && echo "PRIVATE_SUBNET1=$PRIVATE_SUBNET1"
    fi    
    if [ -z "$(grep 'PRIVATE_SUBNET2' $cmdfile)" ] ; then
      subnetExists "$PRIVATE_SUBNET2" && ((dbSubnets++)) && echo "PRIVATE_SUBNET2=$PRIVATE_SUBNET2"
    fi    
    # If we still don't have a total of 2 or more database subnets then exit with an error code
  fi

  cat ./$cmdfile
  source ./$cmdfile

  [ $appSubnets -lt 1 ] && echo "ERROR! Must have at least one application subnet \nNone are provided and could not be found with cli."
  [ $dbSubnets -lt 2 ] && echo "ERROR! Must have 2 database subnets \n1 or more are missing and could not be found with cli."
  [ $((appSubnets+dbSubnets)) -lt 3 ] && false || true
}


subnetExists() {
  local subnetId="$1"
  if [ -n "$subnetId" ] ; then
    local lookupResult="$(
    aws \
      ec2 describe-subnets \
      --subnet-ids=$subnetId \
      --output text \
      --query 'Subnets[].SubnetId' 2> /dev/null
    )"
    [ "$lookupResult" != "$subnetId" ] && echo "ERROR: subnet does not exist: $subnetId"
  else
    lookupResult="null"
  fi
  [ "$lookupResult" == "$subnetId" ] && true || false
}


# Will determine if an S3 bucket exists, even if it is empty.
# NOTE: You must call scripts that use this with bash, not sh, else the pipe to the while loop syntax will not be recognized.
bucketExists() {
  local bucketname="$1"

  findBucket() {
    while read b ; do
      b=$(echo "$b" | awk '{print $3}')
      if [ "$b" == "$bucketname" ] ; then
        return 0
      fi
    done
    return 1
  }

  aws s3 ls 2> /dev/null | findBucket
  [ $? -eq 0 ] && true || false
}

secretExists() {
  local name="$1"
  local secret="$(
  aws secretsmanager list-secrets \
    --output text \
    --query 'SecretList[?Name==`'$name'`].{Name:Name}' 2> /dev/null
  )"
  [ -n "$secret" ] && true || false
}

secretExistsForBaseline() {
  local baseline="${1:-$BASELINE}"
  local result="$(
    aws resourcegroupstaggingapi get-resources \
      --resource-type-filters secretsmanager:secret \
      --output text \
      --tag-filters \
        'Key=Landscape,Values='$baseline \
        'Key=Function,Values='${kualiTags['Function']} \
        'Key=Service,Values='${kualiTags['Service']} 2> /dev/null
    )"
    [ -n "$result" ] && true || false
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
  echo "$RDS_SECRET"
}

getRdsAdminUsername() {
  # getRdsSecret | cut -d'"' -f8
  getRdsSecret 'admin' | jq '.MasterUsername' | sed 's/"//g'
}

getRdsAdminPassword() {
  # getRdsSecret | cut -d'"' -f4
  getRdsSecret 'admin' | jq '.MasterUserPassword' | sed 's/"//g'
}

getRdsAppUsername() {
  getRdsSecret 'app' | jq '.username' | sed 's/"//g'
}

getRdsAppPassword() {
  getRdsSecret 'app' | jq '.password' | sed 's/"//g'
}

getRandomPassword() {
  date +%s | sha256sum | base64 | head -c 32
}

getRdsArn() {
  local landscape=${1:-$LANDSCAPE}
  aws resourcegroupstaggingapi get-resources \
    --resource-type-filters rds:db \
    --tag-filters 'Key=App,Values=Kuali' 'Key=Landscape,Values='$landscape \
    --output text \
    --query 'ResourceTagMappingList[].{ARN:ResourceARN}' 2> /dev/null
}

getRdsHostname() {
  local rdsArn=$(getRdsArn)
  if [ -n "$rdsArn" ] ; then
    aws rds describe-db-instances \
      --db-instance-id $rdsArn \
      --output text \
      --query 'DBInstances[].Endpoint.{Hostname:Address}' 2> /dev/null
  fi
}

getArnOfRdsToSnapshot() {
  if [ "$LANDSCAPE" != "$BASELINE" ] ; then
    if [ -z "$(getRdsArn)" ] ; then
      getRdsArn $BASELINE
    fi
  fi
}

getRdsBaseline() {
  local rdsArn="$1"
  if [ -n "$rdsArn" ] ; then
    aws rds list-tags-for-resource \
      --resource-name $rdsArn \
      --output text \
      --query 'TagList[?Key==`Baseline`].{Value:Value}' 2> /dev/null
  fi
}

getRdsSnapshotBaseline() {
  local snapshotArn="$1"
  if [ -n "$snapshotArn" ] ; then
    local rdsRN=$(
      aws rds describe-db-snapshots \
        --db-snapshot-identifier $snapshotArn \
        --output text \
        --query 'DBSnapshots[].{DBInstanceIdentifier:DBInstanceIdentifier}' 2> /dev/null
    )
    local rdsArn=$(
      aws rds describe-db-instances \
        --db-instance-identifier $rdsRN \
        --output text \
        --query 'DBInstances[].{DBInstanceArn:DBInstanceArn}' 2> /dev/null
    )
    getRdsBaseline $rdsArn
  fi
}

checkRDSParameters() {
  [ "$task" == 'delete-stack' ] && return 0
  outputHeading "Checking RDS parameters..."

  validateBaseline() {
    local msg="$1"
    if [ -z "$BASELINE" ] ; then
      if [ -n "msg" ] ; then
        echo "ERROR! Could not establish a BASELINE using $msg"
        exit 1
      elif isABaselineLandscape "$LANDSCAPE" ; then
        BASELINE=$LANDSCAPE
      else
        echo "ERROR! No baseline landscape specified."
        exit 1
      fi    
    elif isABaselineLandscape "$BASELINE" ; then
      if ! secretExistsForBaseline ; then
        echo "Secrets Manager kuali secret with a landscape tag equal to the specified baseline ($BASELINE) must exist!"
        exit 1
      fi
    else      
      echo "ERROR! Invalid baseline landscape \"$BASELINE\""
      exit 1 
    fi
  }

  validateRdsArn() {
    if [ -z "$RDS_ARN_TO_CLONE" ] ; then
      echo "Cannot clone non-existent database! No RDS instance exists for kuali tagged with a $RDS_LANDSCAPE_TO_CLONE landscape."
      exit 1
    fi  
  }

  if [ -n "$RDS_SNAPSHOT_ARN" ] ; then
    BASELINE="$(getRdsSnapshotBaseline $RDS_SNAPSHOT_ARN)"
    validateBaseline "rds snapshot ARN"
  elif [ -n "$RDS_ARN_TO_CLONE" ] ; then
    BASELINE="$(getRdsBaseline $RDS_ARN_TO_CLONE)"
    validateBaseline "rds ARN"
    RDS_SNAPSHOT_ARN='new'
  elif [ -n "$RDS_LANDSCAPE_TO_CLONE" ] ; then
    RDS_ARN_TO_CLONE="$(getRdsArn $RDS_LANDSCAPE_TO_CLONE)"
    validateRdsArn      
    BASELINE="$(getRdsBaseline $RDS_ARN_TO_CLONE)"
    validateBaseline "rds ARN"
    RDS_SNAPSHOT_ARN='new'
  elif [ -n "BASELINE" ] ; then
    if ! isABaselineLandscape ; then
      local original="$BASELINE"
      BASELINE="$(getStackBaselineByLandscape $BASELINE)"
      validateBaseline " descendent landscape \"$original\""
    fi
  fi

  validateBaseline
}

createRdsSnapshot() {
  local instanceARN="$1"
  local snapshotId="$2"
  local landscape="$3"
  local instanceId=$(nameFromARN $instanceARN)

  local data=$(aws rds create-db-snapshot \
    --db-instance-identifier $instanceId \
    --db-snapshot-identifier $snapshotId \
    --tags \
        Key=Function,Value=${kualiTags['Function']} \
        Key=Service,Value=${kualiTags['Service']} \
        Key=Landscape,Value=$LANDSCAPE 2> /dev/null
  )

  echo "$data" | grep 'DBSnapshotArn' | cut -d'"' -f4 2> /dev/null
}

waitForRdsSnapshotCompletion() {
  local snapshotArn="$1"
  local snapshotName=$(nameFromARN "$snapshotArn")
  outputHeading "Waiting for $snapshotName snapshot completion..."
  local counter=1
  local status="unknown"
  while true ; do
    local data=$(aws rds describe-db-snapshots \
      --db-snapshot-identifier $snapshotArn \
      --output text \
      --query 'DBSnapshots[].{status:Status, progress:PercentProgress}'
    )
    local progress=$(echo "$data" | awk '{print $1}')
    local status=$(echo "$data" | awk '{print $2}')
    echo "$snapshotName status check $counter: $status, ${progress}% done"
    ([ "${status,,}" == 'available' ] && [ "$progress" == '100' ]) && break
    ((counter++))
    if [ $counter -ge 720 ] ; then
      echo 'RDS snapshot not yet available after an hour, cancelling'
      break;
    fi
    sleep 5
  done
  ([ "${status,,}" == 'available' ] && [ "$progress" == '100' ]) && true || false
}

# Most of the RDS related parameters have been determined at this point.
# Add them all to the final cloudformation stack creation/update cli function call being built.
addRdsSnapshotParameters() {
  local cmdfile="$1"
  local landscape="$2"
  local rdsSnapshotARN="$3"
  local rdsArnToSnapshot="$4"

  add_parameter $cmdfile 'RdsDbSubnet1' 'PRIVATE_SUBNET1'
  add_parameter $cmdfile 'RdsDbSubnet2' 'PRIVATE_SUBNET2'
  add_parameter $cmdfile 'RdsSubnetCIDR1' 'PRIVATE_SUBNET1_CIDR'
  add_parameter $cmdfile 'RdsSubnetCIDR2' 'PRIVATE_SUBNET1_CIDR'
  add_parameter $cmdfile 'RdsJumpboxSubnetCIDR1' 'CAMPUS_SUBNET1_CIDR'
  add_parameter $cmdfile 'RdsJumpboxSubnetCIDR2' 'CAMPUS_SUBNET2_CIDR'
  add_parameter $cmdfile 'RdsAvailabilityZone' 'PRIVATE_SUBNET1_AZ'

  if [ "${rdsSnapshotARN,,}" == 'new' ] ; then
    rdsSnapshotARN="$(createRdsSnapshot $rdsArnToSnapshot $(date -u +'kuali-oracle-'$landscape'-cfn-%Y-%m-%d-%H-%M') $landscape)"
    if [ -z "$rdsSnapshotARN" ] ; then
      err "Problem snapshotting $rdsInstanceId"
      exit 1
    fi
    if ! waitForRdsSnapshotCompletion $rdsSnapshotARN ; then
      echo "RDS snapshot creation unsuccessful, cancelling..."
      exit 1
    fi
    [ $? -gt 0 ] && err "Problem with snapshot attempt!" && exit 1
  fi

  addParameter $cmdfile 'RdsSnapshotARN' $rdsSnapshotARN

  local engineVersion="$(getOracleEngineVersion $rdsSnapshotARN)"
  if [ -z "$engineVersion" ] ; then
    echo "ERROR! Cannot determine rds engine version"
    exit 1
  fi
  addParameter $cmdfile 'RdsEngineVersion' $engineVersion

}

isDryrun() {
  if [ "${1,,}" == 'dryrun' ] || [ "${1,,}" == 'true' ] ; then
    local dryrun="$1"
  fi
  [ -n "$dryrun" ] && true || false
}

nameFromARN() {
  local arn="$1"
  case $(echo "$arn" | grep -o ':' | wc -l) in
    7)
      # arn contains 
      echo $arn | grep -oP '[^:]+:[^:]+$' ;;
    *) 
      echo $arn | grep -oP '[^:]+$' ;;
  esac
}

isAnAutomatedSnapshot() {
  local snapshotId="$1"
  [ "${snapshotId:0:4}" == 'rds:' ] && true || false
}

deleteRdsSnapshot() {
  local snapshotId="$1"
  if isAnAutomatedSnapshot "$snapshotId" ; then
    echo "$snapshotId is an automated backup, to delete you must change the retention period of the source " \
    "rds instance to a number that the age of the snapshot exceeds."
    return 0
  fi
  aws rds delete-db-snapshot --db-snapshot-identifier $snapshotId
}

# Remove either:
#   A single snapshot by db-snapshot-identifier older than a specified number of days
#   or...
#   All snapshots created against an rds instance identified by db-instance-identifier older than a specified number of days
pruneOldRdsSnapshots() {
  for keyAndVal in $@ ; do
    eval "local $keyAndVal"
  done
  if [ -z "$(echo "$days" | grep -P '^\d+$')" ] ; then
    err "Snapshot age in days must be an integer! Provided value: $days"
    return 1
  fi

  [ -n "$dbInstanceId" ] && local dbInstanceIdArg="--db-instance-identifier $dbInstanceId"
  [ -n "$snapshotArn" ] && local snapshotArnArg="--db-snapshot-identifier $(nameFromARN $snapshotArn)"

  while read snapshot ; do
    local id=$(echo "$snapshot" | awk '{print $1}')
    local created=$(echo "$snapshot" | awk '{print $2}')
    local daysOld=$(echo $(( ($(date -u +%s) - $(date -d $created +%s) )/(60*60*24) )))
    if [ -z "$id" ] || [ -z "$created" ] || [ -z "$daysOld" ] ; then
      echo "Problem parsing snapshot age data!"
      continue
    elif [ $daysOld -ge $days ] ; then
      local msg="$id is $daysOld days old"
      isDryrun && msg="DRYRUN: $msg"
      if isAnAutomatedSnapshot "$id" ; then
        echo "$msg, but is an automated backup, skipping..."
      else
        echo "$msg, deleting..."
        deleteRdsSnapshot $id
      fi
    fi
  done <<< "$(aws rds describe-db-snapshots \
      $dbInstanceIdArg $snapshotArnArg --output text \
      --query 'DBSnapshots[].{id:DBSnapshotIdentifier,time:SnapshotCreateTime}' 2> /dev/null
  )"
}

pruneKualiRdsSnapshots() {
  for keyAndVal in $@ ; do
    eval "local $keyAndVal"
  done
  [ -z "$excludeLandscape" ] && excludeLandscape='no-landscape'
  while read snapshot ; do
    arn=$(echo $snapshot | jq -r '.ResourceARN')
    landscape=$(echo $snapshot | jq -r '.Tags[] | select(.Key == "Landscape").Value')
    echo "deleting $landscape snapshot: $arn"
    pruneOldRdsSnapshots snapshotArn=$arn $@
  done <<< "$(aws resourcegroupstaggingapi get-resources \
    --resource-type-filters rds:snapshot \
    --tag-filters \
      'Key=Function,Values=kuali' \
      'Key=Service,Values=research-administration' \
      | jq -r --compact-output '.ResourceTagMappingList[] | select(contains({Tags: [{Key: "Landscape", Value: "'$excludeLandscape'"} ]}) | not)'
  )"
}

pruneKualiRdsSnapshotsExceptProd() {
  # pruneKualiRdsSnapshots excludeLandscape=prod dryrun=true days=30
  pruneKualiRdsSnapshots excludeLandscape=prod $@
}

pruneSnapshotsExistingKualiRdsInstance() {
  # pruneOldRdsSnapshots landscape=ci dryrun=true days=30
  for keyAndVal in $@ ; do
    eval "local $keyAndVal"
  done

  local arn=$(aws resourcegroupstaggingapi get-resources \
    --resource-type-filters rds:db \
    --tag-filters \
      'Key=Function,Values=kuali' \
      'Key=Service,Values=research-administration' \
      'Key=Landscape,Values='$landscape \
    --output text \
    --query 'ResourceTagMappingList[].{ARN:ResourceARN}' | head -1 2> /dev/null
  )

  local dbInstanceId=$(nameFromARN "$arn")
  [ -z "$dbInstanceId" ] && echo "No rds instance found tagged with landscape: $landscape" && return 0
  pruneOldRdsSnapshots dbInstanceId=$dbInstanceId $@
}

getKcConfigDb() {
  if [ ! -f 'kc-config.xml.temp' ] ; then
    aws s3 cp s3://$TEMPLATE_BUCKET_NAME/$BASELINE/kuali/main/config/kc-config.xml 'kc-config.xml.temp' > /dev/null
    [ ! -f 'kc-config.xml.temp' ] && return 1
  fi

  getKcConfigDbPassword && echo ''
  getKcConfigDbHost && echo ''
  getKcConfigDbName && echo ''
  getKcConfigDbPort && echo ''
  getKcConfigDbUsername && echo ''
  getKcConfigDmsDbUsername && echo ''
  getKcConfigDmsDbPassword && echo ''
  getKcConfigSctDbUsername && echo ''
  getKcConfigSctDbPassword && echo ''

  [ -f 'kc-config.xml.temp' ] && rm -f 'kc-config.xml.temp'
}


getKcConfigLine() {
  {
    if [ -f 'kc-config.xml.temp' ] ; then
      cat 'kc-config.xml.temp'
    else
      aws s3 cp s3://$TEMPLATE_BUCKET_NAME/$BASELINE/kuali/main/config/kc-config.xml - 2> /dev/null
    fi
  } | grep $1
}

getKcConfigDbUsername() {
  getKcConfigLine 'datasource.username' \
    | grep -oE '>[^<>]+<' \
    | tr -d '\t[:space:]<>'
}

getKcConfigDmsDbUsername() {
  getKcConfigLine 'datasource.dms.username' \
    | grep -oE '>[^<>]+<' \
    | tr -d '\t[:space:]<>'
}

getKcConfigSctDbUsername() {
  getKcConfigLine 'datasource.sct.username' \
    | grep -oE '>[^<>]+<' \
    | tr -d '\t[:space:]<>'
}

getKcConfigDbPassword() {
  getKcConfigLine 'datasource.password' \
    | grep -oE '>[^<>]+<' \
    | tr -d '\t[:space:]<>'
}

getKcConfigDmsDbPassword() {
  getKcConfigLine 'datasource.dms.password' \
    | grep -oE '>[^<>]+<' \
    | tr -d '\t[:space:]<>'
}

getKcConfigSctDbPassword() {
  getKcConfigLine 'datasource.sct.password' \
    | grep -oE '>[^<>]+<' \
    | tr -d '\t[:space:]<>'
}

getKcConfigDbCtnStrItem() {
  getKcConfigLine 'datasource.url' \
    | grep -oE $1'=[^\(\))]+' \
    | cut -d'=' -f2 \
    | tr -d '[:space:]\n'
}

getKcConfigDbHost() {
  getKcConfigDbCtnStrItem 'HOST'
}

getKcConfigDbName() {
  getKcConfigDbCtnStrItem 'SERVICE_NAME'
}

getKcConfigDbPort() {
  getKcConfigDbCtnStrItem 'PORT'
}

getOracleEngineVersion() {
  local snapshotArn=${1:-$RDS_SNAPSHOT_ARN}
  if [ -n "$snapshotArn" ] ; then
    aws rds describe-db-snapshots \
    --output text \
    --query 'DBSnapshots[?DBSnapshotArn==`'$snapshotArn'`].{EngineVersion:EngineVersion}' 2> /dev/null
  fi
}

getLatestOracleEngineVersion() {
  local engine="$1"
  local majorVersion="$2"
  
  aws rds describe-db-engine-versions \
    --engine $engine \
    --output text \
    --query 'DBEngineVersions[?DBParameterGroupFamily==`'$engine-$majorVersion'`].{EngineVersion:EngineVersion}' 2> /dev/null | tail -n -1
}

# All kuali images are tagged with a single version: YYMM.xxxx
# The top result of a numeric sort against a list of all an ecr repos image tags should indicate the latest one.
getLatestImage() {
  local reponame="$1"
  local accountNbr="$(aws sts get-caller-identity --output text --query 'Account')"
  local version=$(aws \
    ecr describe-images \
    --registry-id $accountNbr \
    --repository-name $reponame \
    --output text \
    --query 'imageDetails[*].[imageTags[0]]' \
    | sort -rn \
    | head -n 1)
  echo "$accountNbr.dkr.ecr.us-east-1.amazonaws.com/$reponame:$version"
}

waitForStackToDelete() {
  outputHeading "Deleting existing stack..."
  local counter=1
  local status="unknown"
  local stackname="$FULL_STACK_NAME"
  if [ -z "$stackname" ] ; then
    stackname=$STACK_NAME
    [ -n "$LANDSCAPE" ] && stackname="$stackname-$LANDSCAPE"
  fi
  while true ; do
    status="$(
      aws cloudformation describe-stacks \
        --stack-name $stackname \
        --output text \
        --query 'Stacks[].{status:StackStatus}' 2> /dev/null
    )"
    [ -z "$status" ] && status="DELETED"
    echo "$stackname stack status check $counter: $status"
    ([ "$status" == 'DELETED' ] || [ "$status" == 'DELETE_FAILED' ]) && break
    ((counter++))
    sleep 5
  done
  [ "$status" == 'DELETED' ] && true || false
}

waitForEc2InstanceToFinishStarting() {
  local instanceId="$1"
  local counter=1
  local instanceState="unknown"
  local instanceStatus="unknown"
  local systemStatus="unknown"
  local sleep=5
  local timeoutMinutes=${2:-10}
  local timeoutSeconds=$(($timeoutMinutes*60))
  while true ; do
    details="$(
      aws ec2 describe-instance-status \
        --instance-ids $instanceId \
        --output text \
        --query 'InstanceStatuses[].{state:InstanceState.Name,sysStatus:SystemStatus.Status,instStatus:InstanceStatus.Status}' 2> /dev/null
    )"
    instanceStatus=$(echo "$details" | awk '{print $1}')
    instanceState=$(echo "$details" | awk '{print $2}')
    systemStatus=$(echo "$details" | awk '{print $3}')
    echo "$instanceId status check $counter: instanceState:$instanceState, instanceStatus:$instanceStatus, systemStatus:$systemStatus"
    [ "${instanceState,,}" == 'running' ] && [ "${instanceStatus,,}" == 'ok' ] && [ "${systemStatus,,}" == 'ok' ] && break
    [ $(($counter*$sleep)) -ge $timeoutSeconds ] && echo "Its been $timeoutMinutes minutes without passing status check, cancelling." && exit 1
    ((counter++))
    sleep $sleep
  done
}

jqInstalled() {
  jq --version > /dev/null 2>&1
  if [ $? -gt 0 ] ; then
    echo "Installing jq ..."
    if [ -n "$(yum --version 2> /dev/null)" ] ; then
      # Centos
      yum install epel-release -y && \
      yum install jq -y
    elif [ -n "$(dnf --version 2> /dev/null)" ] ; then
      # Fedora
      dnf install -y jq
    elif [ -n "$(apt-get --version 2> /dev/null)" ] ; then
      # Debian/Ubuntu
      apt-get install -y jq
    elif [ -n "$(brew --version 2> /dev/null)" ] ; then
      # OS X
      brew install jq
    elif [ -n "$(chocolatey --version 2> /dev/null)" ] ; then
      # windows
      chocolatey install -y jq
    fi
    if [ -z "$(jq --version > /dev/null 2> /dev/null)" ] ; then
      printf "WARNING! jq not detected and could not be installed.\n
      Install jq and try again.\n
      https://stedolan.github.io/jq/download/\n"
      local failed="true"
    fi
    [ -n "$failed" ] && true || false
  fi
}


# The aws cloudformation stack create/update command has just been constructed.
# Prompt the user and/or run it according to certain flags.
runStackActionCommand() {
  if [ "$DEBUG" ] ; then
    cat $cmdfile
    exit 0
  fi

  if [ "$PROMPT" == 'false' ] ; then
    printf "\nExecuting the following command(s):\n\n$(cat $cmdfile)\n"
    local answer='y'
  else
    printf "\nExecute the following command:\n\n$(cat $cmdfile)\n\n(y/n): "
    read answer
  fi
  [ "$answer" == "y" ] && sh $cmdfile || echo "Cancelled."

  [ $? -gt 0 ] && echo "Cancelling..." && exit 1
}

awsVersion() {
  aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2 | cut -d'.' -f1
}

getHostedZoneId() {
  local commonName="$1"
  aws route53 list-hosted-zones \
    --output text \
    --query 'HostedZones[?starts_with(Name, `'$commonName'`) == `true`].{id:Id}' 2> /dev/null
}

getHostedZoneIdByLandscape() {
  local landscape="${1:-$LANDSCAPE}"
  # Only need to get the arn, the id will be part of it
  aws resourcegroupstaggingapi get-resources \
    --resource-type-filters route53:hostedzone \
    --tag-filters \
      "Key=Landscape,Values=$LANDSCAPE" \
      'Key=Service,Values='${kualiTags['Service']} \
      'Key=Function,Values='${kualiTags['Function']} \
    --output text \
    --query 'ResourceTagMappingList[*].{arn:ResourceARN}' 2> /dev/null | cut -d'/' -f2
}

getHostedZoneNameByLandscape() {
  aws route53 get-hosted-zone \
    --id "$(getHostedZoneIdByLandscape $1)" \
    --output text \
    --query 'HostedZone.{name:Name}' 2> /dev/null \
    | sed -E 's/\.$//' # trim off any trailing dot
}

checkLegacyAccount() {
  if [[ "$task" == *create-stack ]] || [[ "$task" == *update-stack ]] || [[ "$task" == 'set-cert-arn' ]] ; then
    if ! isBuCloudInfAccount ; then
      LEGACY_ACCOUNT='true'
      echo 'Current profile indicates legacy account.'
      defaults['TEMPLATE_BUCKET_PATH']=$(echo "${defaults['TEMPLATE_BUCKET_PATH']}" | sed -i 's/kuali-config/kuali-research-ec2-setup/')
      if [ "$BASELINE" != 'prod' ] && [ -n "${defaults['HOSTED_ZONE']}" ] ; then
        defaults['HOSTED_ZONE']="kuali-research-$BASELINE.bu.edu"
      fi
    fi
  fi
}

# Cloudformation can only delete a bucket if it is empty (and has no versioning), so empty it out here.
emptyBuckets() {
  local success='true'
  for bucket in $@ ; do
    if bucketExists "$bucket" ; then
      echo "aws s3 rm s3://$bucket --recursive..."
      aws s3 rm s3://$bucket --recursive
      local errcode=$?
      if [ $errcode -gt 0 ] ; then
        echo "ERROR! Emptying bucket $bucket, error code: $errcode"
        success='false'
      fi
      # aws s3 rb --force $bucket
    else
      echo "Cannot empty bucket $bucket. Bucket does not exist."
    fi
  done
  [ $success == 'true' ] && true || false
}

# Zip up one or more files in an archive with a specified name and upload it to s3 at a specified path.
# Arg1: The s3 path, including name of the zip file (ie: s3://mybucket/mydir/myfile.zip)
# Arg2 - ArgN: One or more files (ie: ../some/file.js).
zipAndCopyToS3Basic() {
  local outputfile='temp-zip-file.zip'
  local s3path="$1"
  shift

  [ -f $outputfile ] && rm -f $outputfile
  while [ "$1" ] ; do
    local inputfile="$1"
    if [ ! -f $inputfile ] ; then
      echo "ERROR! No such file: $inputfile"
      local badzip='true'
      break;
    fi
    if [ -n "$(zip --version 2> /dev/null)" ] ; then
      echo "Adding $inputfile to $outputfile..."
      zip $outputfile $inputfile
    elif [ -f /c/Program\ Files/7-Zip/7z.exe ] ; then
      echo "Adding $inputfile to $outputfile..."
      /c/Program\ Files/7-Zip/7z.exe a $outputfile $inputfile
    else
      echo "No zip program!"
      exit 1
    fi
    shift
  done

  if [ "$badzip" ] ; then
    false
  else
    aws s3 cp $outputfile $s3path
    local retval=$?
    rm -f $outputfile
    [ $retval -eq 0 ] && true || false
  fi
}

zipPackageAndCopyToS3() {
  local rootPath="$1"
  [ ! -d "$rootPath" ] && echo "root path: \"$rootPath\" does not exist" && cd - && return 1
  cd $rootPath
  local s3path="$2"
  [ -z "$s3path" ] && echo "Target path in s3 was ommitted!" && cd - && return 1

  npm run pack
  [ $? -gt 0 ] && "Error using npm!" && exit 1

  # BUG in node when accessed from gitbash or cygwin: "stdout is not a tty"
  # Workaround seems to be to call node.exe instead of just node.
  # Not an issue on linux. Mac?
  # https://github.com/nodejs/node/issues/14100
  local gitbash="$(node.exe --version > /dev/null 2>&1 && [ "$?" == "0" ] && echo 'true')"

  # Create the a node command to parse package.json as json and output the version property.
  local cmd="node"
  [ $gitbash ] && cmd="${cmd}.exe"
  local name=$($cmd -pe 'JSON.parse(process.argv[1]).name' "$(cat package.json)" 2> /dev/null);

  [ ! "$name" ] && echo "Cannot determine name from package.json file to give zip file!" && cd - && return 1
  local zipfile="${name}.zip"
  [ ! -f "$zipfile" ] && echo "Failed to generate $zipfile to upload to s3!" && cd - && return 1

  aws s3 cp $zipfile $s3path
  cd -
}

getEc2InstanceName() {
  aws ec2 describe-instances \
    --instance-id $instanceId \
    --output text \
    --query 'Reservations[].Instances[].Tags[?Key==`Name`]' \
    | awk '{print $2}' 2> /dev/null
}

# Offer the user a picklist of id:name pairs for ec2 instances that match the tagging filters provided as parameters. Optionally,
# The first parameter can be a single term that must be found in the name tag of the ec2 instance: 'nameFragment=term'.
# No choice is offered if only one match is found and that match is automatically selected. The ec2 instance id is temporarily 
# saved off to a file in the current directory.
# Example use:
#    filters=(
#      'Key=Function,Values='${kualiTags['Function']}
#      'Key=Service,Values=${kualiTags['Service']}
#    ) 
#    pickEC2InstanceId 'nameFragment=mongo' ${filters[@]}
pickEC2InstanceId() {
  if [ "$(echo ${1:0:12})" == 'nameFragment' ] ; then
    eval "local $1"
    shift
  fi
  local tagfilters=$@
  local instanceState="unknown"
  local instanceStatus="unknown"
  local systemStatus="unknown"
  local ids=()

  echo "Working..."
  while read instanceId ; do
    if [ -n "$instanceId" ] ; then  
      details="$(
        aws ec2 describe-instance-status \
          --instance-ids $instanceId \
          --output text \
          --query 'InstanceStatuses[].{state:InstanceState.Name,sysStatus:SystemStatus.Status,instStatus:InstanceStatus.Status}' 2> /dev/null
      )"
      [ -z "$details" ] && continue;
      instanceStatus=$(echo "$details" | awk '{print $1}')
      instanceState=$(echo "$details" | awk '{print $2}')
      systemStatus=$(echo "$details" | awk '{print $3}')
      # echo "$instanceId: instanceState:$instanceState, instanceStatus:$instanceStatus, systemStatus:$systemStatus"
      if ([ "$instanceState" == 'running' ] && [ "$instanceStatus" == 'ok' ] && [ "$systemStatus" == 'ok' ]) ; then
        local instanceName=$(getEc2InstanceName $instanceId)
        if [ -n "$(echo $instanceName | grep -i "$nameFragment")" ] ; then
          ids=(${ids[@]} $instanceId:$instanceName)
        fi
      fi
    fi
  done <<< "$(
    aws resourcegroupstaggingapi get-resources \
      --resource-type-filters ec2:instance \
      --tag-filters $tagfilters \
      --output text \
      --query 'ResourceTagMappingList[].{ARN:ResourceARN}' | cut -d'/' -f2 | sed 's/\n//g' 2> /dev/null
  )"

  if [ ${#ids[@]} -gt 0 ] ; then
    local id=${ids[0]}
    if [ ${#ids[@]} -gt 1 ] ; then
      echo "Matched more than one ec2 instance. Pick one:"
      select choice in ${ids[@]} 'Cancel'; do 
        case $REPLY in
          $((${#ids[@]}+1)))
            echo "Cancelled."
            id=''
            break ;;
          [0-${#ids[@]}])
            id=${ids[$(($REPLY-1))]}
            break
            ;;
          *)
            echo "Valid selections are 1 $((${#ids[@]}+1))"
        esac
      done;
    fi
    if [ -n "$id" ] ; then
      id=$(echo $id | cut -d':' -f 1)
      echo "$id" > ec2-instance-id
    fi
  fi
}

isABaselineLandscape() {
  local landscape="${1:-$LANDSCAPE}"
  local match=''
  for l in ${BASELINE_LANDSCAPES[@]} ; do
    if [ "${landscape,,}" == $l ] ; then
      match=$l
      break
    fi
  done
  [ -n "$match" ] && true || false
}

getStackByTag() {
  local tagname="$1"
  local tagvalue="$2"
  aws resourcegroupstaggingapi get-resources \
  --resource-type-filters cloudformation:stack \
  --output text \
  --tag-filters \
    'Key=Service,Values='${kualiTags['Service']} \
    'Key=Function,Values='${kualiTags['Function']} \
    "Key=$tagname,Values=$tagvalue"
}

stackExistsForLandscape() {
  local landscape="${1:-$LANDSCAPE}"
  local stack="$(getStackByTag 'Landscape' $landscape)"
  [ -n "$stack" ] && true || false
}

stackExistForBaselineLandscape() {
  local baseline="${1:-$BASELINE}"
  local stack="$(getStackByTag 'Baseline' $baseline)"
  [ -n "$stack" ] && true || false
}

getStackBaselineByLandscape() {
  local landscape="$1"
  getStackByTag Landscape $landscape | grep 'Baseline' | head -1 | awk '{print $3}'
}

validateShibboleth() {
  [ "$task" == 'delete-stack' ] && return 0
  if [ "${USING_SHIBBOLETH,,}" == 'true' ] ; then
    if [ "${USING_ROUTE53}" == 'false' ] ; then
      echo "Cannot use shibboleth without route53!"
      exit 1
    elif [ -z "${USING_ROUTE53}" ] ; then
      echo "Since shibboleth is indicated..."
      echo "USING_ROUTE53='true'" && USING_ROUTE53='true'
    fi
  fi
}

checkLandscapeParameters() {
  [ "$task" == 'delete-stack' ] && return 0
  outputHeading "Checking Landscape parameters..."
  [ -z "$LANDSCAPE" ] && echo "Missing landscape parameter!" && exit 1
  if stackExistsForLandscape ; then
    echo "A cloudformation stack for the $LANDSCAPE landscape already exists!"
    exit 1
  fi
  echo "Ok"
}
