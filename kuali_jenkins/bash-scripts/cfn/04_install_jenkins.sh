#!/bin/bash

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat/jenkins.io.key
# sudo yum --showduplicates list jenkins | expand
jenkinsVersion=${JENKINS_VERSION:-'jenkins-2.322-1.1'}
if [ "${jenkinsVersion,,}" == 'latest' ] ; then
  yum install jenkins -y
else
  yum install --nogpgcheck $jenkinsVersion -y
fi

sudo usermod -a -G docker jenkins
sudo usermod --shell /bin/bash jenkins
sudo chkconfig --add jenkins

# Turn off Jenkins Content Security Policy to allow for javascript in jobs (for better active choices reactive parameter behavior)
if [ -f /etc/sysconfig/jenkins ] ; then
  sed -i 's/JENKINS_JAVA_OPTIONS="/JENKINS_JAVA_OPTIONS="-Dhudson.model.DirectoryBrowserSupport.CSP= /' /etc/sysconfig/jenkins
fi

printf "\n\n"
