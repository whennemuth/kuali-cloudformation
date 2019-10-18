#!/bin/bash

# Print out a command line usage readout.
printusage() {
  cat <<EOF

USAGE: sh docker.sh [OPTIONS]

  Options:

    --task    What docker task is to be performed?
                "build":   Build the docker image
                "rebuild": Build the docker image without using the cache (builds from scratch) 
                "run":     Run the docker container
                "rerun":   Build the docker image AND run the container
                "publish": Tag the last built docker image indicated by the --service arg and push to dockerhub
    --service What application is being built/run (kc|coi)
    --ssl     Build the image so it will have certs/keys and force redirect to ssl
    --help    Print out this usage readout.
  
EOF
}

# Destroy the container indicated by the service parameter
killContainer() {
  echo "Killing cointainer $CONTAINER_NAME"
  docker rm -f $CONTAINER_NAME > /dev/null 2>&1
}

# Build the image based on the provided command line parameters.
build() {
  local cachearg="$1"
  killContainer
  local target="HTTP"
  [ -n "$SSL" ] && target="HTTPS"
  docker build $cachearg --build-arg SERVICE=${SERVICE^^} --target $target -t $IMAGE_NAME .
  # Remove all dangling images
  docker rmi $(docker images --filter dangling=true -q) > /dev/null 2>&1
}

# Build the image based on the provided command line parameters, ignoring any cached image layers (build from scratch).
rebuild() {
  killContainer
  build "--no-cache"
}

# Run the container based on the provided command line parameters.
# NOTE: you cannot run both kc and coi container using https at the same time because only one container can bind to port 443 at a time.
run() {
  local hostport="8080"
  [ "$SERVICE" == "coi" ] && hostport="8082"
  if [ -n "$SSL" ] ; then
    docker run -d -p $hostport:8080 -p 443:443 -e "SERVICE=$SERVICE" --name $CONTAINER_NAME $IMAGE_NAME
  else
    docker run -d -p $hostport:8080 -e "SERVICE=$SERVICE" --name $CONTAINER_NAME $IMAGE_NAME
  fi
}

# Build the image AND run the related container based on the provided command line parameters.
rerun() {
  echo "Building and running from scratch..."
  build
  [ $? -eq 0 ] && run
}

# Publish the image based on the provided parameters to dockerhub.
# NOTE: Hardcoding the tag here for convenience.
publish() {
  echo "Publishing to wrh1/"
  # Remove all dangling images
  docker rmi $(docker images --filter dangling=true -q) > /dev/null 2>&1

  docker tag dummy-kuali-$SERVICE wrh1/$IMAGE_NAME:1906.0021
  docker push wrh1/$IMAGE_NAME:1906.0021  
}

# Parse the args and make them environment variables
while (( "$#" )); do
  case "$1" in 
    --task)
      TASK="${2,,}" ;;
    --service)
      SERVICE="${2,,}" 
      CONTAINER_NAME="dummy-$SERVICE"
      IMAGE_NAME="dummy-kuali-$SERVICE" ;;
    --ssl)
      SSL="true" ;;
    --publish)
      PUBLISH="true" ;;
    --help)
      printusage && exit 0 ;;
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
