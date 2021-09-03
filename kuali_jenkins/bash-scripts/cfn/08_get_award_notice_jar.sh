installJar() {
  local group='bu.edu'
  local groupPath=$(echo $group | sed 's|\.|/|g')
  local artifact='bu-awardnotice'
  local version='1.1'
  local packaging='jar'
  if [ ! -f /var/lib/jenkins/.m2/repository/$groupPath/$artifact/$version/$artifact-$version.$packaging ] ; then
    local jar=/var/lib/jenkins/$artifact-$version.$packaging
    if [ ! -f $jar ] && [ -f $jar.zip ] ; then
      unzip $jar.zip
    fi
    if [ ! -f $jar ] ; then
      echo "WARNING: could not install $artifact-$version.$packaging"
      return 0
    fi
    mvn install:install-file \
      -Dfile=$jar \
      -DgroupId=$group \
      -DartifactId=$artifact \
      -Dversion=$version \
      -Dpackaging=$packaging \
      -DlocalRepositoryPath=/var/lib/jenkins/.m2
  fi             
}

installJar

chown -R jenkins:jenkins chown $repo/$groupPath/$artifact/$version/
