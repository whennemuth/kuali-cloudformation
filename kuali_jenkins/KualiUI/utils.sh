
gitSSH() {
  local sshKeyPath="$1"
  local sshdir=$(dirname $sshKeyPath)
  local cmd="$2"

  # echo "refs/tags/ $sshKeyPath"
  # echo "refs/tags/ $cmd"
  # return 0;

  eval `ssh-agent -s` > /dev/null 2>&1; # Suppress output
  ssh-add <(cat $sshKeyPath) > /dev/null 2>&1; # Suppress output

  checkGithubHost $sshdir  
  checkGithubHost '/root/.ssh'

  if [ -n "$cmd" ] ; then
    # IMPORTANT: All stdout and stderr output up to this point must be suppressed.
    eval "$cmd"
    ssh-agent -k 2> /dev/null;
  fi
}

# Make sure github is present in the known_hosts file (avoids prompt from ssh-add).
checkGithubHost() {
  local sshdir="$1"
  if [ -d $sshdir ] ; then
    if [ -f $sshdir/known_hosts ] ; then
      if [ -z "`cat $sshdir/known_hosts 2> /dev/null | grep 'github.com'`" ] ; then
        ssh-keyscan -t rsa github.com >> $sshdir/known_hosts > /dev/null 2>&1
      fi
    fi
  fi
}

gitSSH "$@"

exit 0