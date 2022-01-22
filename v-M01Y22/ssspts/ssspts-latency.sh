#!/bin/bash

########################################## LATENCY TEST ################################################
find_5_9s() # $1: No.of Jobs
{
	all5_9s=()
	set -x
	for i in $(seq 1 $1)	# For every job log file
	do
		local _hundred_percent_nr=$(cat latlog_clat.$i.log |sort -nk2 |wc -l)
		local _hundred_percent_max=$(cat latlog_clat.$i.log |sort -nk2 |tail -1|cut -f2 -d,|tr -d " ")
		logit "LATENCY_5_9s" "100%_NumLines = $_hundred_percent_nr 100% Value = $_hundred_percent_max"
		
		local _clat_mean=$(awk -F, '{sum+=$2}END{print sum/NR}' latlog_clat.$i.log)
		local _lat_mean=$(awk -F, '{sum+=$2}END{print sum/NR}' latlog_lat.$i.log)
		logit "LATENCY_5_9s" "LAT_MEAN = $_lat_mean, CLAT_MEAN = $_clat_mean"

		local _five9s_nr=$(printf "%.f" $(echo $_hundred_percent_nr \* 0.99999|bc))
		local _five9s_val=$(cat latlog_clat.$i.log |sort -nk2 | head -${_five9s_nr} |tail -1|cut -f2 -d,|tr -d " ")
		logit "LATENCY_5_9s" "99%_NumLines = $_five9s_nr 99% Value: $_five9s_val"
		#all5_9s+=("$i,{$_hundred_percent_nr,$_hundred_percent_max,$_clat_mean,$_lat_mean,$_five9s_nr,$_five9s_val}")
		echo "$i,{$_hundred_percent_nr,$_hundred_percent_max,$_clat_mean,$_lat_mean,$_five9s_nr,$_five9s_val}" >> all5_9s.csv
	done
	set +x
	
}

