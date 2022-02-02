# Periodic cleanup: remove registry originated images that are over 6 months old
pruneOldRegistryImages() {
  [ "$DRYRUN" == 'true' ] && echo "DRYRUN: pruneOldRegistryImages..." && return 0
  echo "Removing coeus images tagged for the registry over 6 months ago..."
  docker rmi $(
    docker images | \
      grep "$AWS_ACCOUNT_ID" | \
      awk '(($4 >= 6 && $5 == "months") || ($5 == "years")) && ($1 ~ /^.*\/coeus(\-feature)?$/) {
        print $3
      }'\
  ) 2> /dev/null && \
  docker rmi $(docker images -a --filter dangling=true -q) 2> /dev/null || true
}

# If the base tomcat image is not in the local repo, get it from the registry
# default value is being invoked through calling this job using the jenkins-cli build function with the corresponding parameter omitted.
# NOTE: If you run this job manually, the default value will be reflected in the environment variable.
getTomcatDockerImage() {
  BASE_IMAGE_TAG="java${JAVA_VERSION}-tomcat${TOMCAT_VERSION}"
  TOMCAT_REGISTRY_IMAGE="${ECR_REGISTRY_URL}/${BASE_IMAGE_REPO}:${BASE_IMAGE_TAG}"
  TOMCAT_LOCAL_IMAGE="bu-ist/${BASE_IMAGE_REPO}:${BASE_IMAGE_TAG}"
  if [ -z "$(docker images -q ${TOMCAT_LOCAL_IMAGE})" ]; then
    echo "CANNOT FIND DOCKER IMAGE: ${TOMCAT_LOCAL_IMAGE}";
    if [ -z "$(docker images -q ${TOMCAT_REGISTRY_IMAGE})" ]; then 
        echo "CANNOT FIND DOCKER IMAGE: ${TOMCAT_REGISTRY_IMAGE}"; 
        echo "Pulling ${TOMCAT_REGISTRY_IMAGE} from registry..."
        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY_URL}
        docker pull ${TOMCAT_REGISTRY_IMAGE}
    fi
    echo "Tagging ${TOMCAT_REGISTRY_IMAGE}"
    docker tag ${TOMCAT_REGISTRY_IMAGE} ${TOMCAT_LOCAL_IMAGE}
  fi
}

# Fetch and reset the code from the git repository containing the docker build context
refreshBuildCode() {
  [ "$DRYRUN" == 'true' ] && echo "DRYRUN: refreshBuildCode..." && return 0
  eval `ssh-agent -k` || true
  eval `ssh-agent -s`
  ssh-add ~/.ssh/bu_github_id_docker_rsa
  if [ -d kuali-research-docker ] ; then
    rm -f -r kuali-research-docker
  fi
  mkdir kuali-research-docker
  cd kuali-research-docker
  git init	
  git config user.email "jenkins@bu.edu"
  git config user.name jenkins
  git config core.sparseCheckout true
  git remote add github git@github.com:bu-ist/kuali-research-docker.git
  echo kuali-research >> .git/info/sparse-checkout
  echo bash.lib.sh >> .git/info/sparse-checkout
  git fetch github master
  git checkout master 
  eval `ssh-agent -k`
}

checkCentosImage() {
  [ "$DRYRUN" == 'true' ] && echo "DRYRUN: checkCentosImage..." && return 0
  local ecrImage="$ECR_REGISTRY_URL/${BASE_IMAGE_REPO}:${TOMCAT_VERSION}"
  local localImage="bu-ist/${BASE_IMAGE_REPO}:${TOMCAT_VERSION}"
  if [ "$(docker images -q $localImage | wc -l)" == "0" ] ; then
    if [ "$(docker images -q $ecrImage | wc -l)" == "0" ] ; then
      evalstr="$(aws ecr get-login)"
      evalstr="$(echo $evalstr | sed 's/ -e none//')"
      eval $evalstr
      docker pull $ecrImage
    fi
    docker tag $ecrImage $localImage
  fi
}


# Since the $SOURCE_WAR artifact exists outside the docker build context we cannot execute the COPY 
# instruction in the Dockerfile against $SOURCE_WAR because we are implementing jenkins security 
# and docker gets challenged for authentication while trying to the war file from this link. So, 
# preferably, we would have a RUN instruction in the Dockerfile that curls the jenkins war artifact 
# into the image while it is building, or use the ADD instruction - and the build command would be:
#
#    docker build -t ${DOCKER_TAG} --build-arg SOURCE_WAR=${JENKINS_WAR_URL} ${DOCKER_BUILD_CONTEXT}
#
# However, the ADD instruction does
# not support authentication and I have not been able to make wget or curl with authentication work 
# from a RUN instruction within the Dockerfile for this same link. Therefore we must get our war 
# file into the build context manually where we can use ADD (or COPY) with a relative file location.
# Therefore, the standard docker build command with a context referring to a git repo also cannot be used
# because it clones the build context to some unknown directory in /tmp.
# Therefore, we will checkout the build context to a known location within the jenkins build context, copy
buildDockerImage() {

  cd kuali-research/build.context

  # Copy the war file to the docker build context
  [ "$DRYRUN" == 'true' ] && echo "DRYRUN: copyWarToBuildContext..." && return 0
  cp -v $JENKINS_WAR_FILE .
  WAR_FILE=$(ls *.war)
  
  # The git readme file says you don't need to do this for tomcat 9.x and above, but still getting ClassNotFoundException from KcConfigVerifier 
  [ "$DRYRUN" == 'true' ] && echo "DRYRUN: copySpringInstrumentJarToBuildContext..." && return 0
  cp -v $SPRING_INSTRUMENT_JAR ./spring-instrument.jar
  SPRING_INSTRUMENT_JAR='spring-instrument.jar'

  # checkCentosImage
  outputSubHeading "Docker build context:"
  echo "$(pwd):"
  ls -la
  echo " "
  local cmd="docker build -t ${DOCKER_TAG} \\
    --build-arg SOURCE_WAR=${WAR_FILE} \\
    --build-arg SPRING_INSTRUMENT_JAR=${SPRING_INSTRUMENT_JAR} \\
    --build-arg JAVA_VERSION=${JAVA_VERSION} \\
    --build-arg REPO_URI=${ECR_REGISTRY_URL}/${BASE_IMAGE_REPO} \\
    --build-arg TOMCAT_VERSION=${TOMCAT_VERSION} ."
  
  echo "$cmd"
  [ "$DRYRUN" != 'true' ] && eval "$cmd"
}

