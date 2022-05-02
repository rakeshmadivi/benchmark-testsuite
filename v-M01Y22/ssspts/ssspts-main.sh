#!/bin/bash
#set -x
# Source Global Variables/Functions required for all tests
source ssspts-common.sh

################################################### MAIN EXECUTION STARTS HERE #######################
NPROC=$(lscpu|grep "^CPU(s)"|awk '{print $2}')	#$(nproc)
# -e | --execute	Test to be executed(1 - for IOPS | 2 - for TROUGHPUT)\n
if [ ! -z $device ] 
then
	if [ $execute -eq 1  ]
	then
		# Source IOPS Test file
		source ssspts-iops.sh

		# START CPU USAGE COLLECTION
		logit "SSD_IOPS" "Starting CPU Usage collection with NPROC = $NPROC no.of jobs = $usr_numjobs"
		cpuusage ssd-iops $NPROC $usr_numjobs &
		mpstat_pid=$!
		logit "MPSTAT_PID" "mpstat pid: $mpstat_pid ppid: $$"

		# START TEST
		ssd_iops 2>$debugfile
		
		logit "SSD_IOPS:" "Stopping CPU Collection...(pid-$mpstat_pid)"
		kill -9 $mpstat_pid 

		# POST RUN FORMATTING
		post_run 2>debug.postrun
		generate_usr_requested "$usr_blocksizes" "$usr_rwmixwrite"

		echo	
		# Print all set parameters
		for i in ${store[@]};do echo $i ;done

	elif [ $execute -eq 2  ]
	then
		# Source TROUGHPUT  Test file
		source ssspts-tp.sh
		
		# START CPU USAGE COLLECTION
		logit "SSD_TP" "Starting CPU Usage collection with NPROC = $NPROC no.of jobs = $usr_numjobs"
		cpuusage ssd-tp $NPROC $usr_numjobs &
		mpstat_pid=$!
		logit "MPSTAT_PID" "mpstat pid: $mpstat_pid ppid: $$"
		
		# START TEST
		ssd_tp 2>$debugfile
		
		logit "SSD_TP:" "Stopping CPU Collection...(pid-$mpstat_pid)"
		kill -9 $mpstat_pid 
	
	elif [ $execute -eq 3  ]
	then
		# Source LATENCY Test file
		source ssspts-latency.sh
		
		# CHANGE MIX and BLOCK SIZES AS PER LATENCY TEST REQUIREMENTS
		usr_rwmixwrite="0,35,100"
		usr_blocksizes="8k,4k,1k"
		format_user_input >&2

		# START CPU USAGE COLLECTION
		logit "SSD_LATENCY" "Starting CPU Usage collection with NPROC = $NPROC no.of jobs = $usr_numjobs"
		cpuusage ssd-latency $NPROC $usr_numjobs &
		mpstat_pid=$!
		logit "MPSTAT_PID" "mpstat pid: $mpstat_pid ppid: $$"
		
		# START TEST
		ssd_latency 2>$debugfile
		
		logit "SSD_LATENCY:" "Stopping CPU Collection...(pid-$mpstat_pid)"
		kill -9 $mpstat_pid 
		
		# POST RUN FORMATTING
		post_run 2>debug.postrun
	fi
	echo
fi # End of Device Condition
