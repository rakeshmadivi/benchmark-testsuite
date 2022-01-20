#!/bin/bash
set -uxe
THISFILE=${BASH_SOURCE}
readonly p_dbgf="debug.$(basename ${THISFILE/.sh/})"

exec 2> $p_dbgf

[ $app_DEBUG -eq 2 ] && set -x 

[ $app_DEBUG -eq 5 ] && exec 2> $dbgf


# Required Arrays for metric collection
# ----------------------------------------
# Array to store file names of each metric type
declare -A STATS_FILE

# Array to hold Headers for each metric type
declare -A HEADERS

# This array controls the ORDER of Headers and values to common metrics file.
declare -a H_ORDER
H_ORDER+=("time" "ipmi" "memory" "turbo" "load" "cpufreq" "pstrack") 

# END OF GLOBAL VARIALES SECTION

#--------------- POWER STATS -----------
parse_power_stats_opts(){

	this="$BASH_SOURCE:${FUNCNAME[0]}()"

	# OPTIONS MAPPING as Short=Long, colon specifies value required   
	declare -A metrics_opt_map
	metrics_opt_map["h"]="help"
	metrics_opt_map["b:"]="bmc:"
	metrics_opt_map["j:"]="jbb-run-log:"
	metrics_opt_map["o:"]="output:"
	metrics_opt_map["s:"]="collect-status-file:"
	metrics_opt_map["t:"]="tool:"

	SHORT=( $(printf "%s\n" ${!metrics_opt_map[@]} | sort) )
	LONG=( $(for i in ${SHORT[@]};do echo ${metrics_opt_map[$i]}; done) )

	help_msg="USAGE: $this <Options>\n"
	cmn_msg=""	# To use in auto generation of option checking.
	for i in ${!SHORT[@]}
	do
		sopt=${SHORT[$i]}
		lopt=${LONG[$i]}
		cmn_msg+="\t$(echo "-${sopt} | --${lopt}\n")" 
	done

	help_msg+="$(echo -e "$cmn_msg" | sed 's/:/ <value>/g')"
	
	#cmd_msg+="$(echo -e "$cmn_msg" | sed 's/:/)\n\t\tVAR_=$2\; shift 2\;\;/2' )"

	#echo -e "$help_msg\nCOMMAND-MSG:\n$cmd_msg" && exit

	OPTS=$(getopt -o $(echo "${SHORT[@]}" | tr " " ",") -l $(echo ${LONG[@]} | tr ' ' ',') -n $this -- "$@" )

	eval set -- $OPTS
	echo "[ $this ] ARGS: $@"

	while true
	do
		case "$1" in
		--tool | -t )
			TOOL=$2
			shift 2
			;;

		--bmc | -b )
			BMCIP=$2
			shift 2
			;;

		--collect-status-file | -s )
			COLLECTION_STATUS_FILE=$2
			shift 2
			;;

		--output | -o )
			OUTPUT_FILE=$2
			shift 2
			;;

		--jbb-run-log | -j )
			JBB_RUN_LOG=$2
			shift 2
			;;

		--help | -h )
			echo -e "$help_msg"
			shift;
			exit
			;;
		-- )   	shift; break
			;;
		esac
	done
}

modprobe_dev(){
	sudo modprobe ipmi_devintf
	sudo modprobe ipmi_si
}

