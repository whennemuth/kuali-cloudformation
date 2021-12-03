repo='/var/lib/jenkins/.m2/repository'
group='bu.edu'
groupPath=$(echo $group | sed 's|\.|/|g')
artifact='bu-awardnotice'
version='1.1'
packaging='jar'
if [ ! -f $repo/$groupPath/$artifact/$version/$artifact-$version.$packaging ] ; then
  jar=/var/lib/jenkins/$artifact-$version.$packaging
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
    -DlocalRepositoryPath=$repo
fi             

chown -R jenkins:jenkins $repo/$groupPath/$artifact/$version/
