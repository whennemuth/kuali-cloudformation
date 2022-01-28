
checkTestHarness $@ 2> /dev/null || true

parseArgs

outputHeading "M2 DEPENDENCY CHECK (schemaspy, rice, coeus-api, s2sgen)"

isDebug && set -x

echo " "
echo "1) Analyzing pom for versions..."

# Get the content of the pom file with all return/newline characters removed.
content=$(cat ${POM} | sed ':a;N;$!ba;s/\n//g')

# Get versions of dependencies, use a zero width lookbehind for the open element and capture 
# all following characters thereafter until a closing element character is encountered

schemaspy_version=$(echo "$content" | grep -Po '(?<=<schemaspy\.version>)([^<]+)' || true)
schemaspy_version_tag=$(echo "$content" | grep -Po '(?<=<schemaspy\.version\.tag>)([^<]+)' || true)
[ -z "$schemaspy_version_tag" ] && schemaspy_version_tag="schemaspy-$schemaspy_version"
echo "schemaspy version: ${schemaspy_version}"
echo "schemaspy tag: ${schemaspy_version_tag}"
 
rice_version=$(echo "$content" | grep -Po '(?<=<rice\.version>)([^<]+)' || true)
rice_version_tag=$(echo "$content" | grep -Po '(?<=<rice\.version\.tag>)([^<]+)' || true)
[ -z "$rice_version_tag" ] && rice_version_tag="rice-$rice_version"
echo "rice version: ${rice_version}"
echo "rice tag: ${rice_version_tag}"
 
api_version=$(echo "$content" | grep -Po '(?<=<coeus\-api\-all\.version>)([^<]+)' || true)
api_version_tag=$(echo "$content" | grep -Po '(?<=<coeus\-api\-all\.version\.tag>)([^<]+)' || true)
[ -z "$api_version_tag" ] && api_version_tag="coeus-api-$api_version"
echo "coeus-api version: ${api_version}"
echo "coeus-api tag: ${api_version_tag}"
 
s2sgen_version=$(echo "$content" | grep -Po '(?<=<coeus\-s2sgen\.version>)([^<]+)' || true)
s2sgen_version_tag=$(echo "$content" | grep -Po '(?<=<coeus\-s2sgen\.version\.tag>)([^<]+)' || true)
[ -z "$s2sgen_version_tag" ] && s2sgen_version_tag="coeus-s2sgen-$s2sgen_version"
echo "s2sgen version: ${s2sgen_version}"
echo "s2sgen tag: ${s2sgen_version_tag}"

research_resources_version=$(echo "$content" | grep -Po '(?<=<research\-resources\.version>)([^<]+)' || true)
research_resources_version_tag=$(echo "$content" | grep -Po '(?<=<research\-resources\.version\.tag>)([^<]+)' || true)
[ -z "$research_resources_version_tag" ] && research_resources_version_tag="research-resources-$research_resources_version"
echo "research-resources version: ${research_resources_version}"
echo "research-resources tag: ${research_resources_version_tag}"

echo " "
echo "2) Searching .m2 directory for dependencies installed for above versions..."

# repo="${JENKINS_HOME}/.m2/repository"
# If the local repo location has been customized in settings.xml, then we need to parse it from maven help plugin output.
repo=$(echo $(mvn help:effective-settings | grep 'localRepository') | cut -d '>' -f 2 | cut -d '<' -f 1)
windows() {
  [ -n "$(ls /c/ 2> /dev/null)" ] && true || false
}
if [ -z "$repo" ] ; then
  echo "ERROR! Cannot determine location of .m2 directory."
  exit 1
fi
if windows ; then
  # assume gitbash and reformat path accordingly
  echo ".m2 repository: ${repo}"
  repo="$(echo '/'$repo | sed 's|:||' | sed 's|\\|/|g')"
fi
echo ".m2 repository: ${repo}"

