#!/bin/bash

while [ "$1" != "" ]
do
	case "$1" in
		--bmc | -b)
			bmc=$2
			shift 2;;
		--user | -u)
			bmc_user=$2
			shift 2;;
		--pwd | -p)
			bmc_pwd=$2
			shift 2;;
		--get-log | -l)
			logs=$2
			shift 2;;
		--output | -o)
			out=$2
			shift 2;;
		*)
			echo "Inalid Option: $1"
			exit
	esac
done

[ -z "$bmc" ] || [ -z "$bmc_user" ] || [ -z "$bmc_pwd" ] && echo "Require <BMC-IP> <BMC-USER> <BMC-PWD>" && exit

default="sel elist"

if [ ! -z "$logs" ]
then
	echo NEED TODO
	exit
else
	cmd=$default
fi

sudo ipmitool -I lanplus -H $bmc -U $bmc_user -P $bmc_pwd $cmd | tee $out
