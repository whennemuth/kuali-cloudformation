#!/bin/bash

cfgdir=/var/lib/jenkins/_cfn-config
srcdir=/var/lib/jenkins/_cfn-scripts

source $srcdir/utils.sh

# Set various parameters to be injected into above collection of config xml files.
cat <<EOF >> $cfgdir/env.sh
JAVA_SHORTNAME=$(echo "${JAVA_HOME}" | rev | cut -d'/' -f1 | rev)
JENKINS_VERSION=$(java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 version)
MAVEN_SHORTNAME=$(sudo mvn --version | grep -oP 'Maven (\d\.?)+' | sed 's/ /-/g')
MAVEN_PLUGIN_VERSION=$(java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 list-plugins | grep -E '^maven-plugin\s' | grep -oP '(\d\.?){2,}' | head -1)
CREDENTIALS_PLUGIN_VERSION=$(java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 list-plugins | grep -E '^credentials\s' | grep -oP '(\d\.?){2,}' | head -1)
PLAIN_CREDENTIALS_PLUGIN_VERSION=$(java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 list-plugins | grep -E '^plain-credentials\s' | grep -oP '(\d\.?){2,}' | head -1)
SSH_CREDENTIALS_PLUGIN_VERSION=$(java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 list-plugins | grep -E '^ssh-credentials\s' | grep -oP '(\d\.?){2,}' | head -1)
EOF

cat $cfgdir/env.sh
source $cfgdir/env.sh

# Replace placeholders in these config xml files with their values now that they're known
# This will also turn security for jenkins back on again.
echo "Modifying config.xml..."
sed "s|JENKINS_VERSION|$JENKINS_VERSION|" $cfgdir/config.xml | \
sed "s|JAVA_HOME|$JAVA_HOME|" | \
sed "s|JAVA_SHORTNAME|$JAVA_SHORTNAME|" > config.xml

echo "Setting MAVEN_HOME in hudson.tasks.Maven.xml..."
sed "s|MAVEN_HOME|$MAVEN_HOME|" $cfgdir/hudson.tasks.Maven.xml | \
sed "s|MAVEN_SHORTNAME|$MAVEN_SHORTNAME|" > hudson.tasks.Maven.xml

# In case any of the credentials plugins have been manually updated, correct them in files before importing.
echo "Ensuring correct credentials plugin version..."
sed -i 's/maven-plugin@[0-9\.]\+/maven-plugin@'$MAVEN_PLUGIN_VERSION'/' $cfgdir/hudson.maven.MavenModuleSet.xml
sed -i 's/credentials@[0-9\.]\+/credentials@'$CREDENTIALS_PLUGIN_VERSION'/' $cfgdir/credentials.kualico.github.xml
sed -i 's/credentials@[0-9\.]\+/credentials@'$CREDENTIALS_PLUGIN_VERSION'/' $cfgdir/credentials.kualico.dockerhub.xml
echo "Ensuring correct plain-credentials plugin version..."
sed -i 's/plain-credentials@[0-9\.]\+/plain-credentials@'$PLAIN_CREDENTIALS_PLUGIN_VERSION'/' $cfgdir/credentials.bu.github.token.xml
sed -i 's/plain-credentials@[0-9\.]\+/plain-credentials@'$PLAIN_CREDENTIALS_PLUGIN_VERSION'/' $cfgdir/credentials.newrelic.license.key.xml
echo "Ensuring correct ssh-credentials plugin version..."
sed -i 's/ssh-credentials@[0-9\.]\+/ssh-credentials@'$SSH_CREDENTIALS_PLUGIN_VERSION'/' $cfgdir/credentials.github.ssh.bu-ist.kc.xml
sed -i 's/ssh-credentials@[0-9\.]\+/ssh-credentials@'$SSH_CREDENTIALS_PLUGIN_VERSION'/' $cfgdir/credentials.github.ssh.bu-ist.rice.xml

# Create all credentials by importing their corresponding xml files.
for credxml in $(ls -1 $cfgdir | grep credentials.) ; do
  echo "Importing $credxml..."
  java -jar $JENKINS_CLI_JAR $(getAdminUserCliParm) -s http://localhost:8080 create-credentials-by-xml system::system::jenkins _ < $cfgdir/$credxml
done

createTokenFile

resetAdminPassword 'bcrypt'

chown -R jenkins:jenkins $JENKINS_HOME

restartJenkins

printf "\n\n"
