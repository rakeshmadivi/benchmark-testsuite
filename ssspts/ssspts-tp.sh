#!/bin/bash

# TROUGHPUT POST RUN
# Arguments: rwmixwrite%
tp_post_run()
{
	echo -e "\nPerforming post run data formatting...\n" >> echolog

	echo RWMIX: $1 BLKSIZE: $blk_size  >> echolog


	rm -rf $w100percent

	tf=temp.txt
	rm -rf $tf

	w_from=$(expr $SS_ROUND - $((window_size - 1)) )
	w_seq=`seq $w_from $SS_ROUND`

	logit "TP_POST_RUN" "TP_Convergence"
	# THROUGHPUT STEADY STATE CONVERGENCE
	echo Generating THROUGHPUT STEADY STATE CONVERGENCE \[ For Read and Write Separately \]...  >> echolog

	#########################
	values100=""
	values0=""
	for i in `seq $w_from $SS_ROUND`	#$(expr $SS_ROUND - $((window_size - 1))) $SS_ROUND`
	do
		for j in 128k 1024k
		do
			egrep "^100 $j $i" ${tp_files[0]} >/dev/null 2>&1
			wfound=$?
			[ $wfound -eq 1 ] && values100="$values100 NA"
			[ $wfound ] && values100="$values100 `egrep "^100 $j $i" ${tp_files[0]}|awk '{print $5}'`"

			egrep "^0 $j $i" ${tp_files[0]} >/dev/null 2>&1
			rfound=$?
			[ $rfound  -eq 1 ] && values0="$values0 NA"
			[ $rfound ] && values0="$values0 `egrep "^0 $j $i" ${tp_files[0]}|awk '{print $4}'`"
		done
		#[ $1 -eq 100 ] && echo $i $values100 | sed 's/ /,/g' >> ${tp_files[1]}
		#[ $1 -eq 0 ] && echo $i $values0 | sed 's/ /,/g' >> ${tp_files[2]}
		[ $1 -eq 100 ] && echo $i $values100 | tr " " "\n"|paste -d, -s >> ${tp_files[1]}
		[ $1 -eq 0 ] && echo $i $values0 | tr " " "\n"|paste -d, -s >> ${tp_files[2]}

		values100=""
		values0=""
	done

	echo TP_SS_Covergence-WRITE: 128k > ${tp_files[4]}
	echo ROUND,128k >> ${tp_files[4]}
	#egrep "NA" ${tp_files[1]}| awk -F ',' '{print $1","$2}' >> ${tp_files[4]} 
	awk -F ',' '{if($3 == "NA")print $1","$2}' ${tp_files[1]} >> ${tp_files[4]} 
	
	echo TP_SS_Covergence-WRITE: 1024k >> ${tp_files[4]}
	echo ROUND,1024k >> ${tp_files[4]}
	awk -F ',' '{if($1 != "ROUND" && $3 != "NA")print $1","$3}' ${tp_files[1]} >> ${tp_files[4]}
	
	echo TP_SS_Covergence-READ: 128k >> ${tp_files[4]}
	echo ROUND,128k >> ${tp_files[4]}
	#egrep "NA" ${tp_files[2]}| awk -F ',' '{print $1","$2}' >> ${tp_files[4]} 
	awk -F ',' '{if($3 == "NA")print $1","$2}' ${tp_files[2]} >> ${tp_files[4]} 
	
	echo TP_SS_Covergence-READ: 1024k >> ${tp_files[4]}
	echo ROUND,1024k >> ${tp_files[4]}
	awk -F ',' '{if($1 != "ROUND" && $3 != "NA")print $1","$3}' ${tp_files[2]} >> ${tp_files[4]}

	#########################

	logit "TP_POST_RUN" "TP_Measurement_Window_Tabular_Data"
	# AVERAGES - TP Measurement Window Tabular Data
	#########################
	echo "TP - Calculating Average of all rounds..." >> echolog

	w128avg=$(awk -F ',' -v ws=$window_size '{if($3 == "NA")sum+=$2;cnt+=1}END{print sum/ws}' ${tp_files[1]})
	w1024avg=$(awk -F ',' -v ws=$window_size '{if($1 != "ROUND" && $3 != "NA")sum+=$3;cnt+=1}END{print sum/ws}' ${tp_files[1]})

	r128avg=$(awk -F ',' -v ws=$window_size '{if($3 == "NA")sum+=$2;cnt+=1}END{print sum/ws}' ${tp_files[2]})
	r1024avg=$(awk -F ',' -v ws=$window_size '{if($1 != "ROUND" && $3 != "NA")sum+=$3;cnt+=1}END{print sum/ws}' ${tp_files[2]})

	# tp_measurement_window_tabular_data.csv
	echo BLOCK_SIZE,0/100,100/0 > ${tp_files[6]}
	echo 128k,${w128avg},${r128avg} >> ${tp_files[6]}
	echo 1024k,${w1024avg},${r1024avg} >> ${tp_files[6]}

	#### Take values from steadystate.log and calculate best-fit for TP_SS_CONVEGENCE_WINDOW_PLOT
	# Returns array of bestfit values for each set

	logit "TP_POST_RUN" "TP_SS_Convergce Window"
	# TP_SS_CONVERGENCE_WINDOW_PLOT
		
	# 128K
	arr=(`grep "\[100,128k," $sslog |awk '{print $2" "$4" "$5}'`); 
	w128k=($(for i in `echo ${arr[0]}| awk -F, '{print $3}'|tr -d ']'|sed 's/-/ /g'`;do echo "$i * ${arr[1]} + ${arr[2]}"|bc;done));

	arr=(`grep "\[0,128k," $sslog |awk '{print $2" "$4" "$5}'`); 
	r128k=($(for i in `echo ${arr[0]}| awk -F, '{print $3}'|tr -d ']'|sed 's/-/ /g'`;do echo "$i * ${arr[1]} + ${arr[2]}"|bc;done)); 

	echo -e "128k-WRITE\nROUND,WRITE_TP,100%-Avg,110%-Avg,90%-Avg,Best_fit" > ${tp_files[5]}
	awk -F ',' '{if($3 == "NA")print $1","$2}' ${tp_files[1]}|awk -F',' -v w128avg=$w128avg -v bfit="$(echo ${w128k[@]})" -v id=1 '{split(bfit,bfit_arr," ");print $1","$2","w128avg","1.1*w128avg","0.9*w128avg","bfit_arr[id];id+=1}' >> ${tp_files[5]}
	echo -e "128k-READ,\nROUND,READ_TP,100%-Avg,110%-Avg,90%-Avg,Best_fit" >> ${tp_files[5]}
	awk -F ',' '{if($3 == "NA") print $1","$2}' ${tp_files[2]}| awk -F ',' -v r128avg=$r128avg -v bfit="$(echo ${r128k[@]})" -v id=1 '{split(bfit,bfit_arr," ");print $1","$2","r128avg","1.1*r128avg","0.9*r128avg","bfit_arr[id];id+=1}' >> ${tp_files[5]} 


	# 1024k
	arr=(`grep "\[100,1024k," $sslog |awk '{print $2" "$4" "$5}'`); 
	w1024k=($(for i in `echo ${arr[0]}| awk -F, '{print $3}'|tr -d ']'|sed 's/-/ /g'`;do echo "$i * ${arr[1]} + ${arr[2]}"|bc;done));

	arr=(`grep "\[0,1024k," $sslog |awk '{print $2" "$4" "$5}'`); 
	r1024k=($(for i in `echo ${arr[0]}| awk -F, '{print $3}'|tr -d ']'|sed 's/-/ /g'`;do echo "$i * ${arr[1]} + ${arr[2]}"|bc;done)); 
	
	echo -e "1024k-WRITE\nROUND,WRITE_TP,100%-Avg,110%-Avg,90%-Avg,Best_fit" >> ${tp_files[5]}
	awk -F ',' '{if($1 != "ROUND" && $3 != "NA")print $1","$3}' ${tp_files[1]} |awk -F ',' -v w1024avg=$w1024avg -v bfit="$(echo ${w1024k[@]})" -v id=1 '{split(bfit,bfit_arr," ");print $1","$2","w1024avg","1.1*w1024avg","0.9*w1024avg","bfit_arr[id];id+=1}' >> ${tp_files[5]}
	echo -e "1024k-READ\nROUND,READ_TP,100%-Avg,110%-Avg,90%-Avg,Best_fit" >> ${tp_files[5]}
	awk -F ',' '{if($1 != "ROUND" && $3 != "NA")print $1","$3}' ${tp_files[2]}| awk -F ',' -v r1024avg=$r1024avg -v bfit="$(echo ${r1024k[@]})" -v id=1 '{split(bfit,bfit_arr," ");print $1","$2","r1024avg","1.1*r1024avg","0.9*r1024avg","bfit_arr[id];id+=1}' >> ${tp_files[5]}
}

