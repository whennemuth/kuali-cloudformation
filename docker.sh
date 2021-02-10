#!/bin/bash


startSecretsServer() {
  docker rm -f secrets_server 2> /dev/null
  docker run \
    --rm \
    --name secrets_server \
    -v $(getSecretBindMount) \
    -d \
    -p 8095:80 \
    nginx

    SECRETS_SERVER_IP=$(docker inspect -f {{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}} secrets_server)
}

build() {
  if ready ; then
    if usingKeyFile ; then
      echo "RSA key detected in secrets directory. Will connect to github using ssh."
      startSecretsServer
      docker build \
        -t kuali-infrastructure 
        --build-arg DATETIME=$(date +'%s') 
        --add-host=secrets:$SECRETS_SERVER_IP \
        .
    else
      echo "The file in the secrets directory appears to be a personal access token."
      printf "Please enter your github username: "
      read username
      if [ -z "$username" ] ; then
        echo "No username entered. Cancelling..."
        exit 1
      fi
      startSecretsServer
      docker build \
        -t kuali-infrastructure \
        --build-arg DATETIME=$(date +'%s') \
        --build-arg GIT_USERNAME=$username \
        --add-host=secrets:$SECRETS_SERVER_IP \
        .
    fi
    # docker stop secrets_server
  fi
}

ready() {
  local msg=''
  if [ $(ls -1 | grep 'kuali_' | wc -l) -eq 0 ] ; then
    msg="You do not appear to be in the root directory of this repository!"
  elif [ -z "$(ls -1 Dockerfile 2> /dev/null)" ] ; then
    msg="Dockerfile is missing from the current directory!"
  elif [ ! -d secrets ] || [ $(ls -1 secrets | wc -l) -ne 1 ] ; then
    msg=$(cat <<EOF
You must create "secrets" directory under the root folder of this repository.
Deposit a single file in this directory:
  a) Your git ssh key for access to the kuali infrastructure repository
  or...
  b) Your personal access token for access to the kuali infrastructure repository"
EOF
     )
  fi
  [ -n "$msg" ] && echo "$msg"
  [ -z "$msg" ] && true || false
}

detectOS() {
  local os="$(echo $OSTYPE)"
  [ -n "$(echo "$os" | grep -iP '(msys)|(windows)')" ] && echo "windows" && return 0
  [ -n "$(echo "$os" | grep -iP 'linux')" ] && echo "linux" && return 0
  # Assuming only 3 types of operating systems for now.
  echo "mac"
}
isWindows() { [ "$(detectOS)" == "windows" ] && true || false; }
isLinux() { [ "$(detectOS)" == "linux" ] && true || false; }
isMac() { [ "$(detectOS)" == "mac" ] && true || false; }

# Convert a UNIX path to a DOS path if on windows (forward slash to double backslash), if not already.
# Assumes that any UNIX path starting with a single letter path segment (like /c/) refers to a DOS drive letter.
convertPath() {
  if isWindows ; then
    echo "$1" | sed -r 's/^\/([a-zA-Z])\//\1:\\\\/' | sed 's/\//\\\\/g'
  else
    echo "$1"
  fi
}

getSecretBindMount() {
  local file=$(ls -1 secrets)
  local path=$(pwd)/secrets/$file
  local bindSource=$(convertPath $path)
  local bindTarget=/usr/share/nginx/html
  if usingKeyFile ; then
    bindTarget=$bindTarget/rsa:ro
  else
    bindTarget=$bindTarget/token:ro
  fi
  echo ${bindSource}:${bindTarget}
}

usingKeyFile() {
  local file=$(ls -1 secrets)
  beginkey=$(cat secrets/$file | grep 'BEGIN' | grep 'KEY')
  endkey=$(cat secrets/$file | grep 'END' | grep 'KEY')
  [ -n "$beginkey" ] && [ -n "$endkey" ]
}

task="$1"
shift 

case "$task" in
  build) build ;;
  secrets) startSecretsServer ;;
  test) 
    echo 'hello' $@ 
    env
    ;;
  tunnel)
    cd kuali_rds/jumpbox
    sh tunnel.sh $@
    ;;
esac