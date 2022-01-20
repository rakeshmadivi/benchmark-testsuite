#!/bin/bash
debug_level=0
THISFILE=$(basename ${BASH_SOURCE})

#readonly 

jbb_multi_dbgf="debug.${THISFILE/.sh/}" # -$tnow"

exec 2> $jbb_multi_dbgf

set -xue

src=(
	utilities.sh
	power-stats.sh 
	plot-power-metrics.sh
)

# Source Required Files
sourceWrapper(){
	for s in ${src[@]}
	do
		[ ! -f $s ] && echo "Required file: $s" && exit
		source $s
	done
}
# ------------- SOURCE USING WRAPPER TO DISABLE ARGUMENTS TO BE PASSED TO SOURCING SCRIPTS ------

source_directly=1

if [ $source_directly -eq 1 ]
then
	ARGS="$@"
	eval set --
	for i in ${src[@]}
	do
		source $i
	done
	eval set -- "$ARGS"
else
	app_source_wrapper ${src[@]}
fi

#sourceWrapper

# ------------- ------------- -------------

# Increase groups till 4xNUMA-COUNT

numa_cnt=$(ls -ld /sys/devices/system/node/node*/ | wc -l)

# P/C State Info
statesInfo(){
	sudo cpupower frequency-set -g performance

	echo ----------------- PERFORMANCE / POWER SAVING STATES ---------------------------
	echo "P-STATES/ GOVERNORS"
	echo ==============
	cpupower frequency-info | grep governor | paste -d';' -s | tr -s ' '

	echo
	echo "IDLE STATES"
	echo ==============
	cpupower idle-info | egrep "idle states:"

	echo -e "\nTo enable (e)/disable (d) use cpupower command. \nEg: cpupower -c 0-15 idle-set -d 2 -> disables state-2"
	echo --------------------------------------------
}

# statesInfo | tee P-and-IDLE-states.txt
# exit

jbb_home=${2:-${HOME}/jbb15}
run_script=$jbb_home/run_multi.sh
jbb_config=$jbb_home/config/template-M.raw

tune_options(){
	# ----------------------------- OS KERNEL TUNING -----------------------------
	tune_options_file=jbb-tuning/tune-JBB.sh
	if [ -f $tune_options_file ]
	then
		echo "$(bash $tune_options_file intel)"
	else
		echo "[ File Not Found ] $tune_options_file" 1>&2
	fi
	# ----------------------------- OS KERNEL TUNING -----------------------------
}

