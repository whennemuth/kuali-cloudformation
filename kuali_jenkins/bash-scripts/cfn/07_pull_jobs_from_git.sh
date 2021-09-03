#!/bin/bash

source /var/lib/jenkins/_cfn-scripts/utils.sh

# Adjust file/directory permissions
chmod 700 .ssh
ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts
ssh-keyscan -t rsa github.com >> $JENKINS_HOME/.ssh/known_hosts

# Configure github access
[ ! -d jobs ] && mkdir jobs
cd jobs
[ ! -d .git ] && git init
git config user.email "jenkins@bu.edu"
git config user.name jenkins
git remote add github git@github.com:bu-ist/kuali-research-jenkins.git

# Pull all main/job configuration files from github
eval `ssh-agent -s`
ssh-add ../.ssh/bu_github_id_jenkins_rsa
echo "Fetching from upstream and performing hard reset"
git fetch github master
git reset --hard FETCH_HEAD
eval `ssh-agent -k`

chown -R jenkins:jenkins $JENKINS_HOME

restartJenkins

printf "\n\n"