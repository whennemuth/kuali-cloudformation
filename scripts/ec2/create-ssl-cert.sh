#!/bin/bash

DEFAULT_CERT_NAME='mycert'

setDefaults() {
  # Set variables
  [ -z "$HOST" ] && HOST="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
  [ -z "$CERT_DIR" ] && CERT_DIR="/opt/kuali/nginx/certs"
  [ -z "$CERT_NAME" ] && CONFIG_NAME="$DEFAULT_CERT_NAME"
  [ -z "$CONFIG_FILE" ] && CONFIG_FILE="$CERT_DIR/$CERT_NAME.cfg"
  [ -z "$CERT_FILE" ] && CERT_FILE="$CERT_DIR/$CERT_NAME.crt"
  [ -z "$KEY_FILE" ] && KEY_FILE="$CERT_DIR/$CERT_NAME.key"
  
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
  if [ -z "$CACERTS_FILE" ] ; then
    CACERTS_FILE="$(find / -iname cacerts -type f | head -1 2> /dev/null)"
  fi
  [ -z "$CERT_FILE" ] && CERT_FILE="/opt/kuali/certs/${DEFAULT_CERT_NAME}.crt"

  keytool \
    -importcert \
    -alias kuali-self-signed-cert \
    -storepass changeit \
    -noprompt \
    -keystore $CACERTS_FILE \
    -file $CERT_FILE
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
  create-config)
    createConfigFile
    ;;
  create-cert)
    createCertificate
    ;;
  import-cert)
    importCertificate
    ;;
  
esac