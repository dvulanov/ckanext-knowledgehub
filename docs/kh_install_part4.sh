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

pip install --no-cache-dir -e "git+https://github.com/keitaroinc/ckanext-oauth2.git@kh_stable#egg=ckanext-oauth2"

AUTHCONF="\
# OAuth2 settings
ckan.oauth2.register_url = https://YOUR_OAUTH_SERVICE/users/sign_up
ckan.oauth2.reset_url = https://YOUR_OAUTH_SERVICE/users/password/new
ckan.oauth2.edit_url = https://YOUR_OAUTH_SERVICE/settings
ckan.oauth2.authorization_endpoint = https://YOUR_OAUTH_SERVICE/authorize
ckan.oauth2.token_endpoint = https://YOUR_OAUTH_SERVICE/token
ckan.oauth2.profile_api_url = https://YOUR_OAUTH_SERVICE/user
ckan.oauth2.client_id = YOUR_CLIENT_ID
ckan.oauth2.client_secret = YOUR_CLIENT_SECRET
ckan.oauth2.scope = profile other.scope
ckan.oauth2.rememberer_name = auth_tkt
ckan.oauth2.profile_api_user_field = username
ckan.oauth2.profile_api_fullname_field = full_name
ckan.oauth2.profile_api_mail_field = email
ckan.oauth2.authorization_header = Authorization
"

mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk -v patch="$AUTHCONF" '/## Logging configuration/ {print patch; print; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = recline_view validation stats datarequests oauth2"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

deactivate
EOF
