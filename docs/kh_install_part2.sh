#!/bin/bash

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

echo "Welcome to my amazing script that does awesomeness and creates Knowledge Hub"

#####
echo "Installing ckan Validation extensions"
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
pip install --no-cache-dir -e "git+https://github.com/frictionlessdata/ckanext-validation.git#egg=ckanext-validation"
cd /usr/lib/ckan/default/
pip install -r src/ckanext-validation/requirements.txt
cd src/ckanext-validation/
paster validation init-db -c /etc/ckan/default/production.ini

mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = recline_view validation stats"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

deactivate
EOF

