#!/bin/bash

APP_TITLE="PLATFORM EVALUATION FRAMEWORK"
APP_VERSION=v0
APP_MAIN=benchmark-main.sh

THISFILE=${BASH_SOURCE}
app_dbgf=debug.${THISFILE/.sh/}

#app_DEBUG=0

[ $app_DEBUG -eq 2 ] && echo "[ $BASH_SOURCE ] ARGS: $@ [$#]" 1>&2

set -uea

[ $app_DEBUG -eq 2 ] && set -x 

[ $app_DEBUG -eq 5 ] && exec 2> $app_dbgf

app_source_wrapper(){
	for i in $@
	do
		# if-else one liner
		[ -f $i ] && source $i || echo "File [ $i ] Not Found." && return 1
	done
}

app_print_title(){
	echo $@ | sed 's/./-/g'
	echo $@
	echo $@ | sed 's/./-/g'
}

app_disp_msg(){
	echo -e "\n$@"
	echo "$@" | sed 's/././g'
}

app_log_stdout(){
	echo "[ Func: ${FUNCNAME[1]}() ] $@"
}

app_log_stderr(){
	echo "[ Func: ${FUNCNAME[1]} ] $@" 1>&2
}

app_get_fname(){
	if [ $# -eq 1 ]
	then
		# ScriptName:FunctionName()
		echo "$1:${FUNCNAME[1]}()"
	else
		# FunctionName()
		echo "${FUNCNAME[1]}()"
	fi
	return 0
}

# ---------- ARRAYS to Store Overall Application Options [ Not User Set Options ] ----------
app_SHORT=()
app_LONG=()

# Option Descriptions if given
declare -A app_DESC

# Delimiter to separate Option and Option Description
APP_DESC_DL="@"

# Store Options Set by user from Command line arguments.
declare -A app_USER_SET_VALS

# Maintain list of functions defined
app_FUNCTIONS=()

app_add_fname(){
	[ $# -eq 0 ] && echo "Required function name as argument." && return 1
	app_FUNCTIONS+=( $1 )
}

# Save commonly required  SUT info 
declare -A app_SUT_INFO

app_add_sut_key(){

	log_prefix="[ $(app_get_fname) ]"
	app_log_stderr "$log_prefix Adding Key = Value: $1 = $2"

	app_SUT_INFO["$1"]="$2"
}

app_get_system_memory(){
	echo $(sudo lshw -c memory -short | grep "System" | awk '{print $(NF-2)}')
}

app_get_sut_info(){

	log_prefix="[ app_get_sut_info() ]"

	[ $# -le 0 ] && echo "$log_prefix No key provided." && return 1

	for k in $@
	do
		k_val=${app_SUT_INFO[$k]:-}

		echo "$k_val"
		app_log_stderr "$log_prefix key = value : $k = $k_val"
	done
}

app_print_sut_info(){
	
	[ $(echo "${!app_SUT_INFO[@]}" | awk '{print NF}') -eq 0 ] && echo "No Entries Found in app_SUT_INFO." && return 1
	
	for i in ${!app_SUT_INFO[@]}
	do
		echo "$i: $(app_get_sut_info $i)"
	done	
}

app_max_mem_divisor(){

	app_log_stderr "[ $(app_get_fname) ] Finding max memory divisor"

	MEM_M=$(free -m | awk '{print $4}' | sed -n '2p')
	FREE_MEM_G="$(( ( MEM_M - (1024*5)) / 1024 ))"
	
	DIVISOR=10

	MAX_DIVISOR=""

	while true
	do
		QUOTIENT=$((FREE_MEM_G/DIVISOR))

		if [ $QUOTIENT -gt 1 ]
		then
			DIVISOR=$((DIVISOR*10))
		else
			break
		fi
		MAX_DIVISOR=$DIVISOR
	done

	out="${MAX_DIVISOR:--1}:${QUOTIENT:-0}"

	if [ "$out" == "-1:0" ]
	then
		app_log_stderr "Insufficient Memory!"
		echo $out
		#return 1
	else
		echo $out
		#return 0
	fi
	
}

app_add_fname "app_set_SUT_INFO"
app_update_sut_info(){

	this="${BASH_SOURCE}:${FUNCNAME[0]}"

	app_disp_msg "[ $this ] Updating SUT Info..."

	# No.of cpus
	app_SUT_INFO["nproc"]=$(nproc)

	# NUMA DETAILS
	nodes=( $(ls -d /sys/devices/system/node/node* | sort -n) )

	for i in ${!nodes[@]}
	do
		local key="numa-$i"
		local value="$(cat /sys/devices/system/node/node${i}/cpu*/topology/thread_siblings_list | sort | uniq | paste -d, -s)"
		
		app_SUT_INFO["$key"]="$value"
		
		[ $app_DEBUG -eq 4 ] && echo "[ $BASH_SOURCE ] app_SUT_INFO[$key] ${app_SUT_INFO[$key]}" 1>&2
	done

	IPMI_PRESENT=1

	if [ $(ls /dev/ipmi* 2>/dev/null | wc -l) -eq 0 ]
	then
		echo -e "$(app_get_fname): [ NO IPMI DEVICE FOUND. ]"
		IPMI_PRESENT=0
	fi
	
	if [ $IPMI_PRESENT -eq 1 ]
	then
		app_SUT_INFO["bmc-ip"]=$(sudo ipmitool lan print 1 | grep "IP Addr" | tail -1 | awk '{print $NF}')

		# SUT - Product, Manufacturer, CPU Details, NUMA Count, Governor
		app_SUT_INFO["vendor-model"]=$(sudo ipmitool fru >/dev/null 2>&1 && sudo ipmitool fru | egrep "Product Name|Product Manufacturer" | cut -f2 -d: | awk '{print $1}' | xargs -n1 | paste -d_ -s || echo "-NA-")
	fi

	#app_SUT_INFO["cpu"]=$(lscpu | grep "Model name:" | xargs | cut -f2 -d: | xargs -n1 | tr -d '()@' | xargs -n1 | paste -d_ -s)
	app_SUT_INFO["cpu"]="$(lscpu | grep "Model name:" | cut -f2 -d: | sed 's/\(R\)//g' | tr -d '()@' | xargs | tr ' ' '_')"

	app_SUT_INFO["numa-count"]=$(lscpu | grep "NUMA node(" | cut -f2 -d: | xargs)

	which cpupower > /dev/null && [ $(cpupower frequency-info | grep "available cpufreq governors: Not Available" >/dev/null;echo $?) -ne 0 ] && echo "|Setting Governor.." && sudo cpupower frequency-set -g performance

	app_SUT_INFO["governor"]=$(cpupower frequency-info | grep "The governor" | cut -f2 -d'"')

	# MEMORY
	app_SUT_INFO["memory"]="$(sudo dmidecode -t memory | egrep "Manufacturer:|Size:|Part Number:" | egrep -v "Volatile|Cache|Logical" | xargs | sed 's/Size:/\nSize:/2g; s/Manufacturer://g; s/Part Number://g; s/Size://g' | awk '{if($2 ~ /.*MB/){ s=""; for(i=1; i<=NF;i++){ if(i==1){printf "%.0f GB ",$i/1024; i+=1;}else{printf "%s ", $i};};print "";}else{print $0}}' | sed 's/[[:space:]]+*$//g' | sort | uniq -c | tr -s '[:space:]' | sed 's/^[[:space:]]+*//g; s/ / x /1' | paste -d, -s)"

	#echo -e "MEMORY: ${app_SUT_INFO[memory]}" && exit

	[ $(which lsscsi > /dev/null; echo $?) -ne 0 ] && sudo apt-get install lsscsi -y

	app_SUT_INFO[disk]="$(lsscsi -s | paste -d, -s)"

	# Collect Info from dmidecode
	dmidecode_strings=(bios-vendor bios-version bios-release-date system-manufacturer system-product-name system-version system-serial-number system-uuid system-family baseboard-manufacturer baseboard-product-name baseboard-version baseboard-serial-number baseboard-asset-tag chassis-manufacturer chassis-type chassis-version chassis-serial-number chassis-asset-tag processor-family processor-manufacturer processor-version processor-frequency)

	
	app_SUT_INFO[systeminfo]="$(
	for str in ${dmidecode_strings[@]}
	do
		#app_SUT_INFO["$str"]="$(sudo dmidecode -s $str | uniq | xargs)";

		echo "$str = $(sudo dmidecode -s $str | uniq | paste -d, -s | xargs)"
	done
	)"
}

save_sut_info(){

	app_disp_msg "SYSTEM INFO"
	app_get_sut_info systeminfo

	echo -e "\nCPU = $(app_get_sut_info cpu)"
	
	echo -e "\nNUMA = $(app_get_sut_info numa-count)"
	
	echo -e "\nGOVERNOR = $(app_get_sut_info governor)"

	echo -e "\nMEMORY INFO = $(app_get_sut_info memory)"

	echo -e "\nDISK INFO = $(app_get_sut_info disk)"
}

app_set_options(){

	this="$(app_get_fname ${BASH_SOURCE})"

	# CHECK IF OPTIONS ARE CORRECTLY SET i.e req.short should have respective req.long option. s:=long: - right, s=long: - wrong.

	# RESET app_SHORT, app_LONG, app_DESC
	unset app_SHORT app_LONG app_DESC

	if [ -z "${APP_OPTIONS:-}" ]
	then
		echo "[ ERROR ] APP OPTIONS are not defined..!" && exit 1
	else
		APP_OPTIONS+="v:=verbose:${APP_DESC_DL}Enable Verbose level for debugging."

		if [ $app_DEBUG -eq 2 ]
		then
			app_print_title "APP_OPTIONS (verbose [ levels 0-3 ] option appended by default):"
			echo -e "$APP_OPTIONS"
		fi
	fi

	#if [ $# -ge 1 ]
	#then
	#	APP_OPTIONS="$(echo -e "$@" | grep -v "^$" | sed 's/^[[:space:]]*//g')"
	#else
		APP_OPTIONS="$(echo -e "${APP_OPTIONS}" | grep -v "^$" | sed 's/^[[:space:]]*//g')"
	#fi

	app_req_opts="$(echo -e "$APP_OPTIONS" | sed "s/${APP_DESC_DL}.*//g" | grep ":" )" 
	
	[ $( echo "$app_req_opts" | tr -cd '[:\n]' | uniq | wc -l) -ne 1 ] && echo -e "[ERROR] Please correct missing required tag(:) in option definitions: \n${app_req_opts}" && return 1

	app_HELP="USAGE: $APP_MAIN <OPTIONS>\n"
	
	#mapfile -t map_options <<< "${APP_OPTIONS}" #(set -x; echo -e "${APP_OPTIONS}" | egrep -v "^$" | sort | sed 's/^[[:space:]]*//g'; set +x)"
	mapfile -t map_options <<< "$(echo -e "${APP_OPTIONS}" | egrep -v "^$" | sort | sed 's/^[[:space:]]*//g';)"

	if [ $app_DEBUG -eq 2 ]
	then
		echo "[ No.of Options: ${#map_options[@]} ]"
		printf "%s\n" "${map_options[@]}"
	fi

	for i in ${!map_options[@]}
	do
		ms_opt=$(echo "${map_options[$i]}" | awk -F"${APP_DESC_DL}" '{print $1}' | cut -f1 -d= | xargs) #tr -d '[:space:]' | cut -f1 -d= )
		ml_opt=$(echo "${map_options[$i]}" | awk -F"${APP_DESC_DL}" '{print $1}' | cut -f2 -d=)
		ml_desc=$(echo "${map_options[$i]}" | awk -F"${APP_DESC_DL}" '{print $2}')
		
		app_SHORT+=( "$ms_opt" )
		app_LONG+=( "$ml_opt" )
		app_DESC+=( [$i]="$ml_desc" )

		opt_line="-${app_SHORT[$i]} | --${app_LONG[$i]} - ${app_DESC[$i]}" 
		
		[ $app_DEBUG -eq 2 ] && echo "Added: $opt_line"
		app_HELP+="$(echo "$opt_line" | sed 's/:/ <Value>/g')\n"
	done
}

go_through_switch_cases(){

	# BUILD SWITCH CASE statements from defined APP OPTIONS
	case_statements=""

	for i in ${!app_SHORT[@]}
	do
		local _short=${app_SHORT[$i]}
		local _long=${app_LONG[$i]}

		local line_delimiter="\n\t"
		
		local _output_str="$(echo "-${_short} | --${_long} )" | tr -d ':' )${line_delimiter}"

		local user_k="${_short},${_long}"

		opt_multiple_times=yes
		
		if [[ "${_short}" == *: ]]
		then
			if [ $opt_multiple_times == yes ]
			then
				req_opt_stmts="

				if [ ! -z \"\${app_USER_SET_VALS[$user_k]:-}\" ]
				then
					app_USER_SET_VALS[$user_k]=\"\${app_USER_SET_VALS[$user_k]},\$2\"
				else
					app_USER_SET_VALS+=([$user_k]=\"\$2\")
				fi
				"
			else
				req_opt_stmts="app_USER_SET_VALS+=([$user_k]=\$2;"
			fi
			
			case_statements+="${_output_str} ${req_opt_stmts} shift 2;;\n"
		else
			if [ $opt_multiple_times == yes ]
			then
				opt_opt_stmts="app_USER_SET_VALS+=([$user_k]=true)"
#				opt_opt_stmts="
#				if [ ! -z \"app_USER_SET_VALS[$user_k]\" ]
#				then
#					app_USER_SET_VALS[$user_k]=\"\${app_USER_SET_VALS[$user_k]},true\"
#				else
#					app_USER_SET_VALS+=([$user_k]=\"true\")
#				fi
#				"
			else
				opt_opt_stmts="app_USER_SET_VALS+=([$user_k]=true"
			fi
			
			case_statements+="${_output_str} ${opt_opt_stmts}; shift ;;\n"
		fi
	done

	if [[ $app_DEBUG -eq 3 ]] && [[ ! -z "$case_statements" ]]
	then
		app_print_title "BUILT CASE STATEMENTS:"
		echo -e "$case_statements"
	fi

	app_PARSE_CMD='
	
	if [ $app_DEBUG -eq -99 ]
	then
		echo "ARGS PASSED [ $# ] : $@ "
		for i in $(seq 0 $# | head -n-1)
		do
			echo "app_PARSE_CMD ARG-$i: $(eval "echo \$$i")"
		done
	fi

	while true
	do
		case "$1" in
			'$(echo -e "${case_statements}")'
			-v | --verbose ) app_DEBUG=$2; echo "VERBOSE (app_DEBUG) set to: $2"; shift 2;;
			-- ) shift; break;;
			* ) echo -e "$app_HELP"; shift; exit;;
		esac
	done
	'

	if [ $app_DEBUG -eq 3 ]
	then
		echo "User Input: $@"
		app_disp_msg "OPTIONS WILL BE PARSED USING:"
		echo -e "$app_PARSE_CMD"
	fi

	# printenv | grep VAR_	# This is matching every initialization thats having text 'VAR_'

	eval set -- $@

	# EXECUTE BUILT SWITCH CASES
	eval "$app_PARSE_CMD" # This will set user values

	if [ $app_DEBUG -eq 2 ]
	then
		app_print_title "OPTIONS SET USING app_USER_SET_VALS[] array"
		for i in ${!app_USER_SET_VALS[@]}
		do
			echo "${i} | ${app_USER_SET_VALS[$i]}"
		done
	fi
}

app_parse_user_options(){
	
	this="$BASH_SOURCE:${FUNCNAME[0]}()"

	parse_statf=status.option-parse
	app_OPTS=$(getopt -o $(echo "${app_SHORT[@]}" | xargs | tr ' ' ',') -l $(echo "${app_LONG[@]}" | xargs | tr ' ' ',') -n $this -- "$@" 2>&1 ; echo $? > $parse_statf 2>&1 )

	parse_success=$(cat $parse_statf)
	
	if [ $parse_success -ne 0 ]
	then
		echo -e "[ ERROR ] Failed to parse arguments."
		
		echo
		echo "-----[ getopt Error ]------"
		echo "$(echo $app_OPTS)"

		echo
		echo "-----[ Debug Files ]------"
		echo -e "$(ls debug.* | xargs -n1)"
		exit 1
	fi

	eval set -- $app_OPTS

	[ ! -z "$(echo "${app_OPTS##*--}" | xargs)" ] && echo "[ $app_OPTS ] Invalid no.of arguments. Please check options using: $0 -h" && exit 1 

	# SET VERBOSE LEVEL BEFORE CALLING ANYTHING
	user_verbose="$(echo "$app_OPTS" | xargs -n1 | egrep -x -A1 "\-v|\--verbose" | tr -d "[a-zA-Z-]" | sort | tail -1 )"

	#echo "$user_verbose" && exit

	app_DEBUG=${user_verbose:-0}
	[ $app_DEBUG -eq 2 ] && echo "USER VERBOSE ($@): $app_DEBUG / $user_verbose"

	go_through_switch_cases $@

	if [ $app_DEBUG -eq 2 ]
	then
		echo "AFTER PARSING:"
		for i in ${!app_USER_SET_VALS[@]}
		do
			echo [ app_USER_SET_VALS[$i] ] ${app_USER_SET_VALS[$i]}
		done
	fi

}

app_list_numa(){

	# GET NUMA INFO
	app_get_SUT_INFO numa

	grp_size=$1
	txi=$2
	cntlr_cpu_list="$(echo ${node_threads[@]} | paste -d, -s) --inteleave=all"

	g_node_map=()

	for((g=0; g<$grp_size; g++))
	do
		g_node_map+=( $((g % ${#nodes[@]})) )
	done
	
	# prints: Node #groups
	n_g_count="$(printf "%s\n" "${g_node_map[@]}" | sort | uniq -c | awk '{print $2,$1}')" 

	declare -A JVMS

	all_threads=$(echo ${node_threads[@]} | paste -d, -s )

	for n in ${!nodes[@]}
	do
		thread_list=${node_threads[$n]}

		# No.of Groups on Node n
		ng=$(echo "$n_g_count" | grep "$n" | awk '{print $2}')

		# No.of jvms to place on this node.
		jvm_cnt=$((ng + (ng*txi) ))

		# Threads count in this node
		node_thread_cnt=$(echo "${thread_list}" | awk -F, '{print NF}')

		jvm_th_cnt=$((node_thread_cnt / jvm_cnt))

		# No.of threads each split gets 
		if [ $jvm_th_cnt -lt 1 ]
		then
			JVMS["$n"]="$thread_list"
		else
			JVMS["$n"]="$(
			for ((s=1; s<=$jvm_cnt; s++))
			do
				till=$((s*jvm_th_cnt)) 
				from=$((till - (jvm_th_cnt-1) ))
				
				jvm_th_list=$(echo "${thread_list}" | cut -d, -f${from}-$till)

				echo "JVM-$s : $jvm_th_list" 1>&2
				echo $jvm_th_list
			done | xargs
			)"
		fi

	done

	for i in ${!JVMS[@]}
	do
		echo "JVMs on $i [${#JVMS[$i]}] : ${JVMS[$i]}"
	done
	
}

app_tune_os_params(){
	# Create sysctl config file:
	tunefile=/etc/sysctl.d/40-tune-specjbb.conf

	cat << EOF | sudo tee $tunefile
# Global Kernel Tuning
kernel.numa_lancing = 0
kernel.sched_child_runs_first = 0
kernel.sched_schedstats = 0
kernel.sched_tunable_scaling = 1
kernel.sched_rr_timeslice_ms = 100
kernel.sched_migration_cost_ns = 1000
kernel.sched_cfs_bandwidth_slice_us = 10000
kernel.sched_rt_period_us = 1000000
kernel.sched_latency_ns = 16000000
kernel.sched_min_granularity_ns = 28000000
kernel.sched_wakeup_granularity_ns = 50000000
kernel.sched_nr_migrate = 9
kernel.sched_rt_runtime_us = 990000
	
# VM Tuning
vm.swappiness = 10
vm.dirty_backgroud_ratio = 10
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 500
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.overcommit_memory=2
# net.ipv4.tcp_timestamps=0
EOF
	# | sudo tee /etc/sysctl.d/40-tune-specjbb.conf

	# Load tuning parameters from above file
	sudo sysctl -p $tunefile
	
	# Disable: Transparante Huge Pages by adding following to 'GRUB_CMDLINE_LINUX_DEFAULT' in /etd/default/grub
	# transparent_hugepage=never
	
	# Enable sysctl settings using following command
	# sudo sysctl --system

}

# AMD: Add cgroup_disable=memory,cpu,cpuacct,blkio,hugetlb,pids,cpuset,perf_event,freezer,devices,net_cls,net_prio to GRUB_CMDLINE_LINUX_DEFAULT

app_tune_ulimits(){
	ulimit -n 1024000
	ulimit -v 800000000
	ulimit -m 800000000
	ulimit -l 800000000
	UserTasksMax=970000
	DefaultTasksMax=970000
}

app_DIMM_JEDEC_format(){
# ### DDR4 Format:
# ### N x gg ss pheRxff PC4v-wwwwaa-m
# ### Example:
# ### 8 x 16 GB 2Rx4 PC4-2133P-R
# ### 
# ### Where:
# ### N = number of DIMMs used
# ### x denotes the multiplication specifier
# ### 
# ### 
# ### gg ss = size of each DIMM, including unit specifier
# ### 256 MB, 512 MB, 1 GB, 2 GB, 4 GB, 8 GB etc.
# ### 
# ### 
# ### pheR = p=number ranks; he=encoding for certain packaging, often blank
# ### 1R = 1 rank of DDR SDRAM installed
# ### 2R = 2 ranks
# ### 4R = 4 ranks
# ### 
# ### 
# ### xff = Device organization (bit width) of DDR SDRAMs used on this assembly
# ### x4 = x4 organization (4 DQ lines per SDRAM)
# ### x8 = x8 organization
# ### x16 = x16 organization
# ### 
# ### 
# ### PCy = Memory module technology standard
# ### PC4 = DDR4 SDRAM
# ### 
# ### 
# ### v = Module component supply voltage values: e.g. <blank> for 1.2V, L for Low Voltage (currently not defined)
# ### 
# ### 
# ### wwww = module speed in Mb/s/data pin: e.g. 1866, 2133, 2400
# ### 
# ### 
# ### aa = speed grade, e.g.
# ### J = 10-10-10
# ### K = 11-11-11
# ### L = 12-12-12
# ### M = 13-13-13
# ### N = 14-14-14
# ### P = 15-15-15
# ### R = 16-16-16
# ### U = 18-18-18
# ### 
# ### 
# ### m = Module Type
# ### E = Unbuffered DIMM ("UDIMM"), with ECC (x72 bit module data bus)
# ### L = Load Reduced DIMM ("LRDIMM")
# ### R = Registered DIMM ("RDIMM")
# ### S = Small Outline DIMM ("SO-DIMM")
# ### U = Unbuffered DIMM ("UDIMM"), no ECC (x64 bit module data bus)
# ### T = Unbuffered 72-bit small outline DIMM ("72b-SO-DIMM")

# Samsung DDR4 SDRAM Module Ordering
SAMSUNG_DDR4_JEDEC="
1 2 3-- 4 5-- 6 7 8 9 10  11 12-- 13
- - ___ - ___ - - - - -   -  ___ -
M X X X A X X X X X X X - X  X X X
1 - M - Memory Module
2 - DIMM Type
	3:DIMM
	4:SODIMM
3 - Data Bits
	71: x64 260pin Unbuffered SODIMM
	74: x72 260pin ECC Unbuffered SODIMM
	78: x64 288pin Unbuffered DIMM
	86: x72 288pin Load Reduced DIMM
	91: x72 288pin ECC Unbuffered DIMM
	92: x72 288pin VLP Registered DIMM
	93: x72 288pin Registered DIMM
4 - DRAM Component Type
	A: DDR4 SDRAM (1.2V VDD)
5 - Depth
	56 : 256M
	51 : 512M
	1G : 1G
	2G : 2G
	4G : 4G
	8G : 8G
	AG : 16G
	1K : 1G (for 8Gb)
	2K : 2G (for 8Gb)
	4K : 4G (for 8Gb)
	8K : 8G (for 8Gb)
	AK : 16G
6 - # of Banks in comp. & Interface
	4 : 16Banks & POD-1.2V
7 -  Bit Organization
	0 : x 4
	3 : x 8
	4 : x 16
8 - Component Revision
	M: 1st Gen.
	B: 3rd Gen.
	D: 5th Gen.
	F: 7th Gen.
	A: 2nd Gen.
	C: 4th Gen.
	E: 6th Gen.
	G: 8th Gen.
9 - Package
	B: FBGA (Halogen-free & Lead-free, Flip Chip)
	M: FBGA (Halogen-free & Lead-free, DDP)
	2: FBGA (Halogen-free & Lead-free, 2H TSV)
	3: FBGA (Halogen-free & Lead-free, 2H 3DS)
	4: FBGA (Halogen-free & Lead-free, 4H TSV)
	5: FBGA (Halogen-free & Lead-free, 4H 3DS)

10 - PCB Revision
	0: None
	1: 1st Rev.
	2: 2nd Rev.
	3: 3rd Rev
	4: 4th Rev
11 - Temp & Power
	C: Commercial Temp.(0°C ~ 85°C) & Normal Power
12 - Speed
	PB: DDR4-2133 (1066MHz @ CL=15, tRCD=15, tRP=15)
	RC: DDR4-2400 (1200MHz @ CL=17, tRCD=17, tRP=17)
	TD: DDR4-2666 (1333MHz @ CL=19, tRCD=19, tRP=19)
	RB: DDR4-2133 (1066MHz @ CL=17, tRCD=15, tRP=15)
	TC: DDR4-2400 (1200MHz @ CL=19, tRCD=17, tRP=17)
	WD: DDR4-2666 (1333MHz @ CL=22, tRCD=19, tRP=19)
	VF: DDR4-2933 (1466MHz @ CL=21, tRCD=21, tRP=21)
	WE: DDR4-3200 (1600MHz @ CL=22, tRCD=22, tRP=22)
	YF: DDR4-2933 (1466MHz @ CL=24, tRCD=21, tRP=21)
	AE: DDR4-3200 (1600MHz @ CL=26, tRCD=22, tRP=22)
13 - Bit Organization
	0 : x 4
	3 : x 8
	4 : x 16
"

# Micron Technology
MT_DDR4_JEDEC="
# 1- 2 3- 4 5- 6---- 7 8 - 9-- 10 11
# MT A 36 A SF 2G 72 P Z - 2G3 A 1

1 - MT Micron Technology

2 - Product Family
	A = DDR4 SDRAM

3 - Number of Die

4 - Voltage
	A = 1.2V

5 - Module Options
	TF = FBGA w/out Temp Sensor
	TS = Dual-Die w/out Temp Sensor
	TQ = Quad-Die w/out Temp Sensor
	SF = FBGA w/Temp Sensor
	SS = Dual-Die w/Temp Sensor
	SQ = Quad-Die w/Temp Sensor
	SE = Octal-Die w/Temp Sensor
	DF = VLP w/Temp Sensor
	DS = VLP Dual-Die w/Temp Sensor
	DQ = VLP Quad-Die w/Temp Sensor
	LF = 4U height with temp sensor
	LS = 4U height Dual-Die with temp sensor 
	LQ = 4U height Quad-Die with temp sensor
	LE = 4U height Octal-Die with temp sensor
	HF = 2U height with temp sensor
	HS = 2U height Dual-Die with temp sensor
	HQ = 2U height Quad-Die with temp sensor
	HE = 2U height Octal-Die with temp sensor
	SZF = FBGA w/Temp Sensor and Heat Spreader
	SZS = Dual-Die w/Temp Sensor and Heat Spreader
	SZQ = Quad-Die w/Temp Sensor and Heat Spreader
	SZE = Octal-Die w/Temp Sensor and Heat Spreader
	DZF = VLP w/Temp Sensor and Heat Spreader
	DZS = VLP Dual-Die w/Temp Sensor and Heat Spreader Module Type
	DZQ = VLP Quad-Die w/Temp Sensor and Heat Spreader

6 - Module Configuration
	Depth, Width
	Blank = Megabits
	G = Gigabits

7 - Module Type
	A = 288-pin UDIMM (unbuffered)
	H = 260-pin SODIMM
	L = 288-pin LRDIMM
	LS = 288-pin 3DS (M/S) LRDIMM
	P = 288-pin RDIMM
	PS = 288-pin 3DS (M/S) RDIMM
	AK = 288-pin miniUDIMM (unbuffered)
	PK = 288-pin miniRDIMM
8 - Package Codes
	Pb-Free Devices | Package Descriptions
	Z Commercial temp; halogen-free; single-, dual-, quad- or octal-rank DIMM
	DZ Commercial temp; halogen-free; select dual-, quad- or octal-rank DIMM
	DZM Commercial temp; Reduced Standby; halogen-free; select dual-, quad- or octal-rank DIMM
	IZ Industrial temp, halogen-free; single-, dual- or quad-rank DIMM
	TZ Industrial temp, halogen-free; select dual- or quad-rank DIMM
	ZM Commercial temp; Reduced Standby; halogen-free; single-, dual-, quad- or octal-rank DIMM

9 - DDR4 SDRAM Module Speed

	-2G1 -093E DDR4-2133 1067 2133 PC4-2133 15-15-15
	-2S1 -093H DDR4-2133 1067 2133 PC4-2133 18-15-15
	-2G3 -083 DDR4-2400 1200 2400 PC4-2400 17-17-17
	-2G4 -083E DDR4-2400 1200 2400 PC4-2400 16-16-16
	-2S3 -083H DDR4-2400 1200 2400 PC4-2400 20-18-18
	-2S4 -083J DDR4-2400 1200 2400 PC4-2400 19-17-17
	-2G6 -075 DDR4-2666 1333 2666 PC4-2666 19-19-19
	-2S6 -075H DDR4-2666 1333 2666 PC4-2666 22-19-19
	-2G7 -075E DDR4-2666 1333 2666 PC4-2666 18-18-18
	-2G9 -068 DDR4-2933 1467 2933 PC4-2933 21-21-21
	-2S9 -068H DDR4-2933 1467 2933 PC4-2933 24-21-21
	-3G2 -062E DDR4-3200 1600 3200 PC4-3200 22-22-22
	-3S2 -062H DDR4-3200 1600 3200 PC4-3200 26-22-22
	SPD = serial presence-detect pin (module only)

10 - Die Revision ( upto 2 characters )

11 - Printed Circuit Board Revision
"

declare -A jedec_conf

# No.of Dimms(N), Size of Each Dimm (Eg. 256 GB), eR (#R Rank),

jedec_conf["DDR4"]=PC4

collect_fields="Rank:"

jedec_conf["rank-by-org"]=${rank}x4

}

# SAMPLE TEST OPTION SETTING, PARSING
app_sample_test(){

	app_print_title "EXECUTING: $(app_get_fname ${BASH_SOURCE})"

	#multi_plot_opts
	APP_OPTIONS2="
	h=help${APP_DESC_DL}Print this help and exit.
	b:=bmc:${APP_DESC_DL}BMC IP
	j:=jbb-run-log:${APP_DESC_DL}SPECjbb Run Log file.
	o:=output:${APP_DESC_DL}Output filename for multiplot
	s:=collect-status-file:${APP_DESC_DL}Collection Status file
	t:=tool:${APP_DESC_DL}Tool/option name to collect metrics.
	"

	app_set_options #"${APP_OPTIONS}"
	
	app_parse_user_options $@
}
