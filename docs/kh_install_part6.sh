#!/bin/bash

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

echo "Welcome to my amazing script that does awesomeness and creates Knowledge Hub"

#####
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
pip install ckanext-envvars
pip install --no-cache-dir -e "git+https://github.com/keitaroinc/ckanext-knowledgehub.git#egg=ckanext-knowledgehub"
# Due to some of the packages requiring newer version of setuptools, we need to uninstall, then reinstall setuptools
pip uninstall setuptools -y
pip install setuptools
pip install --no-cache-dir -r "/usr/lib/ckan/default/src/ckanext-knowledgehub/requirements.txt" 
pip uninstall psycopg2-binary -y
pip uninstall psycopg2 -y
pip install --no-cache-dir psycopg2==2.7.3.2
python -m spacy download en_core_web_sm
knowledgehub -c /etc/ckan/default/production.ini db init
deactivate
EOF

#####
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate

HDXCONF="\
# HDX API keys
ckanext.knowledgehub.hdx.api_key = <HDX_API_KEY>
ckanext.knowledgehub.hdx.site = test
ckanext.knowledgehub.hdx.owner_org = <HDX_OWNER_ORG_ID>
ckanext.knowledgehub.hdx.dataset_source = knowledgehub
ckanext.knowledgehub.hdx.maintainer = <HDX_USER_NAME>

"
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk -v patch="$HDXCONF" '/## Logging configuration/ {print patch; print; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = envvars recline_view validation knowledgehub stats datastore datapusher datarequests oauth2"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
sed -e 's/#smtp.starttls = False/#smtp.starttls = True/' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini 
deactivate
EOF

echo "Config wsgi"
echo "
import os
activate_this = os.path.join('/usr/lib/ckan/default/bin/activate_this.py')
execfile(activate_this, dict(__file__=activate_this))
from paste.deploy import loadapp
config_filepath = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'production.ini')
from paste.script.util.logging_config import fileConfig
fileConfig(config_filepath)
application = loadapp('config:%s' % config_filepath)
" > /etc/ckan/default/apache.wsgi

chown ckan /etc/ckan/default/apache.wsgi
mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf_backup

echo "Config httpd"
echo "
<VirtualHost 127.0.0.1:8080>
    ServerName knowledgehub.prodtest.unhcr.org
    ServerAlias www.knowledgehub.prodtest.unhcr.org
    WSGIScriptAlias / /etc/ckan/default/apache.wsgi
    # Pass authorization info on (needed for rest api).
    WSGIPassAuthorization On
    # Deploy as a daemon (avoids conflicts between CKAN instances).
    WSGIDaemonProcess ckan_default display-name=ckan_default processes=2 threads=15
    WSGIProcessGroup ckan_default
    ErrorLog /var/log/httpd/ckan_default.error.log
    CustomLog /var/log/httpd/ckan_default.custom.log combined
    <IfModule mod_rpaf.c>
        RPAFenable On
        RPAFsethostname On
        RPAFproxy_ips 127.0.0.1
    </IfModule>
    <Directory />
        Require all granted
    </Directory>
    
    # Add this to avoid Apache show error: 
    # "AH01630: client denied by server configuration: /etc/ckan/default/apache.wsgi" 
    <Directory /etc/ckan/default>
      Options All
      AllowOverride All
      Require all granted
    </Directory>
</VirtualHost>
" > /etc/httpd/conf.d/knowledgehub.prodtest.unhcr.org.conf


firewall-cmd --permanent --add-service=http

mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.orig
sed -e 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf.orig > /etc/httpd/conf/httpd.conf

echo "Config nginx"
mkdir /etc/nginx/sites-available
mkdir /etc/nginx/sites-enabled

mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig

echo "
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;
events {
    worker_connections 1024;
}
http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] \"\$request\" '
                      '\$status \$body_bytes_sent \"\$http_referer\" '
                      '\"\$http_user_agent\" \"\$http_x_forwarded_for\"';
    access_log  /var/log/nginx/access.log  main;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;
    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;
    # Load enabled sites.
    include /etc/nginx/sites-enabled/*;
    server_names_hash_bucket_size 64;
}
" > /etc/nginx/nginx.conf

echo "
proxy_cache_path /tmp/nginx_cache levels=1:2 keys_zone=cache:30m max_size=250m;
proxy_temp_path /tmp/nginx_proxy 1 2;
server {
    client_max_body_size 100M;
    location / {
        proxy_pass http://127.0.0.1:8080/;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Host \$host;
        proxy_cache cache;
        proxy_cache_bypass \$cookie_auth_tkt;
        proxy_no_cache \$cookie_auth_tkt;
        proxy_cache_valid 30m;
        proxy_cache_key \$host\$scheme\$proxy_host\$request_uri;
        # In emergency comment out line to force caching
        # proxy_ignore_headers X-Accel-Expires Expires Cache-Control;
    }
}
" > /etc/nginx/sites-available/ckan.conf

ln -s /etc/nginx/sites-available/ckan.conf /etc/nginx/sites-enabled/ckan.conf

setsebool httpd_can_network_connect on -P

systemctl restart httpd
systemctl start nginx
systemctl enable nginx

echo "Install Datapusher"

yum install -y libxslt-devel libxml2-devel libffi-devel

#####
su -s /bin/bash - ckan << EOF
virtualenv /usr/lib/ckan/datapusher
mkdir /usr/lib/ckan/datapusher/src
cd /usr/lib/ckan/datapusher/src
git clone -b 0.0.16 https://github.com/ckan/datapusher.git
. /usr/lib/ckan/datapusher/bin/activate
cd datapusher
pip install -r requirements.txt
python setup.py develop
deactivate
EOF

echo "
<VirtualHost 0.0.0.0:8800>
    ServerName ckan
    # this is our app
    WSGIScriptAlias / /etc/ckan/datapusher.wsgi
    # pass authorization info on (needed for rest api)
    WSGIPassAuthorization On
    # Deploy as a daemon (avoids conflicts between CKAN instances)
    WSGIDaemonProcess datapusher display-name=demo processes=1 threads=15
    WSGIProcessGroup datapusher
    ErrorLog /var/log/httpd/datapusher.error.log
    CustomLog /var/log/httpd/datapusher.custom.log combined
    <Directory /etc/ckan>
    Options All
    AllowOverride All
    Require all granted
    </Directory>
</VirtualHost>
" > /etc/httpd/conf.d/datapusher.conf

cp /usr/lib/ckan/datapusher/src/datapusher/deployment/datapusher.wsgi /etc/ckan/
cp /usr/lib/ckan/datapusher/src/datapusher/deployment/datapusher_settings.py /etc/ckan/

mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.bak
awk '/Listen 8080/ {print; print "Listen 8800"; next}1' /etc/httpd/conf/httpd.conf.bak > /etc/httpd/conf/httpd.conf

semanage port -a -t http_port_t -p tcp 8800

#####
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
sed -e 's/#ckan.datapusher.url/ckan.datapusher.url/' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini 
deactivate
EOF

systemctl restart httpd
curl http://localhost:8800

#####
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate

cd /usr/lib/ckan/default/src/ckan
# Add the user
paster --plugin=ckan user add ckan_admin email=ckan_admin@knowledgehb.org -c /etc/ckan/default/production.ini
# Set the user `ckan_admin` as sysadmin
paster --plugin=ckan sysadmin add ckan_admin -c /etc/ckan/default/production.ini
deactivate
EOF
