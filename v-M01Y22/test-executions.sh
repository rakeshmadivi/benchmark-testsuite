#!/bin/bash
set -ue

THISFILE=$(basename $BASH_SOURCE)
te_dbgf=debug.${THISFILE/.sh/}

[ $app_DEBUG -eq 2 ] && set -x 

[ $app_DEBUG -eq 5 ] && exec 2> $te_dbgf

app_add_fname "speccpu_tests"
function speccpu_tests()
{
  default_loc=${HOME}/spec2017
  echo -e "SPEC HOME Location: $default_loc \nIs above location correct?(y/n): "
  read confirm
  speccpu_home=""
  if [ "$confirm" = "y" ];then
    speccpu_home=$default_loc
  else
    echo -e "Please enter SPECCPU-2017 Installed Location(Full path): "
    read speccpu_home #=$HOME/spec2017_install/
  fi
  
  echo -e "SELECTED SPEC HOME LOCATION: ${speccpu_home}\n"
  echo Sourcing SPEC Environment...
  cd $speccpu_home && source shrc
  
  cd config
  cfg_list=($(echo `ls *.cfg`))
  for i in $(seq 0 $(( ${#cfg_list[*]} - 1)) )
  do
    echo $i ${cfg_list[$i]}      
  done
  
  echo -e "Enter config file index: "
  read cfg_option
  cfgfile=${cfg_list[$cfg_option]}
  
  #=$1
  copies=$ncpus
  threads=1
  
  stack_size=`ulimit -s`
  stack_msg="\nNOTE: Stack Size is lesser than required limit. You might want to increase limit else you might experience cam4_s failure.\n"
  
  echo -e "Changing STACKSIZE soft limit..."
  ulimit -S -s 512000
  
  echo ULIMIT: `ulimit -s`
  
  echo -e "\nUSING CONFIGURATION FILE: $cfgfile [ PATH: $PWD ] \n"
  #cd $speccpu_home/
  #source $speccpu_home/shrc
  #cd config
  
  label=$(sudo dmidecode -s system-manufacturer | awk '{print $1}')-$(sudo dmidecode -s processor-version | sed 's/(R)//g; s/@//g' | uniq | xargs | tr ' ' '-')

  declare -a spectests=("intrate" "fprate") # 
  for i in "${spectests[@]}"
  do    
    sleep 3
    st=$SECONDS
      if [ "$i" = "intspeed" ] || [ "$i" = "fpspeed" ]; then
        copies=1
        threads=1 # $th_per_core
        
        echo -e "RUN: $i \nCONFIG: $cfgfile \nCOPIES: $copies THREADS: $threads"
        
        pin=`cat /sys/devices/system/cpu/cpu1/topology/thread_siblings_list`
        if [ $threads -eq 1 ]
	then
	       pinned=${pin/,*/}
        else
	       pinned=${pin}
	fi

	echo -e "Running $i with PINNING: ${pinned}"
	sleep 3
        
	time numactl -C ${pinned} -l runcpu -c $cfgfile --rebuild --define label=$label --define build_ncpus=$(nproc) --tune=base --copies=$copies --threads=$threads --reportable --iterations=3 $i
        
      else
        copies=$ncpus
        threads=1
        echo -e "RUN: $i \nCONFIG: $cfgfile \nCOPIES: $copies THREADS: $threads"
	sleep 3

        time runcpu -c $cfgfile --rebuild --define label=$label --define build_ncpus=$(nproc) --tune=base --copies=$copies --threads=$threads --reportable --iterations=3 $i
      fi
    en=$SECONDS
    echo -e "${i} : Elapsed time - $((en-st)) Seconds."          
  done
  }


#1

update_jbb_config(){

	usage="USAGE: ${FUNCNAME[0]} < -c | --controller, -ti | --injector, -be | --backend > <config-name>"

	[ $# -ne 2 ] && echo "Invalid args. $usage" && return 1
	
	config_file=$2
	[ ! -f $config_file ] && echo "File [ $config_file ] Not Found." && return 1
	
	case "$1" in
		-c | --controller )
			sed -i "s/Ctr_1.cmdline=.*/Ctr_1.cmdline= $(app_get_sut_info java-opts-c)/g;" $config_file
			;;

		-ti | --injector | -be | --backend )
			
			# Update heap values for BE and TxI in config file

			sed -i "s/Backend_1.cmdline=.*/Backend_1.cmdline= $(app_get_sut_info java-opts-be)/g;s/TxInjector_1.cmdline=.*/TxInjector_1.cmdline= $(app_get_sut_info java-opts-ti)/g" $config_file
			;;

		*)
			echo "$usage"
			;;
	esac
}

run_jbb_multi_jvm(){

	wrk_dir="$(app_get_sut_info jbb-home)"

	app_log_stderr "RUNNING JBB FROM: $wrk_dir"
	
	cd $wrk_dir
	
	jbb_config=${PWD}/config/template-M.raw

	[ ! -f $jbb_config ] && echo "[ $(app_get_fname) ] File '$jbb_config' Not Found." && return 1

	# SET #Numa, #Groups, #TxInjectors, Heap Memory Settings VALUES FROM ARGUMENTS of type Key=Value
	JBB_ARGS="$(echo "$@" | xargs -n1)"
	
	NUMA_COUNT=$(echo "$JBB_ARGS" | grep "numa-count" | awk -F'=' '{print $2}' )
	GROUP_COUNT=$(echo "$JBB_ARGS" | grep "group-count" | awk -F'=' '{print $2}' )
	TI_COUNT=$(echo "$JBB_ARGS" | grep "txi-count" | awk -F'=' '{print $2}' )
	
	TI_MEM=$(echo "$JBB_ARGS" | grep "txi-mem" | awk -F'=' '{print $2}' )
	C_MEM=$(echo "$JBB_ARGS" | grep "c-mem" | awk -F'=' '{print $2}' )
	BE_MEM=$(echo "$JBB_ARGS" | grep "be-mem" | awk -F'=' '{print $2}' )
	ENABLE_SHARE=$(echo "$JBB_ARGS" | grep "enable-mem-share" | awk -F'=' '{print $2}' )
	
	TEST_OPTS=$(echo -e "$JBB_ARGS" | grep "test-opts" | awk -F= '{print $2}')

	#numa_cnt=$(app_get_sut_info numa-count)
	NUMA_COUNT=${NUMA_COUNT:-1}

	GROUP_COUNT=${NUMA_COUNT} 
	TI_JVM_COUNT=${TI_COUNT:-2}

	echo -e "# Groups = $GROUP_COUNT \n# TxInjectors Per Group =  ${TI_JVM_COUNT}"

	# ------------ CONFIG CHANGES ---------------------
	
	# Call 'fill-in-sut-data.sh' to fill information in config file.
	poc_list=${MAIN_HOME:-.}/poc-servers.txt

	#[ ! -f $poc_list ] && echo "[ Error ] POC Servers List Not Found! " && exit 1

	product_name="$(sudo dmidecode -s system-product-name)" 

	matched_line="$(cat $poc_list | grep "$product_name" || echo "VendorNA VendorUrlNA")" #; [ $? -ne 0 ] && echo No-Match-Found)"
	VENDOR_NAME=$(echo $matched_line | awk '{print $1}')
	VENDOR_URL=$(echo $matched_line | awk '{print $2}')

	# ---- UPDATE SUT INFO in JBB Config File
	pushd ${MAIN_HOME}
	
	ORG=ORG_NA

	./fill-in-sut-data.sh --tested-by $ORG --tested-by-name Rakesh.Madivi --vendor ${VENDOR_NAME:-VendorNA} --vendor-url ${VENDOR_URL:-VendorUrlNA} --test-sponsor $ORG --jbb-config y
	
	if [ -d $jbbdir ]
	then
		cp sample.raw ${jbbdir}/config/template-M.raw
	else
		echo [ Failed to Copy Config File ] sample.raw not copied to: ${jbbdir:-jbbdir-Not-Set}
		exit 1
	fi
		
	popd

	# ---- END OF UPDATE SUT INFO in JBB Config File

	test_date=$(date +"%b %d, %Y")
	sed -i "s/test\.date=.*/test.date=$test_date/g" $jbb_config
	for k in "jbb2015.test.aggregate.SUT.totalNodes=" "jbb2015.test.aggregate.SUT.nodesPerSystem=" "jbb2015.product.SUT.hw.system.hw_1.nodesPerSystem="
	do
		sed -i "s/^$k.*/${k}${NUMA_COUNT}/g" $jbb_config
	done

	# SPEC OPTS
	app_add_sut_key "spec-opts-c" "-Dspecjbb.group.count=$GROUP_COUNT -Dspecjbb.txi.pergroup.count=$TI_JVM_COUNT"
	app_add_sut_key "spec-opts-ti" ""
	app_add_sut_key "spec-opts-be" ""

	JAVA_TUNE="-XX:+UseParallelGC -XX:ParallelGCThreads=2 -XX:CICompilerCount=4"

	if [ $ENABLE_SHARE -eq 1 ]
	then

		TI_OPT="-Xms${TI_MEM:-2}g -Xmx${TI_MEM:-2}g ${JAVA_TUNE}"
		
		C_MEM=$((PER_NON_TI_MEM + EXTRA_CNTR))

		C_OPT="-Xms${C_MEM:-2}g -Xmx${C_MEM:-2}g ${JAVA_TUNE}"

		BE_OPT="-Xms${BE_MEM:-24}g -Xmx${BE_MEM:-24}g -Xmn${BE_MEM:-20}g ${JAVA_TUNE}"
      	fi

	# TUNES

	C_TUNES="-Xms2g -Xmx2g -Xmn1536m -XX:+UseParallelGC -XX:ParallelGCThreads=2 -XX:CICompilerCount=4"

	TI_TUNES="-Xms2g -Xmx2g -Xmn1536m -XX:+UseParallelGC -XX:ParallelGCThreads=2 -XX:CICompilerCount=4"

	BE_TUNES1="-XX:AllocatePrefetchInstr=2 -XX:+UseParallelGC -XX:ParallelGCThreads=16 -XX:LargePageSizeInBytes=2m -XX:-UseAdaptiveSizePolicy -XX:+AlwaysPreTouch -XX:+UseLargePages -XX:SurvivorRatio=28 -XX:TargetSurvivorRatio=95 -XX:MaxTenuringThreshold=15 -XX:InlineSmallCode=11k -XX:MaxGCPauseMillis=300 -XX:LoopUnrollLimit=200 -XX:AdaptiveSizeMajorGCDecayTimeScale=12 -XX:AdaptiveSizeDecrementScaleFactor=2 -XX:+UseTransparentHugePages -XX:+UseUnalignedLoadStores -XX:-UseFastStosb -XX:+UseXMMForArrayCopy -XX:+UseXMMForObjInit -XX:+UseFPUForSpilling -XX:TLABAllocationWeight=55 -XX:ThreadStackSize=512"

	BE_TUNES2="-Xms120g -Xmx120g -Xmn117g -server -XX:MetaspaceSize=256m -XX:AllocatePrefetchInstr=2 -XX:LargePageSizeInBytes=2m -XX:-UsePerfData -XX:-UseAdaptiveSizePolicy -XX:+AlwaysPreTouch -XX:+UseLargePages -XX:+UseParallelGC -XX:SurvivorRatio=65 -XX:TargetSurvivorRatio=80 -XX:ParallelGCThreads=32 -XX:MaxTenuringThreshold=15 -XX:InitialCodeCacheSize=25m -XX:InlineSmallCode=10k -XX:MaxGCPauseMillis=200 -XX:+UseCompressedOops -XX:ObjectAlignmentInBytes=32 -XX:+UseTransparentHugePages -XX:+UseUnalignedLoadStores -XX:-UseFastStosb -XX:+UseXMMForArrayCopy -XX:+UseXMMForObjInit -XX:+UseFPUForSpilling -XX:CompileThresholdScaling=15"

	# ---- SET JAVA OPTS for Controller, TxInjectors, Backends
	#TEST_OPTS=3 # $(echo -e "$JBB_ARGS" | grep test-opts | awk -F= '{print $2}')
	
	if [ $TEST_OPTS -eq 0 ]
	then
		JAVA_OPTS_C="${C_OPT:-}"
		JAVA_OPTS_TI="${TI_OPT:-}"
		JAVA_OPTS_BE="${BE_OPT:-}"

	elif [ $TEST_OPTS -eq 1 ]
	then
		JAVA_OPTS_C="${C_OPT:-} ${JAVA_TUNE}"
		JAVA_OPTS_TI="${TI_OPT:-} ${JAVA_TUNE}"
		JAVA_OPTS_BE="${BE_OPT:-} ${JAVA_TUNE}"

	elif [ $TEST_OPTS -eq 2 ]
	then
		JAVA_OPTS_C="${C_OPT:-} ${C_TUNES}"
		JAVA_OPTS_TI="${TI_OPT:-} ${TI_TUNES}"
		JAVA_OPTS_BE="${BE_OPT:-} ${BE_TUNES1}"

	elif [ $TEST_OPTS -eq 3 ]
	then
		JAVA_OPTS_C="${C_OPT:-} ${C_TUNES}"
		JAVA_OPTS_TI="${TI_OPT:-} ${TI_TUNES}"
		JAVA_OPTS_BE="${BE_OPT:-} ${BE_TUNES2}"
	fi

	JAVA_OPTS_PRINT=$(
	app_print_title "JAVA OPTIONS SET ARE:"
	app_disp_msg "TxI: ${JAVA_OPTS_TI}"
	app_disp_msg "Controller: ${JAVA_OPTS_C}"
	echo "BE : ${JAVA_OPTS_BE}"
	) 

	echo -e "$JAVA_OPTS_PRINT"

	default_ctrl_opts="-ms256m -mx1024m"
	default_txi_opts="-Xms2g -Xmx2g"
	default_be_opts="Xms24g -Xmx24g -Xmn20g"

	app_add_sut_key "java-opts-c" "${JAVA_OPTS_C:--ms256m -mx1024m}"
	app_add_sut_key "java-opts-ti" "${JAVA_OPTS_TI:--Xms2g -Xmx2g}"
	app_add_sut_key "java-opts-be" "${JAVA_OPTS_BE:--Xms24g -Xmx24g -Xmn20g}"

	app_add_sut_key "mode-args-c" ""
	app_add_sut_key "mode-args-ti" ""
	app_add_sut_key "mode-args-be" ""

	update_jbb_config -c $jbb_config
	update_jbb_config -be $jbb_config
	# ------------ CONFIG CHANGES DONE --------------------- 	
	
	JAVA=java
	which $JAVA > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "ERROR: Could not find a 'java' executable. Please set the JAVA environment variable or update the PATH."
		exit 1
	fi

	timestamp=$(date '+%y-%m-%d_%H%M%S')
	result=./$timestamp
	mkdir $result

	# Copy current config to the result directory
	cp -r config $result

	pushd $result

	app_print_title "RUNNING: SPEC JBB BENCHMARK [ Groups: $GROUP_COUNT, TxI per group: $TI_JVM_COUNT ]"

	echo "Launching SPECjbb2015 in MultiJVM mode..."
	echo
	
	echo "Start Controller JVM"
	
	numactl --interleave=all $JAVA $(app_get_sut_info java-opts-c) $(app_get_sut_info spec-opts-c) -jar ../specjbb2015.jar -m MULTICONTROLLER $(app_get_sut_info mode-args-c) 2>controller.log > controller.out &
	
	CTRL_PID=$!
	
	echo "Controller PID = $CTRL_PID"

	sleep 3

	CPUS_PER_GRP=$(( $(nproc) / GROUP_COUNT))

	for ((gnum=1; $gnum<=$GROUP_COUNT; gnum=$gnum+1))
	do

		GROUPID=Group$gnum
		echo -e "\nStarting JVMs from $GROUPID:"

		# -----------------------------
		SELECTED_NUMA=$(( (gnum-1) % NUMA_COUNT ))

		CPULIST=$(app_get_sut_info numa-${SELECTED_NUMA} )
		
		CPULIST_ARRAY=( $(echo $CPULIST | tr ',' ' ') )

		node_thr_count=${#CPULIST_ARRAY[@]}
		
		per_txi_th_count=$(( node_thr_count / TI_JVM_COUNT ))

		mapfile -t SPLIT_LIST <<< "$( for i in $( seq 0 $per_txi_th_count ${node_thr_count} );do echo "${CPULIST_ARRAY[@]:${i}:$per_txi_th_count}" | tr ' ' ','; done )"
		
		printf "%s\n" ${SPLIT_LIST[@]} | sed 's/^/[ PER-TXI-JVM-CPULIST ] /g'

		echo "GROUP-$gnum / NUMA-$SELECTED_NUMA ($CPULIST)"
		# -------------------------------------------------

		for ((jnum=1; $jnum<=$TI_JVM_COUNT; jnum=$jnum+1)); do

			JVMID=txiJVM$jnum
			TI_NAME=$GROUPID.TxInjector.$JVMID
			
			echo "    Start $TI_NAME"
			
			numactl -C ${SPLIT_LIST[$((jnum-1))]} -l $JAVA $(app_get_sut_info java-opts-ti) $(app_get_sut_info spec-opts-ti) -jar ../specjbb2015.jar -m TXINJECTOR -G=$GROUPID -J=$JVMID $(app_get_sut_info mode-args-ti) > $TI_NAME.log 2>&1 &

			echo -e "\t$TI_NAME PID = $!"

			sleep 1
		done

		JVMID=beJVM
		BE_NAME=$GROUPID.Backend.$JVMID

		echo "    Start $BE_NAME"
		
		numactl -C $CPULIST -l $JAVA $(app_get_sut_info java-opts-be) $(app_get_sut_info spec-opts-be) -jar ../specjbb2015.jar -m BACKEND -G=$GROUPID -J=$JVMID $(app_get_sut_info mode-args-be) > $BE_NAME.log 2>&1 &

		echo -e "\t$BE_NAME PID = $!"

		sleep 1
	done
	
	echo
	echo "SPECjbb2015 is running..."
	echo "Please monitor $result/controller.out for progress"

	# Save SUT INFO
	echo "[ Saving SUT info ]..."
	sut_f=SUT-info.txt
	save_sut_info | tee $sut_f
	echo -e "$JAVA_OPTS_PRINT" | tee -a $sut_f

	wait $CTRL_PID
	echo
	sleep 5
	echo "Controller has stopped"

	echo "SPECjbb2015 has finished"
	echo

	grep -R INVALID $result/* > /dev/null 2>&1 && echo "[ INVALID RUN ] RUN $result Marked as invalid!. Please check controller logs and output." 

	popd

	echo "STOP" | tee $(app_get_sut_info collect-statf)

	# Using JBB REPORTER after updating HW/SW details in the .raw file to re-generate HTML .
	# Refer section 11 : https://www.spec.org/jbb2015/docs/userguide.pdf

	echo "
	11.1.HW/SW details input file with user defined name
	If user wants to declare a file for HW and SW details, the following command can be used:
	
	java -Xms2g -Xmx2g -jar specjbb2015.jar -m reporter -raw <hw/sw details file.raw> -s <binary_log_file>
	
	11.2.To produce higher level HTML reports
	To produce various levels of report, following command can be used:
	
	java -Xms2g -Xmx2g -jar specjbb2015.jar -m reporter –raw <file> -s <binary_log_file> -l <report_level>
	
	Where report 0 <= level <= 3 (0 - minimum report, 3 - most detailed report).
	
	11.3. Regenerate submission raw file and HTML report
	The file SPECjbb2015-<run_mode_mark>-<timestamp>.raw inside the result directory is the raw submission file
	containing the actual test measurement and result. Once this file is generated and user needs to edit HW/SW details,
	user can re-generate this submission file with updated HW/SW configuration using following two methods.
	
	11.3.1. Using edited original template file and binary log
	In this case user needs both binary log and edited HW/SW details template file and can re-generate submission file
	and HTML report using following command:
	
	java –Xms2g –Xmx2g -jar specjbb2015.jar -m reporter -s <binary_log_file> -raw <raw_template_file>
	
	11.3.2. Edit submission raw file and re-generate HTML ‘level 0’ report without binary log
	User can directly edit submission raw file SPECjbb2015-<run_mode_mark>-<timestamp>.raw, modify the HW/SW
	details and re-generate HTML report with updated HW/SW configuration using the following command:
	
	java –Xms2g –Xmx2g -jar specjbb2015.jar -m reporter -raw <raw_submission_file>
	"
}

app_add_fname "specjbb_tests"
function specjbb_tests()
{
	specjbb_home=$HOME/specjbb15

	jbb_home_default=$HOME/disk-mnt/jbb15

	jbb_home=${jbb_home_cmdline:-${jbb_home_default}}

	if [ ! -d $jbb_home ]
	then
		echo "JBB HOME Directory [ $jbb_home ] not found. Please provide specJBB home directory."
		return 1
	else
		max_divisor_quotient="$(app_max_mem_divisor)"
		
		[ "${max_divisor_quotient}" == "-1:0" ] && echo "Insufficient Memory!" && exit 1

		SYSTEM_MEM=$(app_get_system_memory)

		echo "[ System Memory = ${SYSTEM_MEM} ] Max Memory Divisor = $max_divisor_quotient"

		RUN_FOR=0
		
		test_mem=(100 500 1000)

		test_txi=(1 2)
		
		ENABLE_MEM_SHARE=0

		for mem in ${test_mem[@]} 
		do
			[ $RUN_FOR -ge ${#test_txi[@]} ] && [ $ENABLE_MEM_SHARE -eq 0 ] && continue

			if [ $ENABLE_MEM_SHARE -eq 1 ]
			then	
				JBB_TEST_MEM=$mem 

				echo "[ Memory = $mem ] TESTING MEMORY: ${JBB_TEST_MEM} GB"
			else
				JBB_TEST_MEM=$SYSTEM_MEM 	#$(free -g | head -2 | awk '{print $2}' | tail -1) # 

				HEAP_CONF="${JBB_TEST_MEM}_DefaultHeapConf"
			fi

			for txi_c in ${test_txi[@]}
			do
				app_disp_msg "[ Running ] Memory = $mem TxInjectors = $txi_c"

				pushd $jbb_home
				app_add_sut_key "jbb-home" "$jbb_home"
			
				bmc_ip="$(app_get_sut_info bmc-ip)"
				BMC_IP="${bmc_ip:-localhost}"

				#numa_count=$(app_get_sut_info numa-count)
				numa_count=$(lscpu | grep "NUMA node(" | awk '{print $NF}') 

				NUMA_COUNT=${numa_count:-1}
				
				GROUP_COUNT=${NUMA_COUNT:-1}
				
				TI_COUNT=${txi_c}
				
				echo -e "# Groups = $GROUP_COUNT \n# TxInjectors Per Group =  ${TI_COUNT}"

				# SPEC OPTS
				app_add_sut_key "spec-opts-c" "-Dspecjbb.group.count=$GROUP_COUNT -Dspecjbb.txi.pergroup.count=$TI_COUNT"
				app_add_sut_key "spec-opts-ti" ""
				app_add_sut_key "spec-opts-be" ""

				collect_statf="${PWD}/status.${BMC_IP:-localhost}-${GROUP_COUNT:-1}G-${TI_COUNT}TxI"
				app_add_sut_key "collect-statf" "${collect_statf}"
				
				TOOL=all_metrics

				VENDOR_MODEL="$(app_get_sut_info vendor-model cpu | xargs | tr -s '[:space:]' '-')"

				MEMORY_CONF="$(app_get_sut_info memory | xargs | tr '[, ]' '_' )"

				GOVERNOR="$(app_get_sut_info governor)"

				# Set Heap Memory For Each JVM Type

				if [ $ENABLE_MEM_SHARE -eq 1 ]
				then
					[ -z "${JBB_TEST_MEM:-}" ] && echo "JBB TEST MEM is not set.!" && exit 1

					# % of Total Test memory to be used by TxI			
					TI_SHARE="40" 

					TOTAL_TI_COUNT=$((GROUP_COUNT * TI_COUNT))

					TI_MEM=$(awk -v m=${JBB_TEST_MEM} -v share=${TI_SHARE} -v txi=${TOTAL_TI_COUNT} 'BEGIN{ printf "%.0f",( m*(share/100) )/txi }' )	

					[ $TI_MEM -eq 0 ] && TI_MEM=1
					
					EXTRA_CNTR=5

					PER_NON_TI_MEM=$(awk -v m=${JBB_TEST_MEM} -v ti_m=${TI_MEM} -v txi_cnt=${TOTAL_TI_COUNT} -v g=${GROUP_COUNT} -v extra_cntr=${EXTRA_CNTR} 'BEGIN{ printf "%.0f",( ( m-(ti_m*txi_cnt)-extra_cntr )/(g+1) )}') 

					# Max BE Memory
					BE_MEM=$PER_NON_TI_MEM

					[ $BE_MEM -le 0 ] && BE_MEM=$((4*TI_MEM))

					# Max Controller Memory
					C_MEM=$((PER_NON_TI_MEM + EXTRA_CNTR))

					HEAP_CONF="TOT_TI_BE_C_${JBB_TEST_MEM}${SYSTEM_MEM//[0-9]/}_${TI_MEM}_${BE_MEM}_${C_MEM}"

#					JAVA_TUNE="-XX:+UseParallelGC"
#
#					TI_OPT="-Xms${TI_MEM:-2}g -Xmx${TI_MEM:-2}g ${JAVA_TUNE}"
#					
#					C_OPT="-Xms${C_MEM:-2}g -Xmx${C_MEM:-2}g ${JAVA_TUNE}"
#
#					BE_OPT="-Xms${BE_MEM:-24}g -Xmx${BE_MEM:-24}g -Xmn${BE_MEM:-20}g ${JAVA_TUNE}"
				fi
				
				# TEST_OPTS = 0 (No Options),1 (JAVA_TUNE), 2 (C_TUNES, TI_TUNES, BE_TUNES1), 3 (C_TUNES, TI_TUNES, BE_TUNES2)
				test_opts=1

				TEST_CONF=${TOOL:-ToolNA}-${GROUP_COUNT:-GroupCountNA}G-${TI_COUNT:-TxiNA}TxI-${VENDOR_MODEL:-VendorNA}-NUMA_${NUMA_COUNT}-${MEMORY_CONF:-MemoryNA}-${GOVERNOR:-GovernorNA}-${HEAP_CONF}-TUNE${test_opts} 

				echo "[ Test Configuration ] ${TEST_CONF}"

				METRICS_FILE=${PWD}/${TEST_CONF}.txt

				jbb_runlog=${PWD}/jbb-run.log
				
				# START METRICS COLLECTION
				
				start_power_collection --bmc $BMC_IP --tool $TOOL --jbb-run-log $jbb_runlog --collect-status-file $collect_statf --output $METRICS_FILE &
				
				collection_pid=$!

				echo "[ Collection PID ] $collection_pid"       

				# START RUN
				#run_jbb_multi_jvm | tee $jbb_runlog

				run_jbb_multi_jvm "numa-count=${NUMA_COUNT} group-count=${GROUP_COUNT} txi-count=${TI_COUNT} txi-mem=${TI_MEM:-} c-mem=${C_MEM:-} be-mem=${BE_MEM:-} enable-mem-share=${ENABLE_MEM_SHARE:-0} test-opts=$test_opts" | tee $jbb_runlog

				cd $jbb_home && echo STOP | tee $collect_statf

				app_ENV_RES_DIR=$(grep "Please monitor" $jbb_runlog >/dev/null; echo $?)

				if [  $app_ENV_RES_DIR -eq 0 ]
				then
					# Generate Multi Plot
					# PLOT GRAPH
					# -----------
					
					JBB_RESULT_DIR=$(grep "Please monitor" $jbb_runlog | awk '{print $3}' | xargs dirname | xargs basename)

					RENAME_RES_DIR=${JBB_RESULT_DIR}-${TEST_CONF}
					PLOT_OUTPUT=${RENAME_RES_DIR}
					
					multi_plot -j ${PWD}/${JBB_RESULT_DIR} -i $METRICS_FILE -o $PLOT_OUTPUT -n ${RENAME_RES_DIR}
				else
					echo "[ $(app_get_fname) ] No Result Directory Name Found in '$jbb_runlog' file"
				fi
			done

			RUN_FOR=$((RUN_FOR + ${#test_txi[@]}))
		done # For Max Memory Divisor
	fi

	# Endof Execution
	return 0
}

#2
app_add_fname "stream_tests"
function stream_tests()
{
  echo -e "START stream test?(y/n)"
  read op
  
  if [ "$op" = "n" ];then
    echo -e "STREAM TEST Cancelled by user...\n"
  else
	  [ -z "$(which gnuplot)" ] && echo "[E] GNU Plot executable is not found!" && return 1
	  
	  stream_exe=numa-aware-stream-scaling

	  stream_dir=stream-modified
	  
	  [ -f $stream_exe ] && [ ! -L $stream_dir/$stream_exe ] && echo "Creating soft link [ PWD: $PWD ]: $stream_dir/$stream_exe" && ln -s ${PWD}/$stream_exe $stream_dir/$stream_exe
	  
	  app_disp_msg "STARTING: STREAM TEST ( $stream_dir )"

	  if [ $stream_dir == "stream-scaling" ]
	  then
		  if [ ! -d "$stream_dir" ];then
			  echo -e "\nStream-scaling Folder not found in current working path.\nDownloading stream-scaling....\n"
			  git clone --recursive https://github.com/jainmjo/stream-scaling.git
		  fi
		  
		  cd $stream_dir
		  
		  outfile=stream_scaling_benchmark.txt
		  
		  iters=2 # 4
		  
		  testname=stream_scale_${iters}iters
		  
		  ./multi-stream-scaling $iters  $testname
		  
		  ./multi-averager $testname > stream.txt
		  
		  echo -e "Plotting Triad..."
		  
		  gnuplot stream-plot
		  
		  echo -e "\nNOTE: If you want to plot for 'Scale', please edit find parameter to 'Scale' in stream-graph.py and re-run 'multi-averager'\n"
	  else
		  [ ! -d $stream_dir ] && echo "[Err] STREAM Test Directory ($stream_dir) Not Found!" && return 1

		  cd $stream_dir
		  
		  stream_exe=numa-aware-stream-scaling
		  
		  [ ! -x $stream_exe ] && echo "[Err] Executable ( $stream_exe ) Not Found!" && return 1

		  # START TEST
		  echo  PWD: $PWD
		  ./$stream_exe
	  fi
  fi
}

#3
# start-tests.sh

#4
#iperf_tests

#5
# This function only works for sysbench version: 1.0

get_sb_test_fields(){
	set -x
	result_file=$1
	[ ! -f $result_file ] && echo "File [ $result_file ] Not Found." && return 1

	sb_keys=()
	# Set Required fields to parse
	sb_keys+=("Number of threads:")
	sb_keys+=("events per second:")
	sb_keys+=("total number of events:")
	sb_keys+=("min:")
	sb_keys+=("avg:")
	sb_keys+=("max:")
	sb_keys+=("${PERCENTILE}th percentile:")
	sb_keys+=("sum:")
	sb_keys+=("events (avg/stddev):")
	sb_keys+=("execution time (avg/stddev):")

	# Process output for exportable fields
	sb_header="$(for i in ${!sb_keys[@]};do echo "${sb_keys[$i]}";done | paste -d, -s| xargs)"

	values="$(
	for i in ${!sb_keys[@]}
	do
		cat $result_file | grep "${sb_keys[$i]}" | awk -F: '{print $NF}' 
	done | xargs | xargs -n1 | paste -d, -s
	)"

	echo "HEADER: ${sb_header}"
	echo "VALUES: ${values}"
	set +x
}

app_add_fname "sysbench_tests"
function sysbench_tests()
{
	this=$(app_get_fname $BASH_SOURCE)
	read -p "[ sysbench ] Do you want to run SYSBNECH-1.0 test (y/n)? " op

	if [ "$op" = "n" ]
	then
		echo -e "SYSBENCH TEST Cancelled by user...\n"
	else
		TH_PER_CORE=$(lscpu | grep "Thread" | awk '{print $NF}')
		
		# Create a result directory

		RESULT_DIR=sysbench-results
		mkdir -p $RESULT_DIR
		pushd $RESULT_DIR

		echo Select test to benchmark:
		
		sb_tests=(CPU MEMORY MYSQL-DBTest)

		sb_keys=()
		sb_values=()
		
		PERCENTILE=99

		select op in ${sb_tests[@]} 
		do
			echo SELECTED: $op #VALUE: $REPLY

			case $op in 
				"CPU" )
					unset sb_keys sb_values

					# SYSBENCH CPU TEST

					app_disp_msg "[ ${op} ] Running SYSBENCH-CPU Benchmark..."
					
					init=10000 # Default value for sysbench

					expf=sysbench-cpu-export.txt
					sb_header_written=0

					st=$SECONDS
					for((mx=$init; mx<=$init*10; mx*=2))
					do
						for((th=2; th<=$ncpus; th+=2))
						do
							outf=sysbench-cpu-maxp_${mx}-${th}th.txt
							
							app_disp_msg "Running: CPU Max Prime: $mx Threads: $th"

							sysbench cpu --cpu-max-prime=$mx --threads=$th --percentile=${PERCENTILE} run | tee $outf

							rdata="$(get_sb_test_fields $outf)"
							r_header=$(echo "$rdata" | grep "HEADER:" | cut -f2- -d: | xargs)
							r_values=$(echo "$rdata" | grep "VALUES:" | cut -f2- -d: | xargs)

							[ $sb_header_written -eq 0 ] && echo "Threads,CPU-Max-Prime,$r_header" | tee $expf && sb_header_written=1
							echo "${mx},${r_values}" | tee -a $expf
						done
					done
					en=$SECONDS   
					echo "Elapsed Time: $((en-st))s"

					# NEXT TRY TASKSET TO PIN PROCESSES/THREADS TO PROCESSORS/LOGICAL PROCESSORS
					;;

				"MEMORY" )

					# SYSBENCH MEMORY TEST

					#echo -e "Running MEMORY Workload Benchmark..."
					app_disp_msg "[ ${op} ] Running SYSBENCH-MEMORY Benchmark..."

					init=10000

					# Trying to allocate memory more than L3 Cache and stretch to RAM
					#memload=262144K

					# Use size which stretches to RAM 
					L3=$(lscpu -C | grep L3 | xargs | cut -f3 -d' ')
					
					L3_UNIT=${L3: -1}
					
					MEM_BLK_SIZE=2M #$((2**20))M 

					# Free memory in mB
					FREE_MEM=$(free -m | grep Mem: | xargs | cut -f3 -d' ')
					
					NTIMES=10000 # no.of times the (total memory * threads)
					TEST_MEM_SIZE=${FREE_MEM}G #$((NTIMES * FREE_MEM))G

					out_prefix=sysbench-memory-blk_${MEM_BLK_SIZE}-mem_${TEST_MEM_SIZE}

					expf=sysbench-memory-export.txt
					sb_header_written=0

					st=$SECONDS
					for((th=2; th<=$ncpus; th+=70))
					do
						OUTF=$out_prefix-${th}th.txt

						echo "[ RUNNING ] MEMORY BLOCK SIZE = $MEM_BLK_SIZE, TOTALMEM = $TEST_MEM_SIZE, THREADS = $th" | tee $OUTF

						# --memory-scope=global/local --memory-oper=read/write/none

						sysbench memory --memory-block-size=$MEM_BLK_SIZE --memory-total-size=$TEST_MEM_SIZE --memory-scope=global --memory-oper=read --threads=$th --memory-access-mode=rnd --percentile=${PERCENTILE} --time=5 run | tee $OUTF
							
						rdata="$(get_sb_test_fields $OUTF)"
						r_header=$(echo "$rdata" | grep "HEADER:" | cut -f2- -d: | xargs)
						r_values=$(echo "$rdata" | grep "VALUES:" | cut -f2- -d: | xargs)

						[ $sb_header_written -eq 0 ] && echo "Threads,Blk,Memory,$r_header" | tee $expf && sb_header_written=1
						echo "${MEM_BLK_SIZE},${TEST_MEM_SIZE},${r_values}" | tee -a $expf
					done
					en=$SECONDS
					echo "Elapsed Time: $((en-st))s"

					;;

				"MYSQL-DBTest" )

					# SYSBENCH MYSQL TEST

					app_disp_msg "[ ${op} ] Running SYSBENCH-MySQL Benchmark..."

					# SQL Test Environment Setup
					sql_user=rakesh
					sql_user_pwd=rakesh123

					sql_env_setup="
					select 'CREATING BENCHMARK TEST ENVIRONMENT' as '';
					select '===================================' as '';
					show databases;
					CREATE DATABASE IF NOT EXISTS sbtest;
					CREATE USER IF NOT EXISTS '$sql_user'@'localhost' IDENTIFIED BY '$sql_user_pwd';
					GRANT ALL PRIVILEGES ON * . * TO '$sql_user'@'localhost';

					select 'UPDATED DATABASES:' as '';
					select '==================' as '';
					show databases;

					select 'UPDATED USERS:' as '';
					select '==================' as '';
					select User,Host from mysql.user;
					"

					app_disp_msg "Setting up SQL DB Test Environment"
					
					echo "$sql_env_setup" | sudo mysql

					# START DB TEST
					# -------------
					TABLE_COUNT=10 #0
					RECORD_SET=100 #0000
					TABLE_SIZE=$((RECORD_SET**1))
					PERCENTILE=99

					app_disp_msg "Preparing Database for benchmarking..."

					# Common options fror DB test

					# InnoDB Buffer Size. Use 80% of RAM (in bytes)
					INNODB_BUFFER=$(free -m | grep "Mem:" | awk -v percent=0.8 '{printf "%d\n",$4*percent*1024*1024}')

					# Range: 1048576 to innodb_buffer_pool_size/innodb_buffer_pool_instances
					INNODB_CHUNK=$(($INNODB_BUFFER/1000)) # Performance reasons, buffer_size/buffer_chunk ratio <= 1000

					SYSBENCH_DB_COMMON_OPTS="--db-driver=mysql --mysql-user=$sql_user --mysql-password=$sql_user_pwd --tables=$TABLE_COUNT --table-size=$TABLE_SIZE --threads=$TABLE_COUNT --percentile=${PERCENTILE}"

					# Prepare the DB for Benchmark
					SYSBENCH_TEST=oltp_read_write

					echo -e "Cleaning up previously created tables"
					sysbench ${SYSBENCH_TEST} ${SYSBENCH_DB_COMMON_OPTS} cleanup
					
					echo -e "Creating $TABLE_COUNT tables of $TABLE_SIZE records..."
					sysbench ${SYSBENCH_TEST} ${SYSBENCH_DB_COMMON_OPTS} prepare

					# Insert only
					# sysbench /usr/share/sysbench/oltp_insert.lua 

					# Write only
					# sysbench /usr/share/sysbench/oltp_write_only.lua 

					SYSBENCH_TEST=oltp_read_only # oltp_write_only, oltp_insert 
					
					SYSBENCH_OPTS="$SYSBENCH_TEST ${SYSBENCH_DB_COMMON_OPTS} --time=60" # --report-interval=2

					out_prefix=sysbench-sql-${TABLE_COUNT}x${TABLE_SIZE}


					# -------------- PROCESSOR PINNING
					export pinlist=""
					st=$SECONDS

					if [ $(nproc) -lt 4 ]
					then
						INC=1
					else
						INC=4
					fi

					threads_tested=()
					sb_header_written=0

					for((x=1; x<=$(($(nproc)/INC)); x+=1))
					do
						# Total Threads to use for this test
						TH=$((x * INC))
						
						echo -e "\tTEST: SQL Read only Benchmark (Pinned) THREADS: $TH"
						
						# Get no.of min. Physical cores required to allocate threads
						PHY_CPU=$(( TH / TH_PER_CORE ))

						CPULIST=$(set +x;seq 0 $((PHY_CPU-1)) | xargs -I{} cat /sys/devices/system/cpu/cpu{}/topology/thread_siblings_list | paste -d, -s; set +x)
						# Add extra physical core if threads are remaining after allocating TH_PER_CORE
						[ $((TH % TH_PER_CORE)) -gt 0 ] && CPULIST+=",$(cat /sys/devices/system/cpu/cpu${PHY_CPU}/topology/thread_siblings_list)"
						
						echo "[ Testing $TH-Threads ] on ( $CPULIST )"
						sleep 2
						
						OUTF=${out_prefix}-${TH}th-pinned.txt
						
						[ -f $OUTF ] && rm $OUTF

						numactl -C $CPULIST --localalloc sysbench $SYSBENCH_OPTS --threads=$TH run | tee $OUTF

						TEST_NO_PINNING=false

						if [ $TEST_NO_PINNING == true ]
						then
							# Test with No Pinning
							# --------------------
							# Output filename.
							
							OUTF=${out_prefix}-${TH}th.txt
							sysbench $SYSBENCH_OPTS --threads=$TH run | tee $OUTF
    						fi
						[ -f $OUTF ] && threads_tested+=($TH)

						# Process Result to get required fields
						ignore_rows="Running|SQL|queries performed|General|Latency|Threads fairness"
						
						export_content="$(cat $OUTF | grep ":" | egrep -v "$ignore_rows" | tr -s '[:space:]' | awk -F: '{if ($2 ~ /per sec./){nfname=$1"-Per-Sec:"; tmp=$2; replace="\n"gsub(".*[(]","",tmp)gsub("per sec.)","",tmp); gsub("[(].*","",$2); print $1": "$2"\n"nfname,tmp}else{print $0}}' | sed 's/^ +*//g')"

						sb_header="$(echo "${export_content}" | awk -F: '{print $1}' | paste -d, -s | xargs)"

						expf=sysbench-db-export.txt
						# Write Header
						[ $sb_header_written -eq 0 ] && echo "$sb_header" | tee $expf && sb_header_written=1

						# Write content
						echo "$export_content" | awk -F: '{print $2}' | paste -d, -s | xargs | tr -d ' ' | tee -a $expf

					done
					en=$SECONDS
					echo Elapsed Time: $((en-st)) | tee $OUTF

					echo "[ Threads Tested ] ${threads_tested[@]}"

					# END OF BENCHMARK
					;;

				"*" ) echo -e "\nNO TEST SELECTED FOR SYSBENCH.\n"
					;;
				esac

				break
			done # end of Select 
		popd
	fi
}

#6
# REDIS TEST
app_add_fname "redis_tests"
function redis_tests()
{
  echo -e "Do you want to run redis test?(y/n)"
  read op
  
  if [ "$op" = "y" ];then
    which redis-benchmark > /dev/null 2>&1
    if [ "$?" != "0" ];then
      echo -e "\nError: redis-benchmark is not installed. Please install and re-run.\n"
    else
      outfile=redis_benchmark.txt
      outfile2=redis_benchmark_nopinning.txt
      rm -rf $outfile
	  model=$(lscpu | grep Model)
      echo -e "$model" >> $outfile
      echo -e "$model" >> $outfile2
      
      redis_pid=`pidof redis-server`
      #redis_cpu=`ps -o psr ${redis_pid}|tail -n1`
      #other_cpus="`echo $(numactl --hardware | grep cpus | grep -v "${redis_cpu}" | cut -f4- -d' ')|sed -r 's/[ ]/,/g'`"
	  redis_cpu=$(taskset -c -p ${redis_pid} | cut -f2 -d ':' | tr "," " ")
      all_cpus="$(echo $(numactl --hardware | grep cpus | cut -f2 -d':'))"
      other_cpus=$all_cpus
      for i in $redis_cpu
      do
              other_cpus=$(echo $other_cpus | sed "s/ ${i} / /g")
      done
      echo -e "Redis server running on: ${redis_cpu} and redis-benchmark will run on: ${other_cpus}\n"
      sleep 2
      totreq=10000000
      reqstep=$((totreq/4))
      
      cpustep=$((ncpus/4))
      
      for((req=$reqstep; req<=$totreq; req+=$reqstep))
      do
        for((par_c=$cpustep; par_c<=$ncpus; par_c+=$cpustep))
        do
          echo -e "\nRunning: ==== ${par_c}C_${req}N for get,set operations with pinning ===="
          echo -e "\n==== ${par_c}C_${req}N ====" >> $outfile

          st=$SECONDS
          taskset -c ${other_cpus} redis-benchmark -n $req -c $par_c -t get,set -q >> $outfile
          en=$SECONDS
          echo -e "Elapsed Time: $((en-st)) Seconds." >> $outfile
          
          # NO PINNING 
          echo -e "\nRunning: ==== ${par_c}C_${req}N for get,set operations ===="
          echo -e "\n==== ${par_c}C_${req}N ====" >> $outfile2

          st=$SECONDS
          redis-benchmark -n $req -c $par_c -t get,set -q >> $outfile2
          en=$SECONDS
          echo -e "Elapsed Time: $((en-st)) Seconds." >> $outfile2
          
        done
      done
     fi
   else
    echo -e "REDIS TEST Cancelled by user...\n"
   fi
}

#7
# Nginx test
app_add_fname "nginx_tests"
function nginx_tests()
{
  echo -e "Do you want to run NGINX test?(y/n)"
  read op
  
  if [ "$op" = "y" ];then
    # REFERENCE: https://github.com/wg/wrk
    # EX: wrk -t12 -c400 -d30s http://127.0.0.1:8080/index.html
    # Runs a benchmark for 30 seconds, using 12 threads, and keeping 400 HTTP connections open.

    # CHECK IF NGINX IS RUNNING ON PORT 80; IF NOT SET FOLLOWING PORT TO RESPECTIVE PORT NUMBER
    nginx_port=80

    echo -e "\nRunning nginx Benchmark...\n"
    outfile=nginx_benchmark.txt
    st=$SECONDS
    for((con=0;con<=10000000;con+=1000000))
    do
      for((th=0;th<=$ncpus;th+=10))
      do
        echo -e "\nRunning CON: $con TH: $th Configuration\n"
        echo -e "\n==== CON: $con TH: $th ====\n" >> $outfile
        #wrk -t$th -c$con -d30s http://localhost:${nginx_port}/index.nginx-debian.html >> $outfile
        ab -c $th -n $con -t 60 -g ${con}n_${th}c_ab_benchmark_gnuplot -e ${con}_${th}_ab_benchmark.csv http://127.0.0.1:${nginx_port}/index.nginx-debian.html >> $outfile
      done   
    done
    en=$SECONDS

    echo -e "ELAPSED TIME: $((en-st))" >> $outfile
  else
    echo -e "NGINX TEST Cancelled by user...\n"
  fi
}

# ycsb
app_add_fname "ycsb_tests"
ycsb_tests(){

	this="$(app_get_fname $BASH_SOURCE)"
	ycsb_version=YCSB #go-ycsb # YCSB
	ycsb_default_home=$HOME/ycsb-0.17.0 



	if [ "$ycsb_version" == "go-ycsb" ]
	then
		go_ycsb_home=${YCSB_HOME:-${ycsb_default_home}} 
		
		[ ! -d $go_ycsb_home ] && echo "[ $this ] Directory [ $go_ycsb_home ] Not found." && return 1

		res_dir=${PWD}/ycsb-results

		mkdir -p $res_dir

		pushd $go_ycsb_home

		test_db=mysql
		mysql_opts="-p mysql.user=rakesh -p mysql.password=rakesh123"

		ycsb_exe=./bin/go-ycsb

		for w in workloada 
		do
			ycsb_header_written=0

			app_disp_msg "[ $this ] Running Go-YCSB version"
			$ycsb_exe load $test_db $mysql_opts -P workloads/$w 

			for ((th=1; th<$(nproc); th+=2))
			do
				echo "[ Threads: $th ]"
				
				outf=$res_dir/go-ycsb-$w-${th}th.txt

				$ycsb_exe run $test_db $mysql_opts -P workloads/$w | tee $outf

				# format exportable data from results
				expf=$res_dir/go-ycsb-$w-export.txt

				res_lines="$(cat $outf | awk '/Run finished,/,0' | tail -n+2 )"

				res_l_cnt=$(echo "$res_lines" | wc -l)

				for ((l=1; l<=$res_l_cnt; l++))
				do
					fields="$(echo "$res_lines" | sed -n "${l}p" | tr ',' '\n')"
					
					keys="$(echo "$fields" | awk -F: '{print $1}' | paste -d, -s | xargs)"

					op="$(echo "$keys" | awk -F'-' '{print $1}')"
					
					headers="$(echo "$keys" | awk -F'-' '{print $2}' | paste -d, -s | xargs)"
					
					vals="$(echo "$fields" | awk -F: '{print $2}' | paste -d, -s | xargs)"

					# Write formatted Results
					[ $ycsb_header_written -eq 0 ] && echo "OPERATION,${headers}" | tee $expf && ycsb_header_written=1
					
					echo "$op,${vals}" | tee -a $expf
				done
			
			done
		done
		popd
	else
		ycsb_home=${YCSB_HOME:-${ycsb_default_home}}

		if [ ! -d $ycsb_home ]
		then
			#echo "[ $(app_get_fname) ] Directory '$ycsb_home' not found."
			app_log_stdout "Directory '$ycsb_home' not found."
			return 1
		else
			# Result directory
			ycsb_res_dir=${PWD}/ycsb-results
			
			mkdir -p $ycsb_res_dir

			pushd $ycsb_home

			# RUNTIME PARAMS

#			client_th=$(nproc)	# No.of Threads to do operations
#			target_OPs=1000000	# Target Operations Per Sec
#			run_progress=-s		# Enable/Disable if long running process

			# Run for each workload
			
			ycsb_bin=./bin/ycsb.sh

			db=jdbc

			db_opts=ycsb-mysql-opts.properties
			
			echo "
			db.driver=com.mysql.jdbc.Driver
			db.url=jdbc:mysql://127.0.0.1:3306/ycsb
			db.user=rakesh
			db.passwd=rakesh123
			" | tee $db_opts
		       	
			
			for wrk_load in $(echo workloads/workloada) #{a..f})
			do
				run_conf=${db}-${wrk_load##*/}

				expf=${ycsb_res_dir}/${run_conf}-export.txt
				
				previous_header=""

				for cth in 1 $(seq 2 2 $(nproc))
				do

					outf=$ycsb_res_dir/ycsb-${run_conf}-${cth}th.txt
					
					progress=-s

					echo "[ $(app_get_fname) ] RUNNING YCSB: $run_conf [ threads = $cth ]"
					
					# LOAD
					$ycsb_bin load $db -threads $cth -P $db_opts -P $wrk_load

					# RUN
					$ycsb_bin run $db -threads $cth -P $db_opts -P $wrk_load ${progress} | tee $outf

					# Convert result to exportable format
					res_out="$(cat $outf | awk '/OVERALL/,0')"

					headers="$(echo -e "$res_out" | awk -F, '{print $1"-"$2}' | sed 's/- /-/g')"
					
					if [ $cth -eq 1 ]
					then
						previous_headers="$headers"

						# Write Headers
						{
						echo Threads
						echo "$headers"
						} | paste -s -d, | tee $expf 
						
						# Write Values
						{
						echo $cth
						echo -e "$res_out" | awk '/OVERALL/,0' | awk -F, '{print $3}' | xargs -n1 
						} | paste -s -d, | tee -a $expf
					else

						# Check if current headers matched to previous run headers
						if [ "$headers" != "$previous_headers" ]
						then
							label="[ NOTE ] Current header NOT MATCHING with previous Headers..!"
							app_disp_msg "$label"
							paste -d '\t' <(echo "$previous_headers") <(echo "$headers") 
							echo $label | sed 's/././g'
  						fi

						# Write Values
						{
						echo $cth
						echo -e "$res_out" | awk '/OVERALL/,0' | awk -F, '{print $3}' | xargs -n1 
						} | paste -s -d, | tee -a $expf
  					fi
				done
			done
		fi
	  fi
}