run(){
	# --------------- OS TUNING ------------------------
	TUNE_OPTS="$(tune_options)"
	for kernel_file_val in $(echo -e "$TUNE_OPTS" | grep "TUNE:" | awk '{print $2":"$NF}')
	do
		kfile=${kernel_file_val%%:*}
		kval=${kernel_file_val##*:}

		echo "[ TUNING OS PARAMS ] $kfile $kval"
		echo ${kval} | sudo tee ${kfile}
	done
	# ----------------- DONE TUNING -----------------------

	cd $jbb_home
	echo "Current Directory: $PWD"

	# Memory Allocation to JVMs
	MEM_FREE=$(free -g | awk '{print $4}' | xargs | cut -f2 -d' ') 
	
	# Set the Test memory to be 1T or 1.5T
	MIN_MEM=1000
	
	[ $MEM_FREE -lt $MIN_MEM ] && echo "[ Memory Free = $MEM_FREE ] Min Memory Set to: $MIN_MEM. Please reduce the limit and proceed." && return 1
	MEM_TO_USE=$(awk -v M=$MEM_FREE -v R=1500 -v MIN=$MIN_MEM 'BEGIN{ ratio=M/R; printf "%d\n", (ratio >= 1)? R : MIN;}')
	echo "MEMORY TO USE: $MEM_TO_USE"

	#GROUP_COUNT=$(app_get_sut_info numa-count)
	
	for GROUP_COUNT in $numa_cnt 
	do
		for REDUCE_MEM in 0 # 50 100 
		do
			test_date=$(date +"%b %d, %Y")
			sed -i "s/test\.date=.*/test.date=$test_date/g" $jbb_config
			for k in "jbb2015.test.aggregate.SUT.totalNodes=" "jbb2015.test.aggregate.SUT.nodesPerSystem=" "jbb2015.product.SUT.hw.system.hw_1.nodesPerSystem="
			do
				sed -i "s/^$k.*/${k}${numa_cnt}/g" $jbb_config
			done
			
			echo Setting Group Count =  $GROUP_COUNT
			sed -i "s/^GROUP_COUNT.*/GROUP_COUNT=$GROUP_COUNT/g" $run_script
			
			TXBE_COUNT=$GROUP_COUNT
			
			TXI_PER_GROUP=2
			TXI_PER_GROUP=${TXI_PER_GROUP:-1} 
			
			# Set Tx Injector Count
			sed -i "s/^TI_JVM_COUNT.*/TI_JVM_COUNT=$TXI_PER_GROUP/g" $run_script
			
			TXI_COUNT=$((TXI_PER_GROUP * GROUP_COUNT ))
			TXC_COUNT=1

			# Option to enable/disable memory options for Controller.
			tune_controller_heap=false

			if [ $tune_controller_heap == true ]
			then
				TOTAL_JVM=$(( TXBE_COUNT + TXI_COUNT + TXC_COUNT ))
			else
				TOTAL_JVM=$(( TXBE_COUNT + TXI_COUNT)) # + TXC_COUNT ))
			fi
			
			MEM_PER_JVM=$(( (MEM_TO_USE - REDUCE_MEM) / TOTAL_JVM)) 
			
			XMEM=$MEM_PER_JVM 

			TI_MX=$((XMEM))
			BE_MX=$((XMEM * TXI_COUNT))	# Since, each backend has TXI_COUNT injectors

			JAVA_TUNE="-XX:+UseParallelGC"
			
			if [ $tune_controller_heap == true ]
			then
				JAVA_OPTS_C="-Xms$((XMEM-1))g -Xmx${XMEM}g ${JAVA_TUNE}"	# TODO Remove if no improvement seen
			fi
		
			# ---------- FROM TUNE OPTIONS
			
			TUNE_OPTS_C="$(echo -e "$TUNE_OPTS" | grep "Controller:" | cut -f2- -d':')"
			TUNE_OPTS_TXI="$(echo -e "$TUNE_OPTS" | grep "Txi:" | cut -f2- -d':' )"
			TUNE_OPTS_BE="$(echo -e "$TUNE_OPTS" | grep "Backend:" | cut -f2- -d':')"
			# ---------- END OF FROM TUNE OPTIONS	

			JAVA_OPTS_C="${TUNE_OPTS_C:--ms256m -mx1024m}"
			JAVA_OPTS_TI="${TUNE_OPTS_TXI}" #-Xms$((XMEM-1))g -Xmx${XMEM}g ${JAVA_TUNE}" #
			JAVA_OPTS_BE="${TUNE_OPTS_BE}" #-Xms$((BE_MX-1))g -Xmx${BE_MX}g ${JAVA_TUNE}" #		

			sed -i "s/^JAVA_OPTS_C.*/JAVA_OPTS_C=\"$JAVA_OPTS_C\"/g;" $run_script
			
			sed -i "s/Ctr_1.cmdline=.*/Ctr_1.cmdline= ${JAVA_OPTS_C}/g;" $jbb_config

			# Update BE, Injectors Heap options in Run Script
			sed -i "s/^JAVA_OPTS_TI.*/JAVA_OPTS_TI=\"$JAVA_OPTS_TI\"/g;s/^JAVA_OPTS_BE.*/JAVA_OPTS_BE=\"$JAVA_OPTS_BE\"/g;" $run_script

			# Update heap values for BE and TxI in config file
			sed -i "s/Backend_1.cmdline=.*/Backend_1.cmdline= ${JAVA_OPTS_BE}/g;s/TxInjector_1.cmdline=.*/TxInjector_1.cmdline= ${JAVA_OPTS_TI}/g" $jbb_config

			msg="
			============== CURRENT RUN CONFIGURATION ==================\n
			AVAILABLE MEMORY: $MEM_FREE = MEMORY TO USE: $MEM_TO_USE\n
			MEMORY PER JVM: $MEM_PER_JVM STACK:HEAP MEMORY = $XMEM:$XMEM\n\n		
			[ $GROUP_COUNT ] Groups\n
			[ $TXBE_COUNT ] Backends\n
			[ $TXI_COUNT ] Transaction Injectors\n
			[ $TXC_COUNT ] Conroller\n
			[ $TOTAL_JVM ] #JVMs tuned with heap memory $(if [ $tune_controller_heap == true ];then echo "[ Controller Heap Tuned. ]"; else echo "[ No Tuning for Controller Heap. ]"; fi )\n
			Using\n
			[ $XMEM ] Memory Per JVM\n
			--------------------------\n
			From Run Script:\n $(egrep "^GROUP_COUNT|^TI_JVM_COUNT|^JAVA_OPTS_" $run_script)"

			printf "$msg\n"

			app_disp_msg "Heap Options from config file:"

			egrep "cmdline=" $jbb_config | cut -f4- -d'.' 
			
			BMC_IP=$(sudo ipmitool lan print 1 | grep "IP Addr" | tail -1 | awk '{print $NF}')

			jbb_runlog=jbb-run.log
			
			collect_status_file=$BMC_IP-${GROUP_COUNT}G_${TXI_PER_GROUP}TI.status
			
			VENDOR_MODEL=$(sudo ipmitool fru | egrep "Product Name|Product Manufacturer" | cut -f2 -d: | awk '{print $1}' | xargs -n1 | paste -d_ -s )
			
			CPU=$(lscpu | grep "Model name:" | xargs | cut -f2 -d: | xargs -n1 | tr -d '()@' | xargs -n1 | paste -d_ -s)

			NUMA=$(lscpu | grep "NUMA node(" | cut -f2 -d: | xargs)

			GOVERNOR=$(cpupower frequency-info | grep "The governor" | cut -f2 -d'"')
			
			TOOL=all_metrics

			TEST_CONF=$TOOL-${GROUP_COUNT}G_${TXI_PER_GROUP}TI_per_G-$VENDOR_MODEL-$CPU-NUMA-$NUMA-$GOVERNOR

			METRICS_OUTFILE=${TEST_CONF}.txt

			start_power_collection --bmc $BMC_IP --tool $TOOL --jbb-run-log $jbb_runlog --collect-status-file $collect_status_file --output $METRICS_OUTFILE &
			
			collection_pid=$!

			echo "[ Collection PID ] $collection_pid"       

			echo -e "Starting SPECJBB ...."
			time ./run_multi.sh | tee $jbb_runlog
			
			# Signal to Stop Metrics Collection
			echo STOP > $collect_status_file

			# PLOT GRAPH
			# -----------
			JBB_RESULT_DIR=$(grep "Please monitor" $jbb_runlog | awk '{print $3}' | xargs dirname | xargs basename)

			RENAME_RES_DIR=${JBB_RESULT_DIR}-${TEST_CONF}
			PLOT_OUTPUT=${RENAME_RES_DIR}
			
			# Individual Graph
			#plot_graph -i $METRICS_OUTFILE -o $SUT -j ./${JBB_RESULT_DIR}

			set +e
			# Generate Multiplot
			# ------------------
			multi_plot -j ./${JBB_RESULT_DIR} -i $METRICS_OUTFILE -o $PLOT_OUTPUT -n ${RENAME_RES_DIR}
			echo STOP > $collect_status_file
			set -e
		done
		sleep 30
	done
}

listResults(){

	# Get Results info in jbb results directories
	# Regx for specjbb result directories
	regx="[0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]"
	for d in $(find $RES_DIR -name $regx -type d) 
	do
		echo
		echo Directory: $d
		cd $d
		config_file="./config/template-M.raw"
		flds_regx="SUT.vendor=|hwSystem=|SUT.nodesPerSystem=|cpuName="
		config="$(cat $config_file | egrep "$flds_regx" | cut -f2 -d=)"
		paste -d: <(echo SYSTEM_MODEL VENDOR NUMA CPU | xargs -n1) <(echo "$config")

		mx_size="JVM_MX_SIZE[ Controller, Backend, TxInjector ] = [ $(cat $config_file | grep "cmdline=" | cut -f2 -d= | xargs -I{} echo -n "{}, " | sed 's/..$//g')] "

		gsize=$(ls *Group*Backend* | cut -f1 -d. | tr -d '[a-z][A-Z]' | sort -n | tail -1;)
		txi_size=$(ls *Group*txiJVM* | cut -f3 -d. | tr -d '[a-z][A-Z]' | sort -n | tail -1;)
		
		grep RESULT *.out | sed "s/.*max-jOPS/$(basename $d) : GROUP_SIZE = $gsize TxInjectors-Per-Group = $txi_size $mx_size max-jOPS/g"
	done
}

get_column(){

	this="$(app_get_fname $THISFILE)"

	eval set -- "$GET_VALS"

	in_file=$(echo "$@" | cut -f1 -d:)
	
	[ ! -f $in_file ] && echo "${this}(): File [ $in_file ] not found" && exit

	KTYPE=$(echo $@ | cut -f2 -d:)
	
	[ $KTYPE == ID ] && fld_id=$(echo $@ | cut -f3 -d: )
	[ $KTYPE == NAME ] && fld_name=$(echo $@ | cut -f3 -d: )
	
	FIELDS=$(head -1 $in_file | xargs -n1 | egrep -n "^*$") # This produces output in #:HeaderName format.
	FID=""

	case "$KTYPE" in
		HEADERS )
			msg="${in_file} : Header Names"

			echo "$msg"
			echo "$msg" | sed 's/././g'
			echo "$FIELDS"
			return 0
			;;

		ID )
			FID="$(echo "$FIELDS" | grep "^${fld_id}:" | awk -F: '{print $1}')"  #>/dev/null
			;;

		NAME )
			FID="$(echo "$FIELDS" | egrep ":${fld_name}" | awk -F: '{print $1}')"
			;;

		* )
			echo "Invalid Key in second field. Valid Keys are HEADERS, ID, NAME"
			echo -e "$help_msg"
			return 1
			;;
	esac

	if [ -z "$FID" ]
	then 
		echo "Field ID/NAME Not found." && return 1
	else
		cat $in_file | awk '{print $'$FID'}' && return 0
	fi
}

