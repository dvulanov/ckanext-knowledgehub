#!/bin/bash

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

echo "Welcome to my amazing script that does awesomeness and creates Knowledge Hub"

#####
echo "Installing ckan Data Request OAuth2 extensions"
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate

mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = recline_view validation stats datastore datarequests oauth2"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

deactivate
EOF
