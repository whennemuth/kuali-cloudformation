
#!/bin/bash

# You must source common-functions.sh for some functionality used below.

checkTestHarness $@ 2> /dev/null || true

set -a

parseArgs

isDebug && set -x

validParameters() {
  local msg=""
  appendMessage() {
    [ -n "$msg" ] && msg="$msg, $1" || msg="$1"
  }

  outputSubHeading "Validating parameters & setting defaults..."

  JENKINS_HOME=${JENKINS_HOME:-"/var/lib/jenkins"}
  [ ! -d "$JENKINS_HOME" ] && appendMessage 'JENKINS_HOME'
  MAVEN_WORKSPACE=${MAVEN_WORKSPACE:-"$JENKINS_HOME/latest-maven-build/kc"}
  [ ! -d "$(dirname $MAVEN_WORKSPACE)" ] && appendMessage "[No such directory: $(dirname $MAVEN_WORKSPACE)]"
  POM=${MAVEN_WORKSPACE}/pom.xml
  WARFILE_DIR=${MAVEN_WORKSPACE}/coeus-webapp/target
  BACKUP_DIR=$JENKINS_HOME/backup/kuali-research/war
  SCRIPT_DIR=${SCRIPT_DIR:-"$JENKINS_HOME/kuali-infrastructure/kuali_jenkins/bash-scripts/job"}
  CHECK_DEPENDENCIES=${CHECK_DEPENDENCIES:-"true"}
  GIT_REPO_URL=${GIT_REPO_URL:-"git@github.com:bu-ist/kuali-research.git"}
  S3_BUCKET=${S3_BUCKET:-"kuali-conf"}

  echo "JENKINS_HOME=$JENKINS_HOME"
  echo "MAVEN_WORKSPACE=$MAVEN_WORKSPACE"
  echo "POM=$POM"
  echo "WARFILE_DIR=$WARFILE_DIR"
  echo "BACKUP_DIR=$BACKUP_DIR"
  echo "SCRIPT_DIR=$SCRIPT_DIR"
  echo "CHECK_DEPENDENCIES=$CHECK_DEPENDENCIES"
  echo "GIT_REPO_URL=$GIT_REPO_URL"
  echo "GIT_REF_TYPE=$GIT_REF_TYPE"
  echo "GIT_REF=$GIT_REF"
  echo "GIT_COMMIT_ID=$GIT_COMMIT_ID"
  echo "BRANCH=$BRANCH"
  echo "S3_BUCKET=$S3_BUCKET"
 
  [ -n "$msg" ] && echo "ERROR missing/invalid parameter(s): $msg"

  [ -z "$msg" ] && true || false
}

pullFromGithub() {
  outputSubHeading "Fetching $GIT_REF from $GIT_REPO_URL ..."
  (
    githubFetchAndReset \
      "rootdir=$MAVEN_WORKSPACE" \
      "repo=$GIT_REPO_URL" \
      "key=~/.ssh/bu_github_id_kc_rsa" \
      "reftype=$GIT_REF_TYPE" \
      "ref=$GIT_REF" \
      "commit=$GIT_COMMIT_ID" \
      "user=jenkins@bu.edu"
  )
  [ $? -eq 0 ] && true || false
}

checkDependencies() {
  outputSubHeading "M2 Dependency check (schemaspy, rice, coeus-api, s2sgen)..."
  [ "$CHECK_DEPENDENCIES" != 'true' ] && return 0
  sh -e $SCRIPT_DIR/kuali-dependency-check.sh "POM=$POM"
}

warExists() {
  WAR_FILE=$(ls -1 $WARFILE_DIR | grep -P "^.*war$")
  # Confirm the war file has been found
  if [ -f "$WAR_FILE" ]; then
    echo "Found war file: $WAR_FILE"
    local found="true"
  else
    echo "CANNOT FIND WAR FILE!!!";
    echo "EXITING BUILD.";
  fi  
  [ "$found" == 'true' ] && true || false
}

