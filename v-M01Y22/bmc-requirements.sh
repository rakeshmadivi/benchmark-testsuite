#!/bin/bash

[ $# -ne 2 ] && echo "Require essential BMC info. USAGE: $0 --bmc <BMC-IP>:<BMC-USERNAME>:<BMC-PASSWORD>" $0 && exit
[ "$1" != "--bmc" ] && echo "Invalid option $1" && exit

REDFISH_ROOT="redfish/v1"

CHASSIS=()
SYSTEM=()
NETWORK=()
DISK=()
PCI=()

query(){
	curl -skL -u https:/$BMC_IP/$REDFISH_ROOT/$URI
}


