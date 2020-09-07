#!/bin/bash

# exit when any command fails
set -e
# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

echo "Welcome to my amazing script that does awesomeness and creates Knowledge Hub"

echo "Config Workers"
mkdir /var/log/ckan
chown -R ckan /var/log/ckan

#####
su -s /bin/bash - ckan << EOF
echo "0 0 * * * /usr/lib/ckan/default/bin/knowledgehub -c /etc/ckan/default/production.ini predictive_search train >/var/log/ckan/cronjob_predictive_search.log 2>&1" | crontab -
crontab -l > mytempcron
#echo new cron into cron file
echo "0 0 * * * /usr/lib/ckan/default/bin/knowledgehub -c /etc/ckan/default/production.ini intents update >/var/log/ckan/cronjob_intents_update.log 2>&1" >> mycron
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
