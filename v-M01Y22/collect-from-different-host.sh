#!/bin/bash
#set -x
#source ~/.bashrc
source power-stats.sh

numa_cmd="lscpu | grep NUMA | head -1 | cut -f2 -d: | xargs"

remoteJbbCheck(){

	[ $# -ne 2 ] && echo Invalid no.of args. Exiting... && exit	
	rhost=$1
	rstatus=$2

	jbbrun_check_cmd='[ ! -z "$(pidof java)" ] && echo $?'
	t1=$SECONDS
	while true
	do
		jbbrunning=$(ssh $rhost "$(cat ./remote-jbb-check.sh)")
		if [ "$jbbrunning" == "1" ]
		then
			echo No JBB running on remote host: $rhost. Exting Collection.
			echo STOP > $rstatus
			break;
		else
			echo Remote host: $rhost running SPECJBB

			t2=$SECONDS

			ranfor=$((110*60))
			if [ $((t2-t1)) -lt $ranfor ]
			then
				sleep $((4*60))
			else
				sleep 60
			fi
		fi
	done

}

for i in 10.0.48.158 10.0.48.159
do
	echo "Starting on: $i"
	status_file=run-on-GB-$i
	remote_host=${REMOTE_USER:-RemoteUser}@$i
	output=GB-AMD7713-NUMA$(ssh $remote_host "$numa_cmd")-power-metrics

	remoteJbbCheck $remote_host $status_file > remote-collection-status-$i.log 2>&1 &

	start_power_collection --bmc ${i/48/51} --tool redfish --collect-status-file $status_file --output $output --jbb-run-log jbblog > remote-collection-on-$i 2>&1 & 
done