ssd_latency()
{
	# PURGE

	set -x
	# For ActiveRange 0:100
	if [ $usr_skip_purge -eq 0 ]
	then
		# PURGE DEVICE
		# -p | --skip-purge	Skip Device purge operation\n
		logit "SSD_LATENCY" "DEVICE PURGE Enabled"
		purge
	else
		logit "SSD_LATENCY" "DEVICE PURGE Disabled"
	fi

	logit "SSD_LATENCY" "WIPC: Activation/Independent Pre-conditioning."

	if [ $usr_skip_preconditioning -eq 0 ]
	then
		# ACTIVATION
		# -c | --skip-preconditioning	Disable preconditioning\n
		logit "SSD_LATENCY" "Running Workload Independent Preconditioning."
		sudo fio --name=WIPC_${wipc_bs}_${wipc_rw_type} --filename=${test_file} --size=${size} --bs=${wipc_bs} --direct=${DIRECT} --rw=${wipc_rw_type} --iodepth=${usr_iodepth} --output-format=json > $prep_result 
	else
		logit "SSD_LATENCY" "Skipping WIPC"
	fi

	logit "SSD_LATENCY" "WDPC: Testing/Stimulus/Dependent Pre-conditioning."

	# START TESTING
	round=1
	while true
	do
		st=$SECONDS

		# CONTINUE TEST UNTIL ROUND Max-rounds
		#-m | --max-rounds	Max no.of rounds test to be executed\n
		if [ $round -gt ${usr_maxrounds} ] #25 ]
		then
			logit "SSD_LATENCY" "Note: No Seady State found even after Round 25."
			echo "STEADY STATE IS NOT FOUND EVEN AFTER ROUND $((round-1))... " #>> echolog
			echo "Aborting the run...\n" >> echolog;
			echo
			exit 1
		fi

		echo -en "\r\033[1KRunning ROUND: $round"
		# -w | --rwmixwrite	ReadWrite Mix of Writes\n
		# -b | --block-sizes	User provided block sizes\n
		for rwmix in ${usr_mix}	
		do
			for blk_size in ${usr_blocks} 
			do
				echo Running $rwmix $blk_size >> echolog

				test_size="`echo "${size: :-1}/2"|bc``echo ${size: -1}`"

				logit "SSD_LATENCY" "Testing: RWMIX-write = $rwmix Block_size = $blk_size Round = $round"
				# OPTIONS TO BE USED IN TEST STIMULUS
				# -i | --iodepth	I/O Depth\n
				# -n | --numjobs	Number of jobs to perform the test\n
				# -t | --write-pattern	Pettern to fill IO Buffers content\n
				# -r | --active-range	Address range of test operation\n

				json_outfile=${json_dir}/${rwmix}_${blk_size}_result.json

				sudo fio --name=WDPC_${blk_size}_${rwmix}_${round} --filename=${test_file} --bs=${blk_size} --rwmixwrite=${rwmix} --direct=${DIRECT} --sync=${SYNC} --rw=${wdpc_rw_type} --runtime=${run_time} --iodepth=${usr_iodepth} --numjobs=${usr_numjobs} --buffer_pattern=${usr_writepattern} --output-format=json --percentile_list=99.999 --write_lat_log=latlog --group_reporting > $json_outfile

				# ** SHOULD WE DO FOLLOWING -BLOCK- FOR EVERY THREAD CREATED ?
				find_5_9s $usr_numjobs 2>find_5_9s.output

				local _hundred_percent_nr=$(cat latlog_clat.1.log |sort -nk2 |wc -l)
				local _hundred_percent_max=$(cat latlog_clat.1.log |sort -nk2 |tail -1|cut -f2 -d,|tr -d " ")
				logit "SSD_LATENCY" "100%_NumLines = $_hundred_percent_nr 100% Value = $_hundred_percent_max"
				
				local _clat_mean=$(awk -F, '{sum+=$2}END{print sum/NR}' latlog_clat.1.log)
				local _lat_mean=$(awk -F, '{sum+=$2}END{print sum/NR}' latlog_lat.1.log)
				logit "SSD_LATENCY" "LAT_MEAN = $_lat_mean, CLAT_MEAN = $_clat_mean"

				local _five9s_nr=$(printf "%.f" $(echo $_hundred_percent_nr \* 0.99999|bc))
				local _five9s_val=$(cat latlog_clat.1.log |sort -nk2 | head -${_five9s_nr} |tail -1|cut -f2 -d,|tr -d " ")
				logit "SSD_LATENCY" "99%_NumLines = $_five9s_nr 99% Value: $_five9s_val"

				for i in ${!rt[@]}
				do
					rt_r+=(`jq ".jobs | .[].read.${rt[$i]}" $json_outfile | awk '{sum+=$0} END {print sum}'`)
					rt_w+=(`jq ".jobs | .[].write.${rt[$i]}" $json_outfile | awk '{sum+=$0} END {print sum}'`)
				done
				
				local _result=$(for i in `seq 0 $((${#rt[@]}-1))`;do echo ${rt[$i]} = ${rt_r[$i]}:${rt_w[$i]};done | tr "\n" ";\s")
				logit "SSD_LATENCY" "$_result"

				# ** -END OF BLOCK-

				# MIX BS ROUND No.ofLinesOf100% IOPS LAT_MEAN CLAT_MEAN Five9sCLAT CLAT_MAX
				echo "$rwmix $blk_size $round NL_$_hundred_percent_nr $(echo ${rt_r[0]} + ${rt_w[0]} | bc) $_lat_mean $_clat_mean $_five9s_val $_hundred_percent_max " >> $datafile

				# Unset all previously initialized arrays: rt_r,rt_w 
				unset rt_r
				unset rt_w
			done
		done
		et=$SECONDS

		echo Iteration: $round Elapsed Time: $((et-st)) seconds >> echolog

		if [ $round -gt $((window_size-1)) ]
		then
			logit "SSD_LATENCY" "Checking Steady State for - 100 4k $round"
			#check_steady_state 100 4k $round $datafile
			check_steady_state 0 4k $round $datafile
			[ $? -eq 0 ] && logit "SSD_LATENCY" "Exporting STOP_NOW=y" && export STOP_NOW=y
		fi

		if [ "$STOP_NOW" = "y" ]
		then
			logit "SSD_LATENCY" "Steady State Reached @ Round = $round"
			echo Breaking out of run loop... >> echolog
			break;
		fi
		echo Incrementing iteration... >> echolog
		round=$((round+1))
	done
	
	# RUN WITH BS=4K AND RWMIXWRITE=100
	# FOR LAT RESPONSE TIME HISTOGRAM
	sudo fio --name=WDPC_${blk_size}_${rwmix}_${round} --filename=${test_file} --bs=4k --rwmixwrite=100 --direct=${DIRECT} --sync=${SYNC} --rw=${wdpc_rw_type} --runtime=20m --iodepth=${usr_iodepth} --numjobs=${usr_numjobs} --buffer_pattern=${usr_writepattern} --output-format=json > $rtresult

	for i in ${!rt[@]}
	do
		echo ${rt[$i]},`jq ".jobs|.[].write.${rt[$i]}" $rtresult` >> $rtfile
	done

	# Process and Plot the accumulated rounds data 
	echo "EXECUTION DONE." >> echolog

	logit "SSD_LATENCY" "Execution DONE."
	set +x

}

