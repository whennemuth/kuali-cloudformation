AwsCliInstalled() {
  aws --version > /dev/null 2>&1 && [ "$?" == "0" ] && true || false
}

prePublishCheck() {
  if ! AwsCliInstalled ; then
    s3=""
    printf "\nThe AWS cli does not seem to be installed!\n"
    echo "------------------------------------------"
    printf "   Directions to install at: https://docs.aws.amazon.com/cli/latest/userguide\n" 
    printf "   Until you install the cli, you cannot push the build artifact (jar file) to s3\n"
    local answer=""
    while true; do
      printf "   Would you like to build the jar? [y/n]: "
      read answer
      if [ ${answer,,} == "y" ] ; then
        break;
      elif [ ${answer,,} == "n" ] ; then
        pkg="" && break;
      else
        echo "   \"$answer\" is not a valid entry"
      fi
    done
  fi
}

build() {
  local success=""
  eval $pkg
  [ "$?" == "0" ] && success="true"
  [ $success ] && true || false
}

pkg="mvn package shade:shade"
s3="s3://kuali-conf/cloudformation/lambda/lambda-utils.jar"

prePublishCheck

if build ; then
  [ $s3 ] && aws --profile=ecr.access s3 cp target/lambda-utils.jar $s3
fi
