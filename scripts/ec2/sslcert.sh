#!/bin/bash

# Kuali Research has a REST api for performing CRUD operations against users.
# This api performs ssl handshaking/validation against any incoming requests.
# If the incoming request has a common name that can be verified as trusted by a CA, then all is well.
# If not, however, then a search within the java keystore (cacerts file) must return a corresponding certificate, matched by the common name of the incoming request.
# If this criterion is not met, the following will show up in a BIG stack trace:
#
# Caused by: org.apache.cxf.transport.http.HTTPException: HTTP response '403: Forbidden' when communicating with https://stg.kuali.research.bu.edu/kc/remoting/soap/kim/v2_0/identityService
# 	at org.apache.cxf.transport.http.HTTPConduit$WrappedOutputStream.doProcessResponseCode(HTTPConduit.java:1618) ~[cxf-rt-transports-http-3.3.5.jar:3.3.5]
# or...
# Caused by: java.lang.RuntimeException: HostnameVerifier, socket reset for TTL
#         at org.apache.cxf.transport.https.httpclient.DefaultHostnameVerifier.verify(DefaultHostnameVerifier.java:98) ~[cxf-rt-transports-http-3.3.5.jar:3.3.5]
#
# There are two scenarios in which this problem might arise:
# 1) Self-signed certificates. Obviously no CA knows about these.
# 2) Domain is registered with CA as a wildcarded common name and the REST call is made from a subdomain that the wildcard stands in for.
#    For example, *.kuali.research.bu.edu is registered with the CA, and a REST call is made using stg.kuali.research.bu.edu.
#    This poses no problem for a browser, but the java library is not sophisticated and will search for a literal match of "stg.kuali.research.bu.edu" from the CA.
#    No match will be found and so the keystore must have an entry that matches.
#
# This script is used to both create and import the certificate prevent the errors during REST calls.
# 
# IMPORTANT: Whatever certificates are used for the import, they must be the same certificates used by 
# A) The load balancer (ALB) in use
#    or...
# B) A reverse proxy (nginx)
# If B, you can create the certificate and share it between the nginx and java keystores.
# If A, you cannot create the certificate, but must obtain it from the CA and then import it into the java keystore.
#
# REFERENCES:
#   https://medium.com/@antelle/how-to-generate-a-self-signed-ssl-certificate-for-an-ip-address-f0dd8dddf754
#   https://docs.oracle.com/javase/1.5.0/docs/tooldocs/solaris/keytool.html#importCmd
#   https://magicmonster.com/kb/prg/java/ssl/pkix_path_building_failed/

getCertName() {
  if [ -n "$CERT_NAME" ] ; then
    echo $CERT_NAME
  elif [ "$task" == 'get-cert' ] ; then
    # Will be retrieving the certificate from acm (and potentially backing it up to s3)
    if [ -n "$S3_FILE" ] ; then
      echo "$S3_FILE" | awk 'BEGIN {RS="/"} {print $1}' | tail -1
    elif [ -n "$S3_BUCKET" ] ; then
      echo 'acm_nonprod_certificate'
    fi
  else
    # Will be creating a new self-signed certificate
    echo 'mycert'
  fi
}

# These are defaults for certificate creation only (not importing or getting)
setDefaults() {
  # Set variables
  [ -z "$HOST" ] && HOST="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
  [ -z "$CERT_DIR" ] && CERT_DIR="/opt/kuali/nginx/certs"
  [ -z "$CONFIG_FILE" ] && CONFIG_FILE="$CERT_DIR/$(getCertName).cfg"
  [ -z "$CERT_FILE" ] && CERT_FILE="$CERT_DIR/$(getCertName).crt"
  [ -z "$KEY_FILE" ] && KEY_FILE="$CERT_DIR/$(getCertName).key"
  
  # Create directories or clean them.
  [ ! -d $CERT_DIR ] && mkdir -p $CERT_DIR
  [ -f $CERT_FILE ] && rm -f $CERT_FILE
  [ -f $KEY_FILE ] && rm -f $KEY_FILE
}

# Create the certificate configuration file (happens on the docker host (ec2))
createConfigFile() {

  setDefaults
  
  cat <<EOF > $CONFIG_FILE
[req]
  prompt = no
  distinguished_name = req_distinguished_name
  req_extensions = req_ext

[req_distinguished_name]
  C=US
  ST=MA
  L=Boston
  O=BU
  OU=IST
  CN=$HOST

[req_ext]
  subjectAltName = @alt_names

[v3_req]
  subjectAltName = @alt_names

[alt_names]
  IP.1 = $HOST
EOF
}

# Create the certificate (happens on the docker host (ec2))
createCertificate() {

  createConfigFile

  openssl req -newkey rsa:4096 \
    -x509 \
    -sha256 \
    -days 3650 \
    -nodes \
    -out $CERT_FILE \
    -keyout $KEY_FILE \
    -config $CONFIG_FILE
}

