#!/bin/bash

killContainer() {
  echo "Killing cointainer dummy-$SERVICE"
  docker rm -f dummy-$SERVICE > /dev/null 2>&1
}

build() {
  local cachearg="$1"
  killContainer
  local target="HTTP"
  [ -n "$SSL" ] && target="HTTPS"
  docker build $cachearg --build-arg SERVICE=${SERVICE^^} --target $target -t dummy-kuali-$SERVICE .
}

rebuild() {
  killContainer
  build "--no-cache"
}

run() {
  local hostport="8080"
  [ "$SERVICE" == "coi" ] && hostport="8082"
  if [ -n "$SSL" ] ; then
    docker run -d -p $hostport:8080 -p 443:443 -e "SERVICE=$SERVICE" --name dummy-$SERVICE dummy-kuali-$SERVICE
  else
    docker run -d -p $hostport:8080 -e "SERVICE=$SERVICE" --name dummy-$SERVICE dummy-kuali-$SERVICE
  fi
}

rerun() {
  echo "Building and running from scratch..."
  build
  [ $? -eq 0 ] && run
}

# Parse the args and make them environment variables
while (( "$#" )); do
  case "$1" in 
    --task)
      TASK="${2,,}" ;;
    --service)
      SERVICE="${2,,}" ;;
    --ssl)
      SSL="true" ;;
    --publish)
      PUBLISH="true" ;;
  esac
  shift
done

# Validate the args
[ -z "$TASK" ] && echo "Missing task!" && printusage && exit 1
[ -z "$SERVICE" ] && echo "Missing service!" && printusage && exit 1
[ $SERVICE != "kc" ] && [ $SERVICE != "coi" ] && echo "Invalid value for service: $SERVICE" && printusage && exit 1


case "$TASK" in
  'build') build ;;
  'rebuild') rebuild ;;
  'run') run ;;
  'rerun') rerun ;;
  'publish') publish ;;
  *) echo 'Invalid task: $TASK' && printusage && exit 1 ;;
esac

printusage() {
  cat <<EOF

USAGE: sh docker.sh [OPTIONS]

  Options:

    --task    What docker task is to be performed?
                  "build": Build the docker image
                "rebuild": Build the docker image without using the cache (builds from scratch) 
                    "run": Run the docker container
                  "rerun": Build the docker image AND run the container
                "publish": Tag the last built docker image indicated by the --service arg and push to dockerhub
    --service What SERVICElication is being build (kc|coi)
    --ssl     Build the image so it will have certs/keys and force redirect to ssl
  
EOF
}