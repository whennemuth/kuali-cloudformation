# This script will replace placeholders in a javascript file with environment variable values.
# The javascript file has a single command that, when executed by a browser, will allow it to be "aware" of the environment. 
jsfile=${JS:-'/usr/share/nginx/html/env.js'}
if [ -n "$landscape" ] ; then
  landscape="${landscape,,}"
  if [ "${landscape:0:4}" != 'prod' ] ; then
    sed -i "s/LANDSCAPE/$landscape/g" $jsfile
    sed -i "s|https://|&$landscape.|g" $jsfile
    sed -i "s/kuali/kualitest/g" $jsfile
  fi
fi

if [ -z "$heading" ] ; then
  heading='Kuali Research has moved'
fi
sed -i "s/HEADING/$heading/g" $jsfile 

if [ -z "$message" ] ; then
  message='New Location'
fi
sed -i "s/MESSAGE/$message/g" $jsfile

nginx -g "daemon off;"
