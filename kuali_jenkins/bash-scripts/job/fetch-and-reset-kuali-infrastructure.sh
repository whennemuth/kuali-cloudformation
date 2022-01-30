cd ${JENKINS_HOME}
if [ ! -d kuali-infrastructure ] ; then
  mkdir kuali-infrastructure
else
  source kuali-infrastructure/scripts/common-functions.sh 2> /dev/null || true
  outputHeading 'Pulling kuali infrastructure from github...' 2> /dev/null || true
fi
cd kuali-infrastructure

eval `ssh-agent -s`
# Add the key to the agent.
ssh-add ${JENKINS_HOME}/.ssh/bu_github_id_kuali_cloudformation_rsa
# ssh -T git@github.com
if [ ! -d .git ] ; then
	git init	
	git config user.email "jenkins@bu.edu"
	git config user.name $GITUSER
	git remote add github $REPO
fi
if [ -n "$(git status -s -z)" ] ; then
    echo "FOUND LOCAL CHANGES! SORRY, YOUR ARE GOING TO LOSE THESE."
fi
echo "Fetching from upstream and performing hard reset"
git fetch github $BRANCH
git reset --hard FETCH_HEAD
eval `ssh-agent -k`
