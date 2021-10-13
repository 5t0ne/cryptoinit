#!/bin/bash
REPOURL="http://192.168.0.216:8080"
USERNAME="crypto_node"
DATADIR="/var/lib/Crypto"
CONTAINERNAME=crypto_ecs-validator_1


# Check for active network connection
if ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
  echo "Network connection detected. Proceeding."
else
  echo "Please connect to the network before proceeding."
  echo "You can then restart the script by running sudo /etc/profile.d/init.sh"
  exit 1
fi

# Install docker 
sudo apt update && apt upgrade -y
sudo apt install docker-compose curl -y

# Add user for remapping
sudo useradd -r $USERNAME

# Find next usable UID for remapping
nextfreeuid=1001
uidexists=false

while read -r line
do
    entry=($(echo $line| tr ":" "\n"))
    if [ ${entry[0]} == $USERNAME ]
    then
        uidexists=true
    fi
    base=${entry[1]}
    offset=${entry[2]}
    end=$(( $base + $offset ))
    if [[ ("$end" -ge "$nextfreeuid") && ( "$uidexists" == false) ]]
    then
        nextfreeuid=$(( $end + 1000 ))
    elif [ "$uidexists" == true ]
    then
        nextfreeuid=$base
    fi
done < "/etc/subuid"

# Find next usable GID for remapping
nextfreegid=101
gidexists=false

while read -r line
do
    entry=($(echo $line| tr ":" "\n"))
    if [ ${entry[0]} == $USERNAME ]
    then
        gidexists=true
    fi
    base=${entry[1]}
    offset=${entry[2]}
    end=$(( $base + $offset ))
    if [[ ( "$end" -ge "$nextfreegid" ) && ( "$gidexists" == false) ]]
    then
        nextfreegid=$(( $end + 1000 ))
    elif [ "$gidexists" == ture ]
    then
        nextfreegid=$base
    fi
done < "/etc/subgid"

if [ "$nextfreeuid" -lt "$nextfreegid" ]
then
    nextfreeuid=$nextfreegid
else
    nextfreegid=$nextfreeuid
fi

# Set values for GID and UID remapping
if [ "$gidexists" == false ]
then
    echo "GID for remapping is set"
#    echo "$USERNAME:$nextfreegid:65536" >> /etc/subgid
    echo "$USERNAME:$nextfreegid:65536" | sudo tee -a /etc/subgid
fi
if [ "$uidexists" == false ]
then
    echo "UID for remapping is set"
#    echo "$USERNAME:$nextfreeuid:65536" >> /etc/subuid
     echo "$USERNAME:$nextfreeuid:65536" | sudo tee -a /etc/subuid
fi

# Enable remapping on docker daemon
if [ -f "/etc/docker/daemon.json" ]
then
    echo "Daemon configuration already existing."
else
    sudo tee -a /etc/docker/daemon.json > /dev/null <<EOT
{
   "userns-remap": "$USERNAME"
}
EOT
fi

# Restart docker
sudo systemctl restart docker


mkdir -p "$DATADIR/datadir/geth"
cd $DATADIR
wget "$REPOURL/genesis.json"
wget "$REPOURL/archive-node.docker-compose.yaml"
wget "$REPOURL/full-node.docker-compose.yaml"
wget "$REPOURL/light-node.docker-compose.yaml"
wget "$REPOURL/validator.docker-compose.yaml"

chown -R $nextfreeuid:$nextfreegid $DATADIR

docker-compose -f validator.docker-compose.yaml up -d
until [ "`docker inspect -f {{.State.Running}} $CONTAINERNAME`"=="true" ]; do
   sleep 0.1;
done;
#sleep 10s
#docker exec -it $CONTAINERNAME geth account new
