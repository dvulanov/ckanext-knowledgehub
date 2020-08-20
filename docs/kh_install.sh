#!/bin/bash

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

sudo -u ckan bash << EOF
cd /usr/lib/ckan/
virtualenv --no-site-packages default
EOF

. /usr/lib/ckan/default/bin/activate

echo "Work on python env"
pip install setuptools==36.1

pip install -e 'git+https://github.com/ckan/ckan.git@ckan-2.8.2#egg=ckan'

pip install -r /usr/lib/ckan/default/src/ckan/requirements.txt

deactivate

echo "fix postgres config"
mv /var/lib/pgsql/data/pg_hba.conf /var/lib/pgsql/data/pg_hba.conf.bak
sed -e 's/ ident/ md5/' \
    -e 's/#local/local/' \
    -e 's/#host/host/'  /var/lib/pgsql/data/pg_hba.conf.bak > /var/lib/pgsql/data/pg_hba.conf

chmod 600 /var/lib/pgsql/data/pg_hba.conf
chown postgres:postgres /var/lib/pgsql/data/pg_hba.conf

sudo -u postgres bash << EOF
echo "This is for ckan_default"
createuser -S -D -R -P ckan_default
createdb -O ckan_default ckan_default -E utf-8
psql -d ckan_default -c "create extension postgis;"
select PostGIS_version();

echo "This is for datastore_default"
createuser -S -D -R -P -l datastore_default
createdb -O ckan_default datastore_default -E utf-8
EOF

echo "Solr"
mkdir -p /opt/apps/solr
useradd -m -d /opt/apps/solr -s /bin/bash solr
chown -R solr /opt/apps/solr

sudo -u solr bash << EOF
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
sudo chmod 664 /etc/systemd/system/solr.service

sudo systemctl enable solr
sudo systemctl start solr

. /usr/lib/ckan/default/bin/activate