parseMultiJbbArgs(){
	
	help_msg="USAGE: $0 <-r|--run> <-l|--list-results-in> <directory-name>"

	declare -A OPTS_MAP

	OPTS_MAP["h"]="help"
	OPTS_MAP["r"]="run"
	OPTS_MAP["l:"]="list-results-in:"
	OPTS_MAP["g:"]="get-column:"
	
	OPTS_ORDER=($(printf "%s\n" ${!OPTS_MAP[@]} | sort))
	
	SHORT=""
	LONG=""
	
	OPT_HELP="$THISFILE <Options>"
	
	for i in ${!OPTS_ORDER[@]}
	do
		KEY="${OPTS_ORDER[$i]}"
		SHORT+="${KEY},"
		LONG+="${OPTS_MAP[$KEY]},"
		
		# This is for Option Help 
		s_out="-${KEY/:/ <value>}"
		l_out="--${OPTS_MAP[$KEY]/:/ <value>}"
		OPT_HELP+="\n\t${s_out} | $l_out"
	done

	[ $# -eq 0 ] && echo -e "${OPT_HELP}" && exit

	[ $debug_level -eq 1 ] && echo "${SHORT[@]} == ${LONG[@]}"

	OPTS=$(getopt -o ${SHORT%,*} -l ${LONG%,*} -n ${THISFILE} -- "$@")
	
	eval set -- $OPTS

	while true
	do
		case "$1" in
			--help | -h)
				echo -e "$OPT_HELP"
				shift
				exit
				;;
			--run | -r )
				RUN=Y
				shift;;
			--list-results-in | -l )
				RES_DIR=$2
				shift 2;;
			--get-column | -g )
				ARGS=$(echo "$2" | xargs -d: | xargs -n1)
				NV=$(echo "$ARGS" | wc -l)

				F1="< input-filename >";
				F2="< KEY >"
				F3="< field-number | field-name >"
				EG="KEY = HEADERS, ID, NAME; Eg. input-data.txt:HEADERS, input-data.txt:ID:10, input-data.txt:NAME:My-field-name"

				help_msg="USAGE: \n${THISFILE} -g $F1:$F2:$F3 \n\t$EG"

				[ $NV -lt 2 ] && echo -e "$help_msg" && return 1
				
				GET_VALS="$(echo "$ARGS" | paste -d: -s)"

				shift 2;;
			-- )
				shift; break;;
			*)
				echo "$help_msg"
				echo "Provided: $@"
				exit;;
		esac
	done
}

set +x 
parseMultiJbbArgs $@ 2>&1 
set -x

#RES_DIR=${RES_DIR} #:-$jbb_home}

default_jbb_res_dir=${HOME}/disk-mnt/jbb15

[ ! -z "$RUN" ] && run
[ ! -z "${RES_DIR:-$default_jbb_res_dir}" ] && listResults 
[ ! -z "$GET_VALS" ] && get_column #$GET_VALS
