#!/bin/bash

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

echo "
############################################
Part 1: Base Install
############################################
"
yum -y update
yum install -y epel-release
yum install -y python-devel postgresql-server python-pip python-virtualenv git redis wget lsof policycoreutils-python java-1.8.0-openjdk
yum install -y nginx httpd mod_wsgi
yum groupinstall -y 'Development Tools'

systemctl enable redis
systemctl start redis

systemctl enable httpd
systemctl start httpd

echo "Init ckan env"
useradd -m -s /sbin/nologin -d /usr/lib/ckan -c "CKAN User" ckan
chmod 755 /usr/lib/ckan
mkdir -p /etc/ckan/default
chown -R ckan /etc/ckan

mkdir /var/lib/ckan/data
chown apache:apache /var/lib/ckan/data
chmod 755 /var/lib/ckan/data

semanage fcontext -a -t httpd_sys_rw_content_t "/var/lib/ckan/data(/.*)?"
restorecon -R /var/lib/ckan/data

#####
su -s /bin/bash - ckan << EOF
cd /usr/lib/ckan/
virtualenv --no-site-packages default
. /usr/lib/ckan/default/bin/activate
echo "Work on python env"
pip install setuptools==36.1
pip install -e 'git+https://github.com/ckan/ckan.git@ckan-2.8.2#egg=ckan'
pip install -r /usr/lib/ckan/default/src/ckan/requirements.txt
deactivate
EOF

echo "Solr"
mkdir -p /opt/apps/solr
useradd -m -d /opt/apps/solr -s /bin/bash solr
chown -R solr /opt/apps/solr

#####
su -s /bin/bash - solr << EOF
cd /opt/apps/solr
wget https://archive.apache.org/dist/lucene/solr/6.5.1/solr-6.5.1.tgz
tar xzvf solr-6.5.1.tgz
mv solr-6.5.1 6.5.1  # Rename to the version so we get nice path `/opt/apps/solr/6.5.1`
rm solr-6.5.1.tgz  # Remove the downloaded archive
EOF

echo "
[Unit]
Description=Apache Solr
After=network.target
[Service]
Type=forking
ExecStart=/opt/apps/solr/6.5.1/bin/solr start
ExecReload=/opt/apps/solr/6.5.1/bin/solr restart
ExecStop=/opt/apps/solr/6.5.1/bin/solr stop
User=solr
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/solr.service

chmod 664 /etc/systemd/system/solr.service

systemctl enable solr
systemctl start solr

#####
su -s /bin/bash - solr << EOF
/opt/apps/solr/6.5.1/bin/solr create_core -c ckan
cd /opt/apps/solr/6.5.1/server/solr/ckan/conf/
wget https://raw.githubusercontent.com/keitaroinc/ckanext-knowledgehub/master/ckanext/knowledgehub/schema.xml
mv solrconfig.xml solrconfig.xml.bak
wget https://raw.githubusercontent.com/keitaroinc/ckanext-knowledgehub/master/docs/solrconfig.xml
EOF

systemctl restart solr
mkdir -p /etc/ckan/default
chown -R ckan /etc/ckan/
mkdir /var/lib/ckan
chown ckan:ckan /var/lib/ckan

#####
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
paster make-config ckan /etc/ckan/default/production.ini
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.orig
sed -e 's/sqlalchemy.url = postgresql:\/\/ckan_default:pass@localhost\/ckan_default/sqlalchemy.url = postgresql:\/\/ckan_default:password@localhost/' \
    -e 's/ckan.site_url =/ckan.site_url = http:\/\/knowledgehub.unhcr.org/' \
    -e 's/ckan.site_id = default/ckan.site_id = unhcr_knowledgehub/' \
    -e 's/#ckan.datastore.write_url = postgresql:\/\/ckan_default:pass@localhost\/datastore_default/ckan.datastore.write_url = postgresql:\/\/ckan_default:pass@localhost\/datastore_default/' \
    -e 's/#ckan.datastore.read_url = postgresql:\/\/datastore_default:pass@localhost\/datastore_default/ckan.datastore.read_url = postgresql:\/\/datastore_default:pass@localhost\/datastore_default/' \
    -e 's/#ckan.storage_path = \/var\/lib\/ckan/ckan.storage_path = \/var\/lib\/ckan\/data/' \
    -e 's/#solr_url = http:\/\/127.0.0.1:8983\/solr/solr_url = http:\/\/127.0.0.1:8983\/solr\/ckan/' /etc/ckan/default/production.ini.orig > /etc/ckan/default/production.ini 
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
sed -e 's/_default:pass@/_default:password@/' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini 
ln -s /usr/lib/ckan/default/src/ckan/who.ini /etc/ckan/default/who.ini
deactivate
EOF

#####
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
cd /usr/lib/ckan/default/src/ckan
paster db init -c /etc/ckan/default/production.ini
paster --plugin=ckan datastore set-permissions -c /etc/ckan/default/production.ini | psql -h localhost -U ckan_default -d ckan_default
deactivate
EOF

#####
# for some reason this was not created
su -s /bin/bash - ckan << EOF
mkdir -p /var/lib/ckan/storage/uploads
EOF

echo "
############################################
Part 2: Validation Extention
############################################
"
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
# this extension installs goodtables, which installs pyrsistent>=0.14.0 (from jsonschema>=2.5->tableschema<2.0,>=1.0.3->goodtables==1.5.1)
# however pyrsisten > 0.16.0 breaks with python 2, so we need to install 0.16.0 manually to not grab the latest
pip install pyrsistent==0.16.0
pip install --no-cache-dir -e "git+https://github.com/frictionlessdata/ckanext-validation.git#egg=ckanext-validation"
cd /usr/lib/ckan/default/
pip install -r src/ckanext-validation/requirements.txt
cd src/ckanext-validation/
paster validation init-db -c /etc/ckan/default/production.ini
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = recline_view validation stats"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini
deactivate
EOF