removeDanglingImages() {
  echo "Removing dangling images..."
  docker rmi $(docker images -a --filter dangling=true -q) 2> /dev/null || true
}

# Define variables.
# NOTE: JENKINS_URL is the full URL of Jenkins, like http://server:port/jenkins/ 
#       Only available if Jenkins URL is set in system configuration
setDefaults() {
  [ -z "$BASE_IMAGE_REPO" ] && BASE_IMAGE_REPO='kuali-centos7-java-tomcat'
  [ -z "$JAVA_VERSION" ] && JAVA_VERSION=11
  [ -z "$TOMCAT_VERSION" ] && TOMCAT_VERSION='9.0.41'
  AWS_ACCOUNT_ID="$(echo "$ECR_REGISTRY_URL" | cut -d '.' -f1)"
  AWS_REGION="$(echo "$ECR_REGISTRY_URL" | cut -d '.' -f4)"
  DOCKER_TAG="${ECR_REGISTRY_URL}/${REGISTRY_REPO_NAME}:${POM_VERSION}"
  # DOCKER_BUILD_CONTEXT="git@github.com:bu-ist/kuali-research-docker.git#${DOCKER_BUILD_CONTEXT_GIT_BRANCH}:kuali-research/build.context"

  outputSubHeading "Parameters:"
  echo "BASE_IMAGE_REPO=$BASE_IMAGE_REPO"
  echo "JAVA_VERSION=$JAVA_VERSION"
  echo "TOMCAT_VERSION=$TOMCAT_VERSION"
  echo "ECR_REGISTRY_URL=$ECR_REGISTRY_URL"
  echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
  echo "AWS_REGION=$AWS_REGION"
  echo "POM_VERSION=$POM_VERSION"
  echo "REGISTRY_REPO_NAME=$REGISTRY_REPO_NAME"
  echo "DOCKER_TAG=$DOCKER_TAG"
  # echo "DOCKER_BUILD_CONTEXT=$DOCKER_BUILD_CONTEXT"
  echo "JENKINS_WAR_FILE=$JENKINS_WAR_FILE"
  echo "SPRING_INSTRUMENT_JAR=$SPRING_INSTRUMENT_JAR"
  echo " "

  local msg=""
  appendMessage() {
    [ -n "$msg" ] && msg="$msg, $1" || msg="$1"
  }

  [ -z "$BASE_IMAGE_REPO" ] && appendMessage "BASE_IMAGE_REPO"
  [ -z "$JAVA_VERSION" ] && appendMessage "JAVA_VERSION"
  [ -z "$TOMCAT_VERSION" ] && appendMessage "TOMCAT_VERSION"
  [ -z "$ECR_REGISTRY_URL" ] && appendMessage "ECR_REGISTRY_URL"
  [ -z "$AWS_ACCOUNT_ID" ] && appendMessage "AWS_ACCOUNT_ID"
  [ -z "$AWS_REGION" ] && appendMessage "AWS_REGION"
  [ -z "$POM_VERSION" ] && appendMessage "POM_VERSION"
  [ -z "$REGISTRY_REPO_NAME" ] && appendMessage "REGISTRY_REPO_NAME"
  # [ -z "$DOCKER_BUILD_CONTEXT" ] && appendMessage "DOCKER_BUILD_CONTEXT"
  [ -z "$JENKINS_WAR_FILE" ] && appendMessage "JENKINS_WAR_FILE"
  [ ! -f "$JENKINS_WAR_FILE" ] && appendMessage "JENKINS_WAR_FILE [$JENKINS_WAR_FILE not found]"
  [ -z "$SPRING_INSTRUMENT_JAR" ] && appendMessage "SPRING_INSTRUMENT_JAR"
  [ ! -f "$SPRING_INSTRUMENT_JAR" ] && appendMessage "SPRING_INSTRUMENT_JAR [$SPRING_INSTRUMENT_JAR not found]"
  [ -n "$msg" ] && echo "ERROR missing parameter(s): $msg"

  [ -z "$msg" ] && true || false
}

checkTestHarness $@ 2> /dev/null || true

parseArgs $@

isDebug && set -x

if setDefaults ; then

  pruneOldRegistryImages

  getTomcatDockerImage

  refreshBuildCode

  buildDockerImage

  removeDanglingImages
else
  exit 1
fi