################## THROUGHPUT TEST ACTIVATION ###########
ssd_tp()
{
  	set -x
	# For ActiveRange 0:100
	# purge
	# Run Workload Independent Pre-conditioning
	#**********************************************************************************************************#
	# Set and record test conditions
	# Disable device volatile write cache, OIO/Threads, Thread_count, Data pattern: random,operator
	# Run sequential WIPC with: 2X User capacity @128KiB SEQ Write, writing to entire LBA without restrictions.
	#**********************************************************************************************************#

	# THROUGHPUT SETTINGS
	tp_rwtype=rw	# Mixed sequential reads and writes

	rm -rf ${tp_files[@]}
	echo ROUND,128k,1024k >&2 | tee -a ${tp_files[1]} ${tp_files[2]}
	logit "SSD_TP" "Starting TP_Test"
	for blk_size in 128k 1024k
	do
		for rwmix in 100 0	# Read-Write Mix (0/100,100/0)
		do
			echo Running rwmix=$rwmix >> echolog;
			export SS_ROUND=""
			#echo ${blk_size}_${rwmix} | tee -a ${tp_files[1]} ${tp_files[2]}
			
			logit "SSD_TP" "TP_Params: BLKSIZE: $blk_size RWMIX: $rwmix"
			logit "SSD_TP" "TP_Activation"
			# ACTIVATION
			echo Running Workload Independent Preconditioning... >> echolog

			sudo fio --name=WIPC --filename=${test_file} --size=${size} --bs=${blk_size} --direct=${DIRECT} --rw=write --iodepth=${usr_iodepth} > tp_prep_result.txt 

			logit "SSD_TP" "TP_TestStimulus"
			# START TESTING
			round=1
			while true
			do
				# CONTINUE TEST UNTIL ROUND 25
				if [ $round -gt 25 ]
				then 
					echo "STEADY STATE IS NOT FOUND EVEN AFTER ROUND $((round-1))... " #>> echolog
					echo "Aborting the run...\n" >> echolog;exit 1
				fi
				
				echo -en "\r\033[1KRunning ROUND: $round "
				logit "SSD_TP" "Status: STOP_NOW = $STOP_NOW"
				# Check STOP_NOW Status to break
				if [ "$STOP_NOW" = "y" ]
				then
					tp_post_run $rwmix $blk_size
					
					#reset the value before exiting.
					export STOP_NOW="n"
					echo Breaking out of run loop... >> echolog
					break;
					#continue;
				fi

				echo Running $rwmix $blk_size >> echolog

				test_size="`echo "${size: :-1}/2"|bc``echo ${size: -1}`"
				echo test_size:$test_size >> echolog

				## NEW
				logit "SSD_TP" "Running BlockSize = $blk_size RWMIX-WRITE: $rwmix @ Round-$round"
				output=$(echo `sudo fio --name=WDPC --filename=${test_file} --bs=${blk_size} --rwmixwrite=${rwmix} --rw=${tp_rwtype} --runtime=${run_time} --direct=${DIRECT} --sync=${SYNC} --iodepth=${usr_iodepth}|grep aggrb |cut -f2 -d ','|cut -f2 -d'='`)

				output_val=$(echo ${output:: -4})
				units=$(echo $output| grep -o ....$)

				echo -n "$blk_size RW_MIX:${rwmix}: " >> $aggrlog

				if test $units == "MB/s"
				then
					val_inkb=$(echo "$output_val * 1024"|bc)
					output_val=$val_inkb
					echo "[${output}] $val_inkb KB/s [Converted]" >> $aggrlog
				else
					echo [${output}] $output_val $units >> $aggrlog
				fi

				logit "SSD_TP" "Value Conversion: [$output] -> [$output_val]"

				if [ $rwmix -eq 100 ];then
					echo "$rwmix $blk_size $round 0 $output_val $output_val" >> ${tp_files[0]}
				elif [ $rwmix -eq 0 ];then
					echo "$rwmix $blk_size $round $output_val  0 $output_val" >> ${tp_files[0]}
				#else
					#echo "$rwmix $blk_size $round $output_val" >> ${tp_files[0]}
				fi

				# CHECKING STEADY STATE
				if [ $round -gt $((window_size-1)) ]
				then
					# Call function to check steady state
					logit "SSD_TP" "TP_CheckSteadyState"
					check_steady_state $rwmix $blk_size $round ${tp_files[0]}
					[ $? -eq 0 ] && logit "SSD_TP" "Exporting STOP_NOW=y" && export STOP_NOW="y"
				fi

				echo Incrementing iteration... >> echolog

				round=$((round+1))
			done	# End While

	  done	# End Inner for i.e RWMIX
	  echo 'continue with next block size(y/n)?' >> echolog

	  #: '
	  #read confirmation

	  confirmation="y"
	  if [ "$confirmation" = "y" ] 
	  then 
		  export STATUS=N; export STOP_NOW=n;
	  else
		  export STOP_NOW=y;break;
	  fi
	  #'
	done	# End Outer for i.e blk_size
      
    echo Moving TP Result files... >> echolog
    logit "SSD_TP" "Moving TP Result files"
    
    echo "EXECUTION DONE." >> echolog
    logit "SSD_TP" "Execution DONE."
    set +x
}