echo "
############################################
Part 3: Data Requests Extention
############################################
"
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
pip install --no-cache-dir -e "git+https://github.com/keitaroinc/ckanext-datarequests.git@kh_stable#egg=ckanext-datarequests"
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = recline_view validation stats datarequests"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini
pip install humanize==1.0.0
deactivate
EOF

echo "
############################################
Part 4: OAuth2 Extention
############################################
"
AUTHCONF="\
# OAuth2 settings
ckan.oauth2.authorization_endpoint = https://YOUR_OAUTH_SERVICE/authorize
ckan.oauth2.token_endpoint = https://YOUR_OAUTH_SERVICE/token
ckan.oauth2.profile_api_url = https://graph.microsoft.com/v1.0/me
ckan.oauth2.client_id = YOUR_CLIENT_ID
ckan.oauth2.client_secret = YOUR_CLIENT_SECRET
ckan.oauth2.scope = profile openid email
ckan.oauth2.profile_api_user_field = unique_name
ckan.oauth2.profile_api_fullname_field = name
ckan.oauth2.profile_api_mail_field = unique_name
ckan.oauth2.authorization_header = Authorization
ckan.oauth2.jwt.enable = true
"
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk -v patch="$AUTHCONF" '/## Logging configuration/ {print patch; print; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

chown ckan:ckan /etc/ckan/default/production.ini
chown ckan:ckan /etc/ckan/default/production.ini.bak

###
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
pip install --no-cache-dir -e "git+https://github.com/keitaroinc/ckanext-oauth2.git@kh_stable#egg=ckanext-oauth2"
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = recline_view validation stats datarequests oauth2"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini
deactivate
EOF

echo "
############################################
Part 5: Data Store Extention
############################################
"
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = / {print "ckan.plugins = recline_view validation stats datastore datarequests oauth2"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini
deactivate
EOF

echo "
############################################
Part 6: Knowledge Hub and Httpd / Nginx config
############################################
"
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

chown ckan:ckan /etc/ckan/default/production.ini
chown ckan:ckan /etc/ckan/default/production.ini.bak

#####
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate
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
    ServerName knowledgehub.unhcr.org
    ServerAlias www.knowledgehub.unhcr.org
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
" > /etc/httpd/conf.d/knowledgehub.unhcr.org.conf


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

echo "
############################################
Part 7: Workers Config
############################################
"
echo "Config Workers"
mkdir /var/log/ckan
chown -R ckan /var/log/ckan

#####
su -s /bin/bash - ckan << EOF
echo "0 0 * * * /usr/lib/ckan/default/bin/knowledgehub -c /etc/ckan/default/production.ini predictive_search train >/var/log/ckan/cronjob_predictive_search.log 2>&1" | crontab -
crontab -l > mytempcron
#echo new cron into cron file
echo "0 0 * * * /usr/lib/ckan/default/bin/knowledgehub -c /etc/ckan/default/production.ini intents update >/var/log/ckan/cronjob_intents_update.log 2>&1" >> mytempcron
#install new cron file
crontab mytempcron
rm mytempcron
EOF

echo "Default Worker"
echo "
[Unit]
Description=CKAN Worker Default
After=network.target
[Service]
WorkingDirectory=/usr/lib/ckan/default/src/ckan
ExecStart=/usr/lib/ckan/default/bin/paster --plugin=ckan jobs worker --config=/etc/ckan/default/production.ini
User=ckan
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/ckan-worker.default.service

chmod 664 /etc/systemd/system/ckan-worker.default.service

systemctl enable ckan-worker.default
systemctl start ckan-worker.default
systemctl status ckan-worker.default

echo "Priority Worker"
echo "
[Unit]
Description=CKAN Worker Priority
After=network.target
[Service]
WorkingDirectory=/usr/lib/ckan/default/src/ckan
ExecStart=/usr/lib/ckan/default/bin/paster --plugin=ckan jobs worker priority --config=/etc/ckan/default/production.ini
User=ckan
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/ckan-worker.priority.service

chmod 664 /etc/systemd/system/ckan-worker.priority.service

systemctl enable ckan-worker.priority
systemctl start ckan-worker.priority
systemctl status ckan-worker.priority

echo "Bulk Worker"

echo "
[Unit]
Description=CKAN Worker Bulk
After=network.target
[Service]
WorkingDirectory=/usr/lib/ckan/default/src/ckan
ExecStart=/usr/lib/ckan/default/bin/paster --plugin=ckan jobs worker bulk --config=/etc/ckan/default/production.ini
User=ckan
[Install]
WantedBy=multi-user.target
" > /etc/systemd/system/ckan-worker.bulk.service

chmod 664 /etc/systemd/system/ckan-worker.bulk.service

systemctl enable ckan-worker.bulk
systemctl start ckan-worker.bulk
systemctl status ckan-worker.bulk


#############################################
echo "
As ckan user, run these commands and create ckan_admin
. /usr/lib/ckan/default/bin/activate
cd /usr/lib/ckan/default/src/ckan
paster --plugin=ckan user add ckan_admin email=ckan_admin@knowledgehub.unhcr.org -c /etc/ckan/default/production.ini
paster --plugin=ckan sysadmin add ckan_admin -c /etc/ckan/default/production.ini
"
#############################################
