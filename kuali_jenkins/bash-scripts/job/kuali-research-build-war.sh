
#!/bin/bash

# You must source common-functions.sh for some functionality used below.

checkTestHarness $@ 2> /dev/null || true

parseArgs

isDebug && set -x

printParameters() {
  # For a multibranch project, this will be set to the name of the branch being built, for example in case you wish to deploy to production from master but not from feature branches.
  echo "BRANCH_NAME = ${BRANCH_NAME}"
  # The current build number, such as "153"
  echo "BUILD_NUMBER = ${BUILD_NUMBER}"
  # The current build ID, identical to BUILD_NUMBER for builds created in 1.597+, but a YYYY-MM-DD_hh-mm-ss timestamp for older builds
  echo "BUILD_ID = ${BUILD_ID}"
  # The display name of the current build, which is something like "#153" by default.
  echo "BUILD_DISPLAY_NAME = ${BUILD_DISPLAY_NAME}"
  # Name of the project of this build, such as "foo" or "foo/bar".
  echo "JOB_NAME = ${JOB_NAME}"
  # Short Name of the project of this build stripping off folder paths, such as "foo" for "bar/foo".
  echo "JOB_BASE_NAME = ${JOB_BASE_NAME}"
  # String of "jenkins-${JOB_NAME}-${BUILD_NUMBER}". Convenient to put into a resource file, a jar file, etc for easier identification. starts from 0, not 1.
  echo "BUILD_TAG = ${BUILD_TAG}"
  # The absolute path of the directory assigned to the build as a workspace.
  echo "WORKSPACE = ${WORKSPACE}"
  # The absolute path of the directory assigned on the master node for Jenkins to store data.
  echo "JENKINS_HOME = ${JENKINS_HOME}"
  # Full URL of Jenkins, like http://server:port/jenkins/ (note: only available if Jenkins URL set in system configuration)
  echo "JENKINS_URL = ${JENKINS_URL}"
  # Full URL of this build, like http://server:port/jenkins/job/foo/15/ (Jenkins URL must be set)
  echo "BUILD_URL = ${BUILD_URL}"
  # Full URL of this job, like http://server:port/jenkins/job/foo/ (Jenkins URL must be set)
  echo "JOB_URL = ${JOB_URL}"

  # These should all come from the maven project plugin
  echo "POM_DISPLAYNAME = ${POM_DISPLAYNAME}"
  echo "POM_VERSION = ${POM_VERSION}"
  echo "POM_GROUPID = ${POM_GROUPID}"
  echo "POM_ARTIFACTID = ${POM_ARTIFACTID}"
  echo "POM_PACKAGING = ${POM_PACKAGING}"
}

# Insert a copy of the log4j-appserver jar file into the WEB-INF/lib directory of the war file.
packLog4jAppserverJar() {
  local delegate="$1"
  if [ "$delegate" == 'true' ] ; then
    local cli=/var/lib/jenkins/jenkins-cli.jar
    local host=http://localhost:8080/
    [ -f /var/lib/jenkins/cli-credentials.sh ] && source /var/lib/jenkins/cli-credentials.sh
    java -jar ${cli} -s ${host} build 'kc-pack-log4j-appserver-jar' -v -f \
        -p POM=${WORKSPACE}/pom.xml \
        -p WARFILE_DIR=${WARFILE_DIR}
    return 0
  fi

  local pom="$1"
  # Get the content of the pom file with all return/newline characters removed.
  local content=$(cat ${pom} | sed ':a;N;$!ba;s/\n//g')

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
    else
      echo "ERROR! Could not find log4j-appserver-${vLog4j}.jar in maven local repository"
      exit 1
    fi
  else
    echo "ERROR! could not find log4j-appserver version in ${pom}"
    exit 1
  fi
}

backupWar() {
  WARFILE_DIR=${WORKSPACE}/coeus-webapp/target
  WAR_FILE=$(ls -1 $WARFILE_DIR | grep -P "^.*war$")
  WAR_URL=http://localhost:8080/job/${JOB_BASE_NAME}/ws/coeus-webapp/target/${WAR_FILE}
  BACKUP_DIR=/var/lib/jenkins/backup/kuali-research/war

  # Confirm the war file has been found
  if [ -z "${WARFILE}" ]; then
    echo "Found war file: ${WAR_FILE}"
    packLog4jAppserverJar
  else
    echo "CANNOT FIND WAR FILE!!!";
    echo "EXITING BUILD.";
    exit 1;
  fi      

  # Backup the war file. This keeps war files with the same name but from different git branches
  # from overwriting each other in the jenkins workspace on subsequent builds.
  if [ ! -d ${BACKUP_DIR}/${BRANCH} ] ; then 
    mkdir -p ${BACKUP_DIR}/${BRANCH} 
  fi
  # Clear out the backup dir (ensures only one war file and no space-consuming buildup)
  rm -f -r ${BACKUP_DIR}/${BRANCH}/*
  # Copy the war file from the maven target directory to the backup directory
  cp -f ${WORKSPACE}/coeus-webapp/target/${WAR_FILE} ${BACKUP_DIR}/${BRANCH}/
}

printParameters

backupWar

echo "FINISHED BUILDING WAR ARTIFACT!";