move_metrics_files_to_result_directory(){

	func_msg_prefix="[ $(app_get_fname) ]"

	[ ! -f $JBB_RUN_LOG ] && echo "JBB Run log \( $JBB_RUN_LOG \) not found." && return 1


	[ $(grep "Please monitor" ${JBB_RUN_LOG} >/dev/null 2>&1 ; echo $?)  -ne 0 ] && echo "Result Directory could not found in 'jbb-run.log'" && return 1

	RES_DIR=$(grep "Please monitor" ${JBB_RUN_LOG} | awk '{print $3}' | xargs dirname | xargs basename )

	RES_PARENT=$(dirname ${JBB_RUN_LOG})

	pushd $RES_PARENT

	if [ ${#STATS_FILE[@]} -gt 0 ]
	then
		echo "$func_msg_prefix | Moving Status Files | PWD, RES_PARENT, RES_DIR, = $PWD, $RES_PARENT, $RES_DIR"

		for f in ${STATS_FILE[@]}
		do
			[ ! -f ${f} ] && echo "$func_msg_prefix File Not Found: $f" && continue

			# Replace commas with spaces.
			sed -i 's/,/ /g' ${f}

			echo "Moving: [ ${f} ] => To: $RES_DIR/"

			mv ${f} $RES_DIR/
		done
	fi
		
	# MOVE metrics files to JBB Result Directory
	[ "$ALL_IN_ONE" == "yes" ] && [ -f $METRICS_FILE ] && mv $METRICS_FILE ${RES_DIR}/${RES_DIR}-${METRICS_FILE}

	return $?
}

power_supply_info(){
	{
	date
	sudo ipmitool sdr type "Power Supply"
	} | tee -a $power_supply 
}

check_collection_status(){
      if [ -f "$COLLECTION_STATUS_FILE" ];then
        if [ "`cat $COLLECTION_STATUS_FILE`" = "STOP" ] ;then
          printf "[ Received STOP Command ] STOPPING power collection...\n"
	  # move_metrics_files_to_result_directory
	  exit 0
        fi
      else
	      #printf "\r$MSG"
	      printf "\r[ check_collection_status() ] Collecting Power Metrics..."
      fi
}

ps_stats(){
	# USE this to get column number: top -bn1 | sed -n '/PID/,$p' | tr -s ' ' | awk 'NR==1{for(i=1;i<=NF;i++){print i"-"$i;}}' #awk '{if($9 > 0.0 ){print $0}}'
	
	topf=most-used-procs-top.txt
	psf=most-used-procs-ps.txt
	echo %CPU COMMAND | tee $topf $psf

	while true
	do
		top_procs="$(top -Hbcn1 -o %CPU | sed -n '/PID/,$p' | tr -s ' ' | awk '{if(NR==1){print $0};if($9 > 0.0 ){print $0}}' | sed 's/^ //g' | cut -f1,2,5- -d' ')"

		ps_procs="$(ps axT -o pid,user,%cpu,cmd,stime,etime --sort=-%cpu | tr -s ' ' | grep -v " 0.0 ")"

		# Identify non-java process using >10% of CPU
		non_java_top="$(echo "$top_procs" | grep -v "java")"
		most_cpu_users_top=$(echo "$non_java_top" | awk '{if($9 > 5.0){print $9,$NF}else{print "NONE"}}') | tee $topf

		non_java_ps="$(echo "$ps_procs" | grep -v "java")"
		most_cpu_users_ps=$(echo "$non_java_ps" | awk '{if($3 > 5.0){print $3,$NF}else{print "NONE"}}') | tee $psf

		no_of_procs=$( ps auxT | awk '{print $2}')

		check_collection_status

		sleep 30
	done
}

all_metrics_collection(){

	this="${BASH_SOURCE}:${FUNCNAME[0]}"

	[ -z "$(sudo which turbostat)" ] && echo "INSTALLING: turbostat" && sudo apt-get install turbostat -y

	#sudo turbostat -n 1 -S -s sysfs -s PkgWatt,RAMWatt --quiet | tee -a $turbostatOutput

	#Order of Values: "${TIME_NOW},$IPMI_VALS,$MEM_VALUES,$TURBO_VALUES,$LOAD_VALS,$CPUFREQ_VALS,${PSTRACK_VALS}"
	STATS_FILE[cpufreq]=cpufreq.txt
	STATS_FILE[ipmi]=ipmi.txt
	STATS_FILE[load]=load.txt
	STATS_FILE[memory]=memory.txt
	STATS_FILE[pstrack]=pstrack.txt
	STATS_FILE[turbo]=turbo.txt

	# Update status files list to app_SUT_INFO
	app_SUT_INFO["metricfiles"]="$(echo ${STATS_FILE[@]} | xargs -n1 | sort | xargs)"

	HEADERS[time]="DATE_TIME"

	declare -A VALUES
	
	HEADER=""
	WATT_FOUND=""
	ALL_IN_ONE=yes

	while true
	do
		MSG="\r[ ${this} ] Power Metrics (status: $COLLECTION_STATUS_FILE):"
		
		TIME_HEADER=DATE_TIME
		VALUES[time]=$(date +"%d-%m-%y_%T") 


		if [ $(ls /dev/ipmi* 2>/dev/null | wc -l) -eq 0 ]
		then
		       	echo -e "$MSG [ NO IPMI DEVICE FOUND. Power Metrics Collection SKIPPING ]"
			NO_IPMI=true
		else
			
			# IPMI Metrics - Power Utilization
			# --------------------------------
			SDR="$(sudo ipmitool sdr list)" 
			[ -z "$WATT_FOUND" ] && WATT_FOUND=$(echo -e "$SDR" | grep "Watt" > /dev/null 2>&1; echo $?)

			if [ $WATT_FOUND -eq 0 ]
			then
				printf "$MSG [ Watt ]\n"
				
				IPMI_FIELDS=$(echo -e "$SDR" | grep "Watt"  | awk -F '|' '{print $1}' | tr ' ' '-' | sed 's/--.*//g' | paste -d, -s)
				
				IPMI_VALS="$(echo -e "$SDR" | egrep "Watt" | cut -f2 -d '|' | awk '{print $1}' | paste -d, -s )"
			else
				printf "$MSG [ Volts/Amps ]\n"
				IPMI_FIELDS=$(echo -e "$SDR" | awk -F '|' '{print $1}' | tr ' ' '-' | sed 's/--.*//g' | paste -d, -s)
				IPMI_VALS="$(echo -e "$SDR" | egrep "Volts|Amps" | cut -f2 -d '|' | awk '{print $1}' | paste -d, -s)"
			fi

			HEADERS[ipmi]="$IPMI_FIELDS"
			VALUES[ipmi]="$IPMI_VALS"
		fi  # IPMI DEVICE /dev/ipmi* check

		# Memory Statistics
		# --------------------------------
		HEADERS[memory]="MEM-TOTAL,MEM-USED"
		VALUES[memory]="$(free -m | grep Mem: | xargs | cut -f2,3 -d' ' | tr ' ' ',')"
	
		# Turbostats	
		# --------------------------------
		TURBO_STATS="$(sudo turbostat -S -n1 -q 2>&1 | sed 's/[[:space:]]/,/g')"
		HEADERS[turbo]="$(echo -e "$TURBO_STATS" | head -n1)"
		VALUES[turbo]="$(echo -e "$TURBO_STATS" | tail -n1)"

		# System Load
		# --------------------------------
		HEADERS[load]="LoadAVg-1m,LoadAvg-5m,LoadAvg-15m"
		VALUES[load]=$(uptime | awk -F: '{print $NF}' | tr -d ' ')

		# CPU Frequency
		# --------------------------------
		HEADERS[cpufreq]="CPU_Freq"
		VALUES[cpufreq]="$(
		freq=$(cpupower frequency-info | grep "asserted" | xargs | cut -f4,5 -d ' ') # Contains: NNN <GHz|MHz>
		if [ "$(echo "$freq" | cut -f2 -d ' ')" == "MHz" ]
		then
			echo "$freq" | awk '{print $1/1000}'
		else
			echo "$freq" | awk '{print $1}'
		fi
		)"

		# Non-Java Process Tracking
		# --------------------------------
		NON_JAVA_PS="$(ps -eo pcpu,comm | tail -n+2 | grep -v "java" | awk '{s+=$1;print $2}END{printf "#NonJava-Processes %d\nNon-JAVA-CPU-Usage %f",NR,s/NR}')"

		HEADERS[pstrack]="#NonJava-Processes,Non-JAVA-CPU-Usage"
		VALUES[pstrack]="$(echo "$NON_JAVA_PS" | egrep "#NonJava-Processes|Non-JAVA-CPU-Usage" | awk '{print $2}' | paste -d, -s)"

		if [ -z "$HEADER" ]
		then
			# Write to individual metics files
			for f in ${!STATS_FILE[@]}
			do
				[ $f == ipmi ] && [ ${NO_IPMI:-false} == true ] && continue

				echo "${HEADERS[time]},${HEADERS[$f]}" | tee ${STATS_FILE[$f]}
			done

			# Write to all-in-one metrics file
			if [ "$ALL_IN_ONE" == "yes" ]
			then
				for oid in ${!H_ORDER[@]}
				do
					metric=${H_ORDER[$oid]:-}

					[ $metric == ipmi ] && [ ${NO_IPMI:-false} == true ] && continue

					echo "${HEADERS[${H_ORDER[$oid]}]}"
				done | paste -d, -s | tee $METRICS_FILE | awk -F, '{print "[ # Headers ]",NF}' #&& HEADER=written
			fi
			HEADER=written
		else
			# Write values to Individual Files
			for f in ${!STATS_FILE[@]}
			do
				metric=${f}

				[ $metric == ipmi ] && [ ${NO_IPMI:-false} == true ] && continue
				
				echo "${VALUES[time]},${VALUES[$f]}" | tee -a ${STATS_FILE[$f]}
			done

			# Write to all-in-one metrics file
			if [ "$ALL_IN_ONE" == "yes" ]
			then
				for oid in ${!H_ORDER[@]}
				do
					metric=${H_ORDER[$oid]:-}

					[ $metric == ipmi ] && [ ${NO_IPMI:-false} == true ] && continue
					
					echo "${VALUES[${H_ORDER[$oid]}]}"
				done | paste -d, -s | tee -a $METRICS_FILE | awk -F, '{print "[ # Values ]",NF}'
			fi
		fi

		check_collection_status
		sleep 30
	done
}

# Power Collection using Redfish API
redfish_power_reading(){
	#set -x
        this="${BASH_SOURCE}:${FUNCNAME[0]}"
	[ $# -eq 0 ] && echo -e "Error: BMC IP is not provided. Exiting." && exit
        
	bmcIP=$1
	bmc_user=${2:-admin}
	bmc_pwd=${3:-password}
	echo "BMC: $bmcIP USER: $bmc_user PWD: $bmc_pwd" 1>&2
	
	power_uri="https://$bmcIP/redfish/v1/Chassis/Self/Power"

	power_json="$(curl -skL $power_uri -u $bmc_user:$bmc_pwd)"

	[ $? -ne 0 ] && echo "Something went wrong in fetcing redfish power metrics using uri: $power_uri" && exit

	#echo "$power_json" | jq -r '.|map(has("PowerControl"))' > /dev/null
	#[ $? -ne 0 ] && echo "These metics doesn't have 'PowerControl'"

	#echo "$power_json" | jq -r '.PowerControl | .[] | map(has("PowerConsumedWatts"))' > /dev/null
	#[ $? -ne 0 ] && echo "These metics doesn't have 'PowerConsumedWatts'"
	
	#echo "$power_json" | jq -r '.PowerControl | .[] | map(has("PowerMetrics"))' > /dev/null
	#[ $? -ne 0 ] && echo "These metics doesn't have 'PowerMetrics'"
        
	powerConsumed=($(echo "$power_json" | jq -r '.PowerControl |.[].PowerConsumedWatts'))
	powerMetrics=$(echo "$power_json" | jq -r '.PowerControl |.[].PowerMetrics |"\(.MinConsumedWatts)-\(.AverageConsumedWatts)-\(.MaxConsumedWatts)"' | paste -d, -s )

	echo -e "$(date +"%d-%m-%y_%T"),$powerConsumed,$(echo $powerMetrics | xargs -d'-' | xargs | tr ' ' ',')"
	#set +x
}

redfish_collection(){
	this="${BASH_SOURCE}:${FUNCNAME[0]}()"
	
	# Get BMC IP 
	[ $# -eq 0 ] && read -p "Enter <BMC_IP>:<BMC_USER>:<BMC_PASSWORD>\n" bmc_details
	[ $# -eq 1 ] && bmc_ip=$1
	[ "$bmc_ip" = "" ] && echo -e "No BMC IP provided. Skipping Redfish Power Collection." && return 1
	
	BMC_DETAILS=($(echo "$bmc_details" | xargs -d:))
	bmc_ip=${BMC_DETAILS[0]}
	bmc_user=${BMC_DETAILS[1]}
	bmc_pwd=${BMC_DETAILS[2]}

	MSG="[ Redfish - $this ] Power Metrics using BMC: $bmc_ip. Writing to: $METRICS_FILE"
	
	#echo  "Redfish Power Collection on BMC IP: $bmc_ip"
	#echo "Date,Power Consumed,Avg. Power,Min. Power,Max. Power" | tee $METRICS_FILE
	
	echo "Date,Power Consumed,Min_Power,Avg_Power,Max_Power" | tee $METRICS_FILE

        while true
        do
                redfish_power_reading $bmc_ip $bmc_user $bmc_pwd | tee -a $METRICS_FILE
		check_collection_status 

                sleep 30
        done
}

amd_TDP_collection(){
	amd_utility=cpu_pm_ns_follow_AMD
	_home=${HOME}
	[ ! -f "$_home/$amd_utility" ] && echo "AMD TDP Metric Utility: $amd_utility Not Found." && exit

	ln -s $_home/$amd_utility $amd_utility

	[ -f $METRICS_FILE ] && echo Removing old metrics file... && sudo rm $METRICS_FILE

	sudo ./$amd_utility -a -o $METRICS_FILE &
	amd_util_pid=$!

	#[ -z "$(pidof $amd_utility)" ] && echo "Error: Could not start '$amd_utility'." && exit

	echo "[ $amd_utility ] PID = $amd_util_pid (pidof: $(pidof $amd_utility)) Started."

	while [ ! -z "$(pidof $amd_utility)" ]
	do
		if [ -z "$(pidof java)" ]
		then
			echo "[ $amd_utility ] No JBB process processes running... Exiting."
			sudo kill -9 $amd_util_pid
			break
		fi

		check_collection_status 
		echo -en "\r\e[KCollecting CPU TDP using amd utility..."
		sleep 10
	done

}

start_power_collection(){
	# PARSE ARGUMENTS
	parse_power_stats_opts $@
	
	#if [ $(ls /dev/ipmi* 2>/dev/null | wc -l) -eq 0 ]
	if [ ${IPMI_PRESENT:-0} -eq 1 ]
	then
		VENDOR_MODEL="$(sudo ipmitool fru | egrep "Product Name|Product Manufacturer" | cut -f2 -d: | awk '{print $1}' | xargs -n1 | paste -d_ -s )"
	else
		echo -e "$(app_get_fname): [ NO IPMI DEVICE FOUND. Power Metrics Collection SKIPPING ]"

		VENDOR_MODEL="VendorNA-ModelNA" 
	fi
			
	CPU="$(lscpu | grep "Model name:" | cut -f2 -d: | sed 's/\(R\)//g' | tr -d '()@' | xargs | tr ' ' '_')"

	NUMA_COUNT="$(lscpu | grep "NUMA node(" | awk '{print $NF}')"

	MEM_CONF=$(app_get_sut_info memory | xargs | tr '[, ]' '_')

	default_postfix=txt
	default_out_f=power-metrics-${TOOL:-NoTool}-${VENDOR_MODEL:-VendorNA}-${CPU:-CpuNA}-NUMA-${NUMA_COUNT:-NumaCountNA}-${MEM_CONF}
	
	if [[ "$OUTPUT_FILE" == *.txt ]]
	then
		METRICS_FILE=${OUTPUT_FILE:-$default_out_f}
	else
		METRICS_FILE=${OUTPUT_FILE:-$default_out_f}.${default_postfix}
	fi

	# Remove Existing Collection Status File
        if [ -f "$COLLECTION_STATUS_FILE" ];then
                echo Removing Existing power status file...
                rm -rf $COLLECTION_STATUS_FILE
        fi

	if [ "$TOOL" == "redfish" ]
	then
		redfish_collection $BMCIP

	elif [ "$TOOL" == "amd-utility" ]
	then
		amd_TDP_collection

	elif [ "$TOOL" == "all_metrics" ]
	then
		all_metrics_collection
	fi
	echo "Output Stored in: $METRICS_FILE"
}

#[ $# -gt 0 ] && start_power_collection $@
