#!/bin/bash

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat/jenkins.io.key
# sudo yum --showduplicates list jenkins | expand
yum install jenkins -y
# yum install --nogpgcheck jenkins-2.150-1.1 -y

sudo usermod -a -G docker jenkins
sudo usermod --shell /bin/bash jenkins
sudo chkconfig --add jenkins

# Turn off Jenkins Content Security Policy to allow for javascript in jobs (for better active choices reactive parameter behavior)
if [ -f /etc/sysconfig/jenkins ] ; then
  sed -i 's/JENKINS_JAVA_OPTIONS="/JENKINS_JAVA_OPTIONS="-Dhudson.model.DirectoryBrowserSupport.CSP= /' /etc/sysconfig/jenkins
fi

printf "\n\n"
