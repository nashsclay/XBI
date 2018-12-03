#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE='xbi.conf'
CONFIGFOLDER='/root/.XBI'
COIN_DAEMON='xbid'
COIN_CLI='xbi-cli'
COIN_PATH='/usr/local/bin/'
COIN_REPO='https://github.com/galimba/testing'
COIN_TGZ='https://github.com/galimba/testing/raw/master/xbi-4.3.2.1.zip'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='XBI'
COIN_PORT=7339
RPC_PORT=6259
RPC_OLD_PORT=6250
COIN_OLD_PORT=7332
CAN_UPDATE=1
SHOW_COIN_KEY=0
# add 1 for yes can update 0 for no, if first MN script, put 0
NODEIP=$(curl -s4 icanhazip.com)

BLUE="\033[0;34m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m" 
PURPLE="\033[0;35m"
RED='\033[0;31m'
GREEN="\033[0;32m"
NC='\033[0m'
MAG='\e[1;35m'

function purgeOldInstallation() {
    echo -e "${GREEN}Searching and removing old $COIN_NAME files and configurations${NC}"
    #kill wallet daemon
    systemctl stop $COIN_NAME.service > /dev/null 2>&1
    sudo killall $COIN_DAEMON > /dev/null 2>&1
	# Save Key 
	OLDKEY=$(awk -F'=' '/masternodeprivkey/ {print $2}' $CONFIGFOLDER/$CONFIG_FILE 2> /dev/null)
	if [ "$?" -eq "0" ]; then
    		echo -e "${CYAN}Saving Old Installation Genkey${NC}"
		echo -e $OLDKEY
	fi
    #remove old ufw port allow
    sudo ufw delete allow $COIN_PORT/tcp > /dev/null 2>&1
    #remove old files
    rm rm -- "$0" > /dev/null 2>&1
    sudo rm -rf $CONFIGFOLDER > /dev/null 2>&1
    sudo rm -rf /usr/local/bin/$COIN_CLI /usr/local/bin/$COIN_DAEMON> /dev/null 2>&1
    sudo rm -rf /usr/bin/$COIN_CLI /usr/bin/$COIN_DAEMON > /dev/null 2>&1
    sudo rm -rf /tmp/*
    echo -e "${GREEN}* Done${NONE}";
}


function download_node() {
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME Daemon${NC}"
  cd $TMP_FOLDER >/dev/null 2>&1
  wget -q $COIN_TGZ
  compile_error
  unzip $COIN_ZIP >/dev/null 2>&1
  chmod +x $COIN_DAEMON $COIN_CLI
  mv $COIN_DAEMON $COIN_CLI $COIN_PATH
  cd ~ >/dev/null 2>&1
  rm -rf $TMP_FOLDER >/dev/null 2>&1
  clear
}

function configure_systemd() {
  cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=$CONFIGFOLDER/$COIN_NAME.pid

ExecStart=$COIN_PATH$COIN_DAEMON -daemon -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER
ExecStop=-$COIN_PATH$COIN_CLI -conf=$CONFIGFOLDER/$CONFIG_FILE -datadir=$CONFIGFOLDER stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service >/dev/null 2>&1

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function create_config() {
  mkdir $CONFIGFOLDER >/dev/null 2>&1
  RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
  RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)
  cat << EOF > $CONFIGFOLDER/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcport=$RPC_PORT
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}

function create_key() {
  echo -e "${YELLOW}Enter your ${RED}$COIN_NAME Masternode GEN Key${NC}."
  read -e COINKEY
  if [[ -z "$COINKEY" ]]; then
  $COIN_PATH$COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
   echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
   exit 1
  fi
  COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the GEN Key${NC}"
    sleep 30
    COINKEY=$($COIN_PATH$COIN_CLI masternode genkey)
  fi
  $COIN_PATH$COIN_CLI stop
fi
clear
}

function update_config() {
  sed -i 's/daemon=1/daemon=0/' $CONFIGFOLDER/$CONFIG_FILE
  cat << EOF >> $CONFIGFOLDER/$CONFIG_FILE
logintimestamps=1
maxconnections=256
#bind=$NODEIP
masternode=1
externalip=$NODEIP:$COIN_PORT
masternodeprivkey=$COINKEY

#Addnodes
addnode=45.77.66.151
addnode=199.247.24.242
addnode=95.179.198.223
addnode=45.77.21.46
addnode=104.238.189.176
addnode=108.61.185.148
addnode=45.32.134.213
addnode=45.76.8.202
addnode=149.28.13.176
addnode=95.179.232.26
addnode=149.28.31.212
addnode=45.63.27.217
EOF
}


function enable_firewall() {
  echo -e "Installing and setting up firewall to allow ingress on port ${GREEN}$COIN_PORT${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  ufw allow ssh comment "SSH" >/dev/null 2>&1
  ufw limit ssh/tcp >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  echo "y" | ufw enable >/dev/null 2>&1
}


function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done

  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function compile_error() {
if [ "$?" -gt "0" ];
 then
  echo -e "${RED}Failed to compile $COIN_NAME. Please investigate.${NC}"
  exit 1
fi
}


function checks() {
if [[ $(lsb_release -d) != *16.04* ]]; then
  echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}$0 must be run as root.${NC}"
   exit 1
fi

if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
  echo -e "${RED}$COIN_NAME is already installed.${NC}"
  if [[ "$CAN_UPDATE" -eq "1" ]] ; then
    if [[ $(xbi-cli -version) != *4.3.2.1* ]]; then
      update_node
    fi
  fi
  exit 1
fi
}

function prepare_system() {
echo -e "Preparing the VPS to setup. ${CYAN}$COIN_NAME${NC} ${RED}Masternode${NC}"
apt-get update >/dev/null 2>&1
apt-get -y upgrade >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade >/dev/null 2>&1
apt install -y software-properties-common >/dev/null 2>&1
echo -e "${PURPLE}Adding bitcoin PPA repository"
apt-add-repository -y ppa:bitcoin/bitcoin >/dev/null 2>&1
echo -e "Installing required packages, it may take some time to finish.${NC}"
apt-get update >/dev/null 2>&1
apt-get install libzmq3-dev -y >/dev/null 2>&1
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" make software-properties-common \
build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev libboost-program-options-dev \
libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget curl libdb4.8-dev bsdmainutils libdb4.8++-dev \
libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev  libdb5.3++ unzip libzmq5 >/dev/null 2>&1
apt-get update >/dev/null 2>&1
apt-get -y upgrade >/dev/null 2>&1
if [ "$?" -gt "0" ];
  then
    echo -e "${RED}Not all required packages were installed properly. Try to install them manually by running the following commands:${NC}\n"
    echo "apt-get update"
    echo "apt -y install software-properties-common"
    echo "apt-add-repository -y ppa:bitcoin/bitcoin"
    echo "apt-get update"
    echo "apt install -y make build-essential libtool software-properties-common autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git curl libdb4.8-dev \
bsdmainutils libdb4.8++-dev libminiupnpc-dev libgmp3-dev ufw pkg-config libevent-dev libdb5.3++ unzip libzmq5"
 exit 1
fi
clear
}

function create_swap() {
 echo -e "Checking if swap space is needed."
 PHYMEM=$(free -g|awk '/^Mem:/{print $2}')
 SWAP=$(swapon -s)
 if [[ "$PHYMEM" -lt "2"  &&  -z "$SWAP" ]]
  then
    echo -e "${GREEN}Server is running with less than 2G of RAM without SWAP, creating 2G swap file.${NC}"
    SWAPFILE=$(mktemp)
    dd if=/dev/zero of=$SWAPFILE bs=1024 count=2M
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon -a $SWAPFILE
 else
  echo -e "${GREEN}The server running with at least 2G of RAM, or a SWAP file is already in place.${NC}"
 fi
 clear
}

function update_node() {
  echo -e "Verifying if on updated version..."
  echo -e "Your verison is not current. Updating now!"
    systemctl stop XBI.service
    sed -i 's/rpcport.*/rpcport='"$RPC_PORT"'/' $CONFIGFOLDER/$CONFIG_FILE
    sed -i 's/port='"$COIN_OLD_PORT"'/port='"$COIN_PORT"'/' $CONFIGFOLDER/$CONFIG_FILE
    sed -i 's/externalip=.*.:'"$COIN_OLD_PORT"'/externalip='"$NODEIP"':'"$COIN_PORT"'/' $CONFIGFOLDER/$CONFIG_FILE
    echo "#Addnodes" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=45.77.66.151" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=199.247.24.242" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=95.179.198.223" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=45.77.21.46" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=104.238.189.176" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=108.61.185.148" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=45.32.134.213" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=45.76.8.202" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=149.28.13.176" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=95.179.232.26" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=149.28.31.212" >> $CONFIGFOLDER/$CONFIG_FILE
    echo "addnode=45.63.27.217" >> $CONFIGFOLDER/$CONFIG_FILE
    sudo ufw delete allow $COIN_OLD_PORT/tcp > /dev/null 2>&1
    sudo rm -rf /usr/local/bin/$COIN_CLI /usr/local/bin/$COIN_DAEMON> /dev/null 2>&1
    sudo rm -rf /usr/bin/$COIN_CLI /usr/bin/$COIN_DAEMON > /dev/null 2>&1
    download_node
    enable_firewall
    systemctl daemon-reload
    sleep 3
    systemctl start $COIN_NAME.service
    systemctl enable $COIN_NAME.service >/dev/null 2>&1
    systemctl stop $COIN_NAME.service
    xbi-cli stop
    xbid -daemon -reindex
    $SHOW_COIN_KEY="1"
    OLDKEY=$(awk -F'=' '/masternodeprivkey/ {print $2}' $CONFIGFOLDER/$CONFIG_FILE 2> /dev/null)
    important_information
}