buildWithMaven() {
  outputSubHeading "Performing maven build..."

  # mvn clean compile install \
  #   -Dgrm.off=true \
  #   -Dmaven.test.skip=true \
  #   -Dbuild.version="${UPCOMING_POM_VERSION}" \
  #   -Dbuild.bu.git.ref="git:branch=${GIT_BRANCH},ref=${GIT_COMMIT}" \
  #   -Dclean-jsfrontend-node.off

  warExists && true || false
}

# Insert a copy of the log4j-appserver jar file into the WEB-INF/lib directory of the war file.
packLog4jAppserverJar() {
  outputSubHeading "Packing log4j-appserver into war file..."
  local pom="$1"
  # Get the content of the pom file with all return/newline characters removed.
  local content=$(set +x; cat ${pom} | sed ':a;N;$!ba;s/\n//g')

  # repo="${JENKINS_HOME}/.m2/repository"
  # If the local repo location has been customized in settings.xml, then we need to parse it from maven help plugin output.
  local repo=$(echo $(mvn help:effective-settings | grep 'localRepository') | cut -d '>' -f 2 | cut -d '<' -f 1)
  echo ".m2 repository: ${repo}"

  # Find a copy of the log4j-appserver jar file for the main kuali-research war file building job and copy it to its workspace.
  echo "Looking for the log4j-appserver jar file (was built for test scope, but need it for runtime scope)"
  local vLog4j=$(echo "$content" | grep -Po '(?<=<log4j\.version>)([^<]+)')
  if [ -n "$vLog4j" ] ; then
    local jar=$(find $repo -iname log4j-appserver-${vLog4j}.jar)
    if [ -f $jar ] ; then
      # The WEB-INF/lib directory should be wherever you find a copy of the log4j-core jar file (it had runtime scope and maven put it in war file)
      local libdir=$(dirname $(find $WARFILE_DIR -iname log4j-core-*.jar))
      # Copy the log4j-appserver jar to the lib directory
      echo "cp $jar $libdir"
      cp $jar $libdir/
      # Navigate to the lib directory and then go 2 directories up (parent of WEB-INF, root)
      echo "cd \$(dirname \$(dirname $libdir))"
      cd $(dirname $(dirname $libdir))
      # Get the war file pathname and inject the log4j-appserver jar file into its WEB-INF/lib directory
      local warfile=$(find $WARFILE_DIR -iname coeus-webapp-*.war)
      local jarname=$(ls -la -x $libdir | grep log4j-appserver)
      echo "jarname \$(ls -la -x $libdir | grep log4j-appserver)"
      echo "jar -uf $warfile WEB-INF/lib/$jarname"
      jar -uf $warfile WEB-INF/lib/$jarname
      local success='true'
    else
      echo "ERROR! Could not find log4j-appserver-${vLog4j}.jar in maven local repository"
    fi
  else
    echo "ERROR! could not find log4j-appserver version in ${pom}"
  fi
  [ "$success" == 'true' ] && true || false
}

backupWar() {
  outputSubHeading "Backing up war file..."
  # Backup the war file. This keeps war files with the same name but from different git branches
  # from overwriting each other in the jenkins workspace on subsequent builds.
  if [ ! -d ${BACKUP_DIR}/${BRANCH} ] ; then 
    mkdir -p ${BACKUP_DIR}/${BRANCH} 
  fi
  # Clear out the backup dir (ensures only one war file and no space-consuming buildup)
  rm -f -r ${BACKUP_DIR}/${BRANCH}/*
  # Copy the war file from the maven target directory to the backup directory
  cp -f ${WARFILE_DIR}/${WAR_FILE} ${BACKUP_DIR}/${BRANCH}/
}

if validParameters ; then

  if pullFromGithub ; then

    if checkDependencies ; then

      if buildWithMaven ; then

        if packLog4jAppserverJar ; then

          backupWar && local success='true'
        fi
      fi
    fi
  fi
fi

if [ "$success" == 'true' ] ; then
  echo "FINISHED BUILDING WAR ARTIFACT!"
else
  exit 1
fi