# file extension, group, version, artifactid, parent_artifactid, job
m2_items=(
   "jar,co/kuali/schemaspy,${schemaspy_version},${schemaspy_version_tag},schemaspy,schemaspy,schemaspy"
   # "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-archetype-quickstart,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-core-api,rice,kc-rice"
   # "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-db-config,rice,kc-rice"
   # "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-deploy,rice,kc-rice"
   # "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-development-tools,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-impex-client-bootstrap,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-impex-master,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-impex-server-bootstrap,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-impl,rice,kc-rice"
   # "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-it-config,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-ken-api,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-kew-api,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-kim-api,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-kns,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-krad-app-framework,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-krms-api,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-ksb-api,rice,kc-rice"
   # "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-legacy-web,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-location-api,rice,kc-rice"
   # "war,org/kuali/rice,${rice_version},${rice_version_tag},rice-serviceregistry,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-sql,rice,kc-rice"
   "war,org/kuali/rice,${rice_version},${rice_version_tag},rice-standalone,rice,kc-rice"
   # "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-tools-test,rice,kc-rice"
   "war,org/kuali/rice,${rice_version},${rice_version_tag},rice-web,rice,kc-rice"
   "jar,org/kuali/rice,${rice_version},${rice_version_tag},rice-xml,rice,kc-rice"
   "jar,org/kuali/coeus,${api_version},${api_version_tag},coeus-api-all,coeus-api,kc-api"
   "jar,org/kuali/coeus,${s2sgen_version},${s2sgen_version_tag},coeus-s2sgen-api,coeus-s2sgen,kc-s2sgen"
   "jar,org/kuali/coeus,${s2sgen_version},${s2sgen_version_tag},coeus-s2sgen-impl,coeus-s2sgen,kc-s2sgen"
   # "jar,org.kuali.research,${research_resources_version},${research_resources_version_tag},research-resources,research-resources,kc-research-resources"
)


jobs_to_run=()
versions=()
version_tags=()
artifact_dirs=()
tagRecord='based.on.git.tag'

# Look for a file at the .m2 version subdirectory of the artifact that has a 
# record of the github tag the last install of that artifact and version was based on.
# If found, return the content of the file, else search for it in s3 and return that content.
getLastTag() {
  local artifactDir="$1"
  local s3Record="$S3_BUCKET/jenkins-github-records/$2"
  local m2Record="${artifactDir}/${tagRecord}"
  local temp="${m2Record}.temp"
  local lastTag="$(cat $m2Record 2> /dev/null)"
  [ -z "$lastTag" ] && lastTag="$(cat $temp 2> /dev/null || true)"
  if [ -z "$lastTag" ] ; then
    lastTag="$(aws s3 cp s3://${s3Record} - 2> /dev/null || true)"
    if [ -n "$lastTag" ] ; then
      if [ ! -d "$(dirname $temp)" ] ; then
        mkdir -p "$(dirname $temp)"
      fi
      echo "$lastTag" > "$temp"
    fi
  fi
  echo "$lastTag"
}

# An artifact was just built and installed. Record the github tag associated with the build and
# save it to the corresponding .m2 subdirectory. NOTE: This is not necessary in most cases, only
# there may be times when the version tag of the artifact does not match the tag applied to where
# the source for it is stored in git (a break in convention).
setLastTag() {
   local artifactDir="$1"
   local s3Record="$S3_BUCKET/jenkins-github-records/$2"
   local m2Record="${artifactDir}/${tagRecord}"
   local tagValue="$3"
   local temp="${m2Record}.temp"
   [ -f "$temp" ] && rm -f $temp
   echo "$tagValue" > "$m2Record"
   aws s3 cp $m2Record s3://$s3Record
}

registerArtifactToBuild() {
   local job="$1"
   if [ -z "$(echo ${jobs_to_run[*]} | grep ${job})" ] ; then
      jobs_to_run+=(${job});
      versions+=("$2");
      version_tags+=("$3");
      artifact_dirs+=("$4");
   fi
}
   
artifactFoundInM2() { [ -f "$artifact" ] && true || false ; }
   
usingCustomTag() { [ "$version_tag" != "$default_version_tag" ] && true || false ; }
   