# Import the certificate into the cacerts file.
# This happens inside the docker container, which has the created certificate directory mounted as a volume.
# Will attempt to import this certificate into the cacerts file of the jvm.
importCertificate() {
  echo "Checking for certificates to import into keystore..."
  if [ -z "$CACERTS_FILE" ] ; then
    CACERTS_FILE="$(find / -iname cacerts -type f | head -1 2> /dev/null)"
  fi
  [ -z "$CERT_FILE" ] && CERT_FILE="/opt/kuali/certs/$(getCertName).crt"
  if [ -f "$CERT_FILE" ] ; then
    echo "Found certificate to import at: $CERT_FILE"
  else
    echo "No certificate found to import into keystore: $CERT_FILE not found."
    return 0
  fi
  ALIAS=${ALIAS:-"kuali-self-signed-cert"}

  alreadyImported() {
    local entry="$(
    keytool \
      -list\
      -keystore $CACERTS_FILE \
      -storepass changeit \
      -alias $ALIAS 2> /dev/null | grep "$ALIAS")"
    [ -n "$entry" ] && entry="$(echo "$entry" | grep -i 'trustedCertEntry')"
    [ -n "$entry" ] && true || false
  }

  printKeystoreEntry() {
    keytool \
      -list \
      -v \
      -keystore $CACERTS_FILE \
      -storepass changeit \
      -alias $ALIAS
  }

  if alreadyImported ; then
    echo "Found that a certificate has already been imported to the keystore with alias: $ALIAS"
    echo "Details: "
    printKeystoreEntry
    echo "Cancelling import..."
  else
    keytool \
      -importcert \
      -alias $ALIAS \
      -storepass changeit \
      -noprompt \
      -keystore $CACERTS_FILE \
      -file $CERT_FILE
  fi

  echo "Checking keystore to verify certificate was added successfully..."
  printKeystoreEntry
}

# The certificate to import into the java keystore is either located in an s3 bucket or must be obtained
# from a load balancer using acm methods of the aws cli, in which case, the certificate is assumed to be publicly trusted (not private PKI).
getCertificate() {
  local src=${SOURCE:-${1:-"unspecified"}}
  local certname=${CERT_NAME:-"$(getCertName)"}
  local replace=${REPLACE:-"false"}
  local region=${REGION:-"us-east-1"}
  if [ "$replace" != 'true' ] && [ -f ${certname}.crt ] ; then
    echo "$(pwd)/${certname}.crt already exists and replace = $replace - cancelling certificate retrieval..."
    return 0
  fi
  rm -f ${certname}.crt 2> /dev/null

  # If a full s3 file url is not provided, then a bucket name must be provided which is assumed to have 
  # a certificate with the default name is at its root
  s3Url() {
    if [ -n "$S3_FILE" ] && [ "${S3_FILE:0:5}" != 's3://' ] ; then
      echo "s3://${S3_FILE}"
      return 0
    elif [ -n "$S3_BUCKET" ] ; then
      if [ "${S3_BUCKET:0:5}" != 's3://' ] ; then
        echo "s3://$S3_BUCKET/$certname"
      else
        echo "$S3_BUCKET/$certname"
      fi
    fi
    echo "$S3_FILE"
  }
  s3UrlProvided() { [ -n "$(s3Url)" ] && true || false ; }

  case "${src,,}" in
    s3)
      if s3UrlProvided ; then
        echo "Attempting to download certificate from $(s3Url)..."
        aws s3 cp $(s3Url) ${certname}.crt 2> /dev/null
      fi
      ;;
    acm)
      echo "Attempting to download certificate from acm..."
      local domain=${DOMAIN_NAME:-"*.kuali.research.bu.edu"}
      local certarn="$(aws acm list-certificates \
        --region $region \
        --output text \
        --query 'CertificateSummaryList[?DomainName==`'$domain'`].{arn:CertificateArn}')"

      if [ -n "$certarn" ] ; then
        # Export the certificate into a file
        local certdata="$(aws acm get-certificate \
          --region $region \
          --certificate-arn $certarn | jq -r '.Certificate' \
          > ${certname}.crt)"

        looksLikeACertificate() {
          local top="$(cat "${certname}.crt" | head -1)"
          [ "$top" == '-----BEGIN CERTIFICATE-----' ] && true || false
        }

        if looksLikeACertificate ; then
          echo "SUCCESS! $certarn downloaded as ${certname}.crt"
          if s3UrlProvided ; then
            echo "Backup of certificate to ${s3Url}..."
            aws s3 cp ${certname}.crt $(s3Url)
          fi
        else
          echo "ERROR! Problems downloading $certarn: Does not look like a certificate"
        fi
      else
        echo "ERROR! Could not determine arn of certificate for domain $domain from acm."
        echo "REST requests to the kuali api (snaplogic) may not work."
      fi
      ;;
    unspecified)
      getCertificate 's3'
      if [ ! -f ${certname}.crt ] ; then
        getCertificate 'acm'
      fi
      ;;
  esac
}

# Turn key=value pairs, each passed as an individual commandline parameter 
# to this script, into variables with corresponding values assigned.
parseArgs() {
  for nv in $@ ; do
    [ -z "$(grep '=' <<< $nv)" ] && continue;
    name="$(echo $nv | cut -d'=' -f1)"
    value="$(echo $nv | cut -d'=' -f2-)"
    echo "${name^^}=$value"
    eval "${name^^}=$value" 2> /dev/null || true
  done
}

task="${1,,}"
shift
parseArgs $@ 2>&1

case "$task" in
  get-cert)
    getCertificate
    ;;
  create-config)
    createConfigFile
    ;;
  create-cert)
    # Example: sh /opt/kuali/nginx/certs/sslcert.sh create-cert host=${!EC2_HOST} cert_dir=/opt/kuali/nginx/certs cert_name=mycert
    createCertificate
    ;;
  import-cert)
    # Example: sh /opt/kuali/certs/sslcert.sh import-cert
    importCertificate
    ;;
  
esac