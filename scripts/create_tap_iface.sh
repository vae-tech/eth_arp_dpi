#! /bin/sh

if [ $(id -u) -ne 0 ]
then
  echo "Superuser mode required -> sudo ./create_tap_iface.sh"
  exit 1
fi

echo "Creating tap0 interface..."

# Create tap0 interface
ip tuntap add tap0 mode tap group netdev

# Configure IP addresses
ip addr add 192.168.43.1/24 dev tap0

# Set reverse path filter
sysctl -w net.ipv4.conf.tap0.rp_filter=2

# Bring interface up
ip link set tap0 up

echo "tap0 interface created successfully"