usingDefaultTag() { [ "$version_tag" == "$default_version_tag" ] && true || false ; }
   
artifactBuiltFromUnkownSource() { [ "$version_tag" != "$last_version_tag" ] && true || false ; }
   
artifactBuiltFromOtherTag() { ( artifactBuiltFromUnkownSource && [ -n "$last_version_tag" ] ) && true || false ; }

for i in ${m2_items[@]}; do

   IFS=',' read -ra parts <<< "${i}"

   ext=${parts[0]}
   group=${parts[1]}
   version=${parts[2]}
   version_tag=${parts[3]}
   artifactid=${parts[4]}
   parentartifactid=${parts[5]}
   job=${parts[6]}
   
   if [ -z "$version" ] ; then
      echo "WARNING: Could not determine the version of $artifactid"
      versionFailures='true'
      continue
   fi

   artifactDir="${repo}/${group}/${artifactid}/${version}"
   artifact="${artifactDir}/${artifactid}-${version}.${ext}"
   parentArtifactDir="${repo}/${group}/${parentartifactid}/${version}"
   default_version_tag="${parentartifactid}-${version}"
   last_version_tag="$(getLastTag $parentArtifactDir $default_version_tag)"
   
   if artifactFoundInM2 ; then
      echo "Found: ${artifact}"
      msg=""
      if usingCustomTag && artifactBuiltFromOtherTag ; then
         msg="But it was built from github tag: $last_version_tag, (needed: custom tag $version_tag). Install required."
      elif usingCustomTag && artifactBuiltFromUnkownSource ; then
         msg="But cannot determine if it was built from tag $version_tag as needed. Install required."
      elif usingDefaultTag && artifactBuiltFromOtherTag ; then
      	 msg="But it was built from github tag: $last_version_tag, (needed: default tag $version_tag). Install required"
      else
         if usingCustomTag ; then
         	tagType='custom'
         else
            tagType='default'
         fi
         echo "Was last built from current $tagType tag: $version_tag, so no install required"
      fi
      if [ -n "$msg" ] ; then
         echo "$msg"
         registerArtifactToBuild "$job" "$default_version_tag" "$version_tag" "$parentArtifactDir"
      fi
   else
      echo "MISSING: ${artifact}";
      registerArtifactToBuild "$job" "$default_version_tag" "$version_tag" "$parentArtifactDir"
   fi
done

echo " "

if [ ${#jobs_to_run[@]} -eq 0 ] ; then
   if [ "$versionFailures" == 'true' ] ; then
      echo "Some artifacts could not be checked due to failure to determine version"
      exit 1
   else
      echo "All artifacts accounted for"
   fi
else
  if [ "$DRYRUN" != true ] ; then
    source /var/lib/jenkins/cli-credentials.sh
  fi
   echo "DEPENDENCIES MISSING. Must build the following: ${jobs_to_run[*]}";
   if [ "$versionFailures" == 'true' ] ; then
      echo "Some artifacts could not be checked due to failure to determine version"
      exit 1
   fi
   echo " "
   for ((i=0; i<${#jobs_to_run[*]}; i++));
   do
      # java -jar ${JENKINS_HOME}/jenkins-cli.jar -s http://localhost:8080/ build 'jenkins-cli test2' -v -f -p PARM1=hello --username=warren --password=password

      cmd="java -jar ${JENKINS_HOME}/jenkins-cli.jar -s http://localhost:8080/ build ${jobs_to_run[i]} -v -f -p version=${version_tags[i]}"
      echo "$cmd"
      [ "$DRYRUN" != true ] && eval "$cmd"
      
      cmd="setLastTag ${artifact_dirs[i]} ${versions[i]} ${version_tags[i]}"
      echo "$cmd"
      [ "$DRYRUN" != true ] && eval "$cmd"
      
   done
fi

echo " "
echo "----------------------------------------------------------------------------"
echo "                      FINISHED M2 DEPENDENCY CHECK"
echo "----------------------------------------------------------------------------"
echo " "

set -x

