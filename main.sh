#!/bin/bash

# ensure user is logged in as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# env vars
INTERFACE="wlan0"
SSID="MyAccessPoint"
PASSWORD="password123"
IP_RANGE="192.168.50.1/24"
INTERNET_IFACE="eth0"

# ensure needed packages are installed (hostapd & dnsmasq)
if ! command -v hostapd &> /dev/null; then
  echo "hostapd not found, installing..."
  apt update && apt install -y hostapd
fi

if ! command -v dnsmasq &> /dev/null; then
  echo "dnsmasq not found, installing..."
  apt update && apt install -y dnsmasq
fi

# stop already running services
systemctl stop hostapd
systemctl stop dnsmasq

# Configure the network interface
ip link set $INTERFACE down
ip addr flush dev $INTERFACE
ip addr add 192.168.50.1/24 dev $INTERFACE
ip link set $INTERFACE up

# Configure dnsmasq
cat > /etc/dnsmasq.conf <<EOF
interface=$INTERFACE
dhcp-range=192.168.50.10,192.168.50.100,12h
EOF


# hostpad conf
cat > /etc/hostapd/hostapd.conf <<EOF
interface=$INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# start needed services
systemctl enable hostapd
systemctl enable dnsmasq
systemctl start dnsmasq
systemctl start hostapd

# launch ip forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# set up NAT with iptables
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE
iptables -A FORWARD -i $INTERNET_IFACE -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $INTERFACE -o $INTERNET_IFACE -j ACCEPT

# show result on console
echo "Access Point '$SSID' created on interface $INTERFACE with internet access"