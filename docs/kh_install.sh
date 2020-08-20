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
useradd -m -s /bin/bash ckan

sudo -i -u ckan bash << EOF
mkdir -p ~/ckan/lib
mkdir -p ~/ckan/etc
EOF

ln -s /home/ckan/ckan/lib /usr/lib/ckan
ln -s /home/ckan/ckan/etc /etc/ckan