function important_information() {
 echo
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${PURPLE}Windows Wallet Guide. https://github.com/sub307/Bitcoin_Incognito/blob/master/README.md${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}$COIN_NAME Masternode is up and running listening on port${NC}${PURPLE}$COIN_PORT${NC}."
 echo -e "${GREEN}Configuration file is:${NC}${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "${GREEN}Start:${NC}${RED}systemctl start $COIN_NAME.service${NC}"
 echo -e "${GREEN}Stop:${NC}${RED}systemctl stop $COIN_NAME.service${NC}"
 echo -e "${GREEN}VPS_IP:${NC}${GREEN}$NODEIP:$COIN_PORT${NC}"
 if [ "$SHOW_COIN_KEY" -eq "1" ];
   then
      echo -e "${GREEN}MASTERNODE GENKEY is:${NC}${PURPLE}$OLDKEY${NC}"
   else
      echo -e "${GREEN}MASTERNODE GENKEY is:${NC}${PURPLE}$COINKEY${NC}"
 fi
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${CYAN}Ensure Node is fully SYNCED with BLOCKCHAIN before starting your Node :).${NC}"
 echo -e "${CYAN}FIRST command may be slow to deliver response back. Give MN a few seconds to finish setup.${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
 echo -e "${GREEN}Usage Commands.${NC}"
 echo -e "${GREEN}xbi-cli masternode status${NC}"
 echo -e "${GREEN}xbi-cli getinfo.${NC}"
 echo -e "${BLUE}================================================================================================================================${NC}"
}

function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  important_information
  configure_systemd
}


##### Main #####
clear

checks
purgeOldInstallation
prepare_system
create_swap
download_node
setup_node
