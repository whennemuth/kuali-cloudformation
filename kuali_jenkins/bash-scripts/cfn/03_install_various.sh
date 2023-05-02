#!/bin/bash

# daemonize was not required by jenkins.noarch 0:2.276-1.1, but is for jenkins.noarch 0:2.320-1.1
amazon-linux-extras install epel -y
yum install daemonize -y

# Install docker
amazon-linux-extras install -y docker
service docker start
usermod -a -G docker ec2-user
chkconfig docker on

# Replace version 1 of awscli with version 2
cliVersion=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2 | cut -d'.' -f1)
case "$cliVersion" in
  1)
    # Upgrade to version 2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install --bin-dir /bin --install-dir /usr/local/aws-cli --update
    aws --version
    ;;
  2)
    # Update version 2
    aws --version
    ;;
esac

# Make ssm-user a sudoer
sudo usermod -a -G sudo ssm-user 2> /dev/null

source /var/lib/jenkins/_cfn-scripts/java_version.sh
if [ "${JavaVersion}" == '8' ] ; then
  sudo yum install -y java-1.8.0-openjdk -y
  javaExe=$(namei -v $(which javac) | grep -P '^l\s+' | tail -1 | awk '{print $4}')                  
else
  echo "Installing amazon coretto 11..."
  sudo yum install -y java-11-amazon-corretto
  # javaExe=$(namei -v $(which javac) | grep -P '^l\s+' | tail -1 | awk '{print $4}')                  
  javaExe=$(update-alternatives --list | grep -E '^javac\s' | awk '{print $3}')
fi
JAVA_HOME=$(dirname $(dirname $javaExe))
echo "JAVA_HOME = $JAVA_HOME"
echo "" >> /etc/bashrc
echo "JAVA_HOME=$JAVA_HOME" >> /etc/bashrc
echo "JAVA_HOME=$JAVA_HOME" >> ../_cfn-config/env.sh

# Install maven
mkdir -p /usr/share/maven \
&& curl -fsSL http://apache.osuosl.org/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.tar.gz \
  | tar -xzC /usr/share/maven --strip-components=1 \
&& ln -s /usr/share/maven/bin/mvn /usr/bin/mvn
echo "MAVEN_HOME=/usr/share/maven" >> /etc/bashrc
echo "MAVEN_HOME=/usr/share/maven" >> ../_cfn-config/env.sh
mvn --version

# Install nginx
amazon-linux-extras install -y nginx1

# Install node
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.34.0/install.sh | bash
mkdir /.nvm
export NVM_DIR='/.nvm'
. /.nvm/nvm.sh
# nvm install node
nvm install 17.6.0

# For some reason, nvm may not create symlinks to npm and/or node, so check and correct if necessary.
if [ -z "$(ls -1 /usr/bin | grep 'npm')" ] ; then
  echo "Symlink for npm wasn't created by nvm during install, creating now..."
  ln -s $(find /.nvm -type f -iname npm-cli.js) /usr/bin/npm
fi
if [ -z "$(ls -1 /usr/bin | grep 'node')" ] ; then
  echo "Symlink for node wasn't created by nvm during install, creating now..."
  ln -s $(find /.nvm -type f -iname node) /usr/bin/node
fi
echo "npm version: $(sh -c 'npm --version')"
echo "node version: $(sh -c 'node --version')"

printf "\n\n"