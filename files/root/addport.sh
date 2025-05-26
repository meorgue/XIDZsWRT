#!/bin/bash

FILE="/etc/board.json"

sed -i '5i\
    },\
	"network": {\
		"lan": {\
			"ports": "eth0",\
			"protocol": "static"\
    },\
    "wan": {\
      "ports": ["eth1", "usb0"],\
      "protocol": "dhcp"\
    ' "$FILE"

rm -- "$0"
