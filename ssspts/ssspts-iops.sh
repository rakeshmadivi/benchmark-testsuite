#!/bin/bash

############################## IOPS TEST ACTIVATION #############################
ssd_iops()
{
	set -x

	if [ $usr_skip_purge -eq 0 ]
	then
		# PURGE DEVICE
		# -p | --skip-purge	Skip Device purge operation\n
		logit "SSD_IOPS" "DEVICE PURGE Enabled"
		purge
	else
		logit "SSD_IOPS" "DEVICE PURGE Disabled"
	fi

	logit "SSD_IOPS" "WIPC: Activation/Independent Pre-conditioning."

	if [ $usr_skip_preconditioning -eq 0 ]
	then

		# ACTIVATION
		# -c | --skip-preconditioning	Disable preconditioning\n
		logit "SSD_IOPS" "Running Workload Independent Preconditioning."
		sudo fio --name=WIPC_${wipc_bs}_${wipc_rw_type} --filename=${test_file} --size=${size} --bs=${wipc_bs} --direct=${DIRECT} --rw=${wipc_rw_type} --iodepth=${usr_iodepth} --output-format=json > $prep_result 
	else
		logit "SSD_IOPS" "Skipping WIPC"
	fi

	logit "SSD_IOPS" "WDPC: Testing/Stimulus/Dependent Pre-conditioning."

	# START TESTING
	round=1
	while true
	do
		st=$SECONDS

		# CONTINUE TEST UNTIL ROUND Max-rounds
		#-m | --max-rounds	Max no.of rounds test to be executed\n
		if [ $round -gt ${usr_maxrounds} ] #25 ]
		then
			logit "SSD_IOPS" "Note: No Seady State found even after Round 25."
			echo "STEADY STATE IS NOT FOUND EVEN AFTER ROUND $((round-1))... " #>> echolog
			echo "Aborting the run...\n" >> echolog;
			exit 1
		fi

		echo -en "\r\033[1KRunning ROUND: $round"
		# -w | --rwmixwrite	ReadWrite Mix of Writes\n
		# -b | --block-sizes	User provided block sizes\n
		for rwmix in ${usr_mix}	#100 95 65 50 35 5 0
		do
			for blk_size in ${usr_blocks} #4k 8k 16k 32k 64k 128k 1024k
			do
				echo Running $rwmix $blk_size >> echolog

				st=$SECONDS
				test_size="`echo "${size: :-1}/2"|bc``echo ${size: -1}`"

				logit "SSD_IOPS" "Testing: RWMIX-write = $rwmix Block_size = $blk_size Round = $round"
				# OPTIONS TO BE USED IN TEST STIMULUS
				# -i | --iodepth	I/O Depth\n
				# -n | --numjobs	Number of jobs to perform the test\n
				# -t | --write-pattern	Pettern to fill IO Buffers content\n
				# -r | --active-range	Address range of test operation\n

				json_outfile=${json_dir}/${rwmix}_${blk_size}_result.json

				sudo fio --name=WDPC_${blk_size}_${rwmix}_${round} --filename=${test_file} --bs=${blk_size} --rwmixwrite=${rwmix} --direct=${DIRECT} --sync=${SYNC} --rw=${wdpc_rw_type} --runtime=${run_time} --iodepth=${usr_iodepth} --numjobs=${usr_numjobs} --buffer_pattern=${usr_writepattern} --output-format=json > $json_outfile 

				r_iops=`jq '.jobs | .[].read.iops' $json_outfile | awk '{sum+=$0} END {print sum}'`
				w_iops=`jq '.jobs | .[].write.iops' $json_outfile | awk '{sum+=$0} END {print sum}'`
				
				cpu_util=`jq '.jobs | .[].usr_cpu' $json_outfile | awk '{sum+=$0} END {print sum}'`

				logit "SSD_IOPS" "r_iops: $r_iops w_iops: $w_iops"

				echo "$rwmix $blk_size $round $r_iops $w_iops $(echo $r_iops + $w_iops | bc)" >> $datafile

				et=$SECONDS
				logit "SSD_IOPS" "Elapsed Time = $((et-st))s"
			done
		done
		et=$SECONDS

		echo Iteration: $round Elapsed Time: $((et-st)) seconds >> echolog

		if [ $round -gt $((window_size-1)) ]
		then
			# SS CHECK VAR1
			logit "SSD_IOPS" "Checking Steady State for - 100 4k $round"
			check_steady_state 100 4k $round $datafile
			prev=$?

			if [ $ptsversion -eq 3 ]
			then
				#: '
				# SS CHECK VAR2
				logit "SSD_IOPS" "Checking Steady State for - 35 64k $round prev_status = $prev"
				[ $prev -eq 0 ] && check_steady_state 35 64k $round $datafile
				prev=$?

				# SS CHECK VAR3
				logit "SSD_IOPS" "Checking Steady State for - 0 1024k $round prev_status = $prev"
				[ $prev -eq 0 ] && check_steady_state 0  1024k $round $datafile
				prev=$?
				#'
			fi

			logit "SSD_IOPS" "Checking if ALL Steady State PARAMS are true. PREV_STATUS = $prev"
			[ $prev -eq 0 ] && export STOP_NOW=y
		fi

		if [ "$STOP_NOW" = "y" ]
		then
			logit "SSD_IOPS" "Steady State Reached @ Round = $round"
			echo Breaking out of run loop... >> echolog
			break;
		fi
		echo Incrementing iteration... >> echolog
		round=$((round+1))

	done

	# Process and Plot the accumulated rounds data 
	echo "EXECUTION DONE." >> echolog

	logit "SSD_IOPS" "Execution DONE."
	set +x
}


