#!/bin/bash

# Author: thesubtley

# this should get you up and running quickly
# replace PEM file, server IPs as required
# reinstalls might be a bit janky (errors with duplicate kibana indexes, might need to pipe yes into install-elkserver)
# TODO custom redirector/scenario names depending on TS/Redir
# TODO TeamServer in install-teamserver should match getremotelogs TeamServer name (link to logs in Kibana 404 otherwise)
# TODO haven't tested redirectors w/ HAProxy yet

PEM="labs.pem"
RED_ELK_SERVER="ip-10-10-10-10.us-east-2.compute.internal"
RED_ELK_SERVER_IP="10.10.10.10"
declare -a teamserver_list=("10.0.10.200") #space separated list e.g. ("1.2.3.4" "4.3.2.1")
declare -a redir_list=("10.0.10.100")

#Fix up locals
# update timezones
find ./ -type f -exec sed -i 's/Europe\/Amsterdam/UTC/g' {} \;

#update cert info
sed -i 's/C\ =\ MODIFYME.*$/C\ =\ US' certs/config.cnf
sed -i 's/MODIFYME.*$/TrustMe/g' certs/config.cnf
sed -i "s/dnsnameofyourredelkserver/$RED_ELK_SERVER/" certs/config.cnf
sed -i "s/someseconddnsname/$RED_ELK_SERVER/" certs/config.cnf
sed -i "s/123\.123\.123\.123/$RED_ELK_SERVER_IP/" certs/config.cnf

# Cobalt strike in a non standard location, fix scripts
find ./ -type f -exec sed -i -e 's/\/root\/cobaltstrike/\/opt\/cobaltstrike/g' {} \;

# Initial Setup
sudo ./initial-setup.sh


# Configure redirectors
# Redirectors equire haproxy installed and running
# replace redirector, scenario with whatever you want displayed in Kibana #TODO
for REDIR_IP in "${redir_list[@]}"; do
	scp -i $PEM redirs.tgz ec2-user@$REDIR_IP:~
	ssh -i $PEM ec2-user@$REDIR_IP <<EOF
tar xvf redirs.tgz
cd redirs
sudo ./install-redir.sh Redirector Scenario $RED_ELK_SERVER_IP:5044
EOF
done


# Configure Team Servers
for TEAMSERVER_IP in "${teamserver_list[@]}"; do
	scp -i $PEM teamservers.tgz ec2-user@$TEAMSERVER_IP:~
	ssh -i $PEM ec2-user@$TEAMSERVER_IP <<EOF
tar xvf teamservers.tgz
cd teamservers
sudo ./install-teamserver.sh TeamServer Scenario $RED_ELK_SERVER_IP:5044
EOF
done


# Configure Elk Server
scp -i $PEM elkserver.tgz ec2-user@$RED_ELK_SERVER_IP:~
ssh -i $PEM ec2-user@$RED_ELK_SERVER_IP <<EOF
tar xvf elkserver.tgz
cd elkserver
sudo ./install-elkserver.sh
EOF
for TEAMSERVER_IP in "${teamserver_list[@]}"; do
	ssh -i $PEM ec2-user@$RED_ELK_SERVER_IP <<EOF
sudo echo "#*/2 * * * * redelk /usr/share/redelk/bin/getremotelogs.sh $TEAMSERVER_IP TeamServer scponly" >> /etc/cron.d/redelk #s/kali/tsdisplayname/
EOF
done

echo "Update scripts in /etc/redelk/* as needed."
echo "If things aren't working, check the following logs on the Elk server"
echo "/var/log/filebeat/filebeat"
echo "/var/log/filestash/filestash-plain.log"
echo
echo "Done"

