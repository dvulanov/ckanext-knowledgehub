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


