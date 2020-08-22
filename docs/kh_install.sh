#!/bin/bash

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

echo "Welcome to my amazing script that does awesomeness and creates Knowledge Hub"
echo "Base pkg install ..."
yum install -y epel-release
yum install -y python-devel postgresql-server postgresql-contrib python-pip python-virtualenv postgresql-devel git redis postgis wget lsof policycoreutils-python java-1.8.0-openjdk
yum install -y nginx httpd
yum groupinstall -y 'Development Tools'

echo "Init postgresql"
postgresql-setup initdb
systemctl enable postgresql
systemctl start postgresql

systemctl enable redis
systemctl start redis

echo "Init ckan env"
useradd -m -s /sbin/nologin -d /usr/lib/ckan -c "CKAN User" ckan
chmod 755 /usr/lib/ckan
mkdir -p /etc/ckan/default
chown -R ckan /etc/ckan

mkdir /usr/lib/ckan/data
chown apache:apache /usr/lib/ckan/data
chmod 755 /usr/lib/ckan/data

semanage fcontext -a -t httpd_sys_rw_content_t "/usr/lib/ckan/data(/.*)?"
restorecon -R /usr/lib/ckan/data

#####
sudo -u ckan bash << EOF
cd /usr/lib/ckan/
virtualenv --no-site-packages default

. /usr/lib/ckan/default/bin/activate

echo "Work on python env"
pip install setuptools==36.1

pip install -e 'git+https://github.com/ckan/ckan.git@ckan-2.8.2#egg=ckan'

pip install -r /usr/lib/ckan/default/src/ckan/requirements.txt

deactivate
EOF

echo "fix postgres config"
mv /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf.bak
sed -e 's/ ident/ md5/' \
    -e 's/#local/local/' \
    -e 's/#host/host/'  /var/lib/pgsql/data/pg_hba.conf.bak > /var/lib/pgsql/data/pg_hba.conf

chmod 600 /var/lib/pgsql/data/pg_hba.conf
chown postgres:postgres /var/lib/pgsql/data/pg_hba.conf

systemctl restart postgresql

#####
sudo -u ckan bash << EOF
echo "This is for ckan_default"
createuser -S -D -R -P ckan_default
createdb -O ckan_default ckan_default -E utf-8
psql -d ckan_default -c "create extension postgis;"
psql -d ckan_default -c "select PostGIS_version();"
echo "This is for datastore_default"
createuser -S -D -R -P -l datastore_default
createdb -O ckan_default datastore_default -E utf-8
EOF

echo "Solr"
mkdir -p /opt/apps/solr
useradd -m -d /opt/apps/solr -s /bin/bash solr
chown -R solr /opt/apps/solr

#####
sudo -u ckan bash << EOF
cd /opt/apps/solr
wget https://archive.apache.org/dist/lucene/solr/6.5.1/solr-6.5.1.tgz
tar xzvf solr-6.5.1.tgz
mv solr-6.5.1 6.5.1  # Rename to the version so we get nice path `/opt/apps/solr/6.5.1`
rm solr-6.5.1.tgz  # Remove the downloaded archive
EOF

sudo echo "
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
sudo -u ckan bash << EOF
/opt/apps/solr/6.5.1/bin/solr create_core -c ckan
cd /opt/apps/solr/6.5.1/server/solr/ckan/conf/
wget https://raw.githubusercontent.com/keitaroinc/ckanext-knowledgehub/master/ckanext/knowledgehub/schema.xml
mv solrconfig.xml solrconfig.xml.bak
wget https://raw.githubusercontent.com/keitaroinc/ckanext-knowledgehub/master/docs/solrconfig.xml
EOF

systemctl restart solr
mkdir -p /etc/ckan/default
chown -R ckan /etc/ckan/

#####
sudo -u ckan bash << EOF
. /usr/lib/ckan/default/bin/activate

paster make-config ckan /etc/ckan/default/production.ini
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak

sed -e 's/sqlalchemy.url = postgresql:\/\/ckan_default:pass@localhost\/ckan_default/sqlalchemy.url = postgresql:\/\/ckan_default:password@localhost\/ckan_default?sslmode=disable/' \
    -e 's/ckan.site_url =/ckan.site_url = http:\/\/knowledgehub.unhcr.org/' \
    -e 's/ckan.site_id = default/ckan.site_id = unhcr_knowledgehub/' \
    -e 's/#ckan.datastore.write_url/ckan.datastore.write_url/' \
    -e 's/#ckan.datastore.read_url/ckan.datastore.read_url/' \
    -e 's/#solr_url = http:\/\/127.0.0.1:8983\/solr/solr_url = http:\/\/127.0.0.1:8983\/solr\/ckan/' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini 

ln -s /usr/lib/ckan/default/src/ckan/who.ini /etc/ckan/default/who.ini

deactivate
EOF

#####
sudo -u ckan bash << EOF
. /usr/lib/ckan/default/bin/activate

cd /usr/lib/ckan/default/src/ckan
paster db init -c /etc/ckan/default/production.ini
paster --plugin=ckan datastore set-permissions -c /etc/ckan/default/production.ini | psql -h localhost -U ckan_default -d ckan_default

deactivate
EOF

#####
echo "Installing ckan Validation extensions"
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate

pip install --no-cache-dir -e "git+https://github.com/frictionlessdata/ckanext-validation.git#egg=ckanext-validation"
cd /usr/lib/ckan/default/
pip install -r src/ckanext-validation/requirements.txt
cd src/ckanext-validation/
paster validation init-db -c /etc/ckan/default/production.ini

deactivate
EOF

#####
echo "modifying ckan config"
sudo -u ckan bash << EOF
. /usr/lib/ckan/default/bin/activate

mv /etc/ckan/default/production.ini.bak /etc/ckan/default/production.ini.orig
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = stats text_view image_view recline_view/ {print; print "ckan.plugins = recline_view validation stats"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

deactivate
EOF

#####
echo "Installing ckan Data Request extensions"
su -s /bin/bash - ckan << EOF
. /usr/lib/ckan/default/bin/activate

pip install --no-cache-dir -e "git+https://github.com/keitaroinc/ckanext-datarequests.git@kh_stable#egg=ckanext-datarequests"
mv /etc/ckan/default/production.ini /etc/ckan/default/production.ini.bak
awk '/ckan.plugins = recline_view validation stats/ {print; print "ckan.plugins = recline_view validation stats datarequests"; next}1' /etc/ckan/default/production.ini.bak > /etc/ckan/default/production.ini

pip install humanize==1.0.0

deactivate
EOF
