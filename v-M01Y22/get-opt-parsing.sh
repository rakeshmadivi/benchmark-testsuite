#!/bin/bash

echo "ARGS to this ($0) script: $@"

PROG_NAME=$0
l_opts=(help speccpu specjbb stream sss-pts netperf sysbench redis nginx install: install-home: execute:)	# short options like -a,-b <value>
s_opts=(h c j m d n M R N i: I: E:)	# long options like --long, --long-option <value>

# Above lines makes up <program-name> <options>

chelp(){
	echo -e "
	-c | --speccpu \t Run SPECCPU Test (Micro BenchMark)
	-j | --specjbb \t Run SPECJBB Test (Micro Benchmark)
	-m | --stream \t Run STREAM Test (Memory Bandwidth Benchmark)
	-d | --sss-pts \t Run SSS-PTS (Disk I/O Benchmark)
	-n | --iperf \t Run IPERF3 (Network Performance Test)
	-M | --sysbench \t Run Sysbench (CPU,File I/O,MySQL Benchmark)
	-R | --redis \t Run Redis Benchmark (In-Memory Database Benchmark)
	-N | --nginx \t Run NGINX Benchmark Test (Web Server Benchmark)
	-i | --install <app1,app2,..appN>\t Install application
	-I | --install-home\t Install Location
	-E | --execute <app1,app2...appN>\t Run requested application from above options."
	exit
}

s_opts_size=${#s_opts[@]}
l_opts_size=${#l_opts[@]}

[ $s_opts_size -ne $l_opts_size ] && echo "All short options doesn't have respective long options!." && exit

SHORT=$(echo ${s_opts[@]} | tr ' ' ',')
LONG=$(echo ${l_opts[@]} | tr ' ' ',')

echo -e "SHORT: $SHORT \nLONG: $LONG"

ARGS=$(getopt -n $PROG_NAME -o $SHORT -l $LONG -- "$@")
[ $? -ne 0 ] && exit

#set -x
echo Arguments from getopt : $ARGS

eval set -- $ARGS

echo After eval set: $@

INSTALL_LIST=()
RUN_LIST=()
EXECUTE_LIST=()

while true
do
	case "$1" in
		-h | --help) 
			chelp 
			shift;;
		-c | --speccpu ) #starting spec-cpu
			RUN_LIST+=(speccpu)
			shift;;

		-j | --specjbb ) #starting spec-jbb
			RUN_LIST+=(specjbb)
			shift;;

		-m | --stream )	#starting stream
			RUN_LIST+=(stream)
			shift;;

		-d | --sss-pts ) #starting sss-pts
			RUN_LIST+=(sss-pts)
			shift;;

		-n | --netperf ) #starting netperf
			RUN_LIST+=(netperf)
			shift;;

		-M | --sysbench ) #starting sysbench
			RUN_LIST+=(sysbench)
			shift;;

		-R | --redis ) #starting redis
			RUN_LIST+=(redis)
			shift;;

		-N | --nginx ) #starting nginx
			RUN_LIST+=(nginx)
			shift;;

		-i | --install ) #starting Instalation of $2
			[ -z "$2" ] && chelp
			INSTALL_LIST+=($(echo "$2" | tr ',' ' ' | xargs))
			shift 2;;

		-I | --install-home )
			[ -z "$2" ] && chelp
			INSTALL_HOME=${2:-benchmark-install-home}
			shift 2;;

		-E | --execute )
			[ -z "$2" ] && chelp
			EXECUTE_LIST+=($(echo "$2" | tr ',' ' '))
			shift 2;;

		--) shift;break
			;;

		* ) 
			echo "Invalid Option: $1"
			chelp
			break;;
	esac
done


echo "RUN_LIST: ${RUN_LIST[@]}"
echo "INSTALL_LIST: ${INSTALL_LIST[@]}"
echo "EXECUTE_LIST: ${EXECUTE_LIST[@]}"

[ -z "${RUN_LIST[@]}" ] && [ -z "${EXECUTE_LIST[@]}" ] && echo "No RUN LIST provided."

[ ! -z "${INSTALL_LIST[@]}" ] && ACTION=install

check_if_installed(){
	[ $# -ne 1 ] && echo  "Require <test-name> as argument." && return 1
	
	MSG_PREFIX="[ INSTALLATION-CHECK ]"

	[ ! -f $INSTALL_HOME ] && echo "$MSG_PREFIX No Installations Found. Missing '$INSTALL_HOME' directory."

	#for i in $@
	#do
		[ ! -f ${INSTALL_HOME}/$1/install.status ] && echo "$MSG_PREFIX $i Not Installed." && return 1
	#done
	return 0
}

Benchmark(){
	[ $# -ne 1 ] && echo  "Require <install | run> <test-name> as argument." && return 1
	
	MSG_PREFIX="[ INSTALLATION ]"

	ACTION=$1
	TARGET=$2

	echo ACTION: $ACTION TARGET: $TARGET

	case "$TARGET" in
		speccpu)
			${ACTION}_SPECCPU
			;;
		specjbb)
			${ACTION}_SPECJBB
			;;
		stream)
			${ACTION}_STREAM
			;;
		sss-pts)
			${ACTION}_SSSPTS
			;;
		netperf)
			${ACTION}_NETPERF
			;;
		redis)
			${ACTION}_REDIS
			;;
		sysbench)
			${ACTION}_SYSBENCH
			;;
		nginx)
			${ACTION}_NGINX
			;;
		*)
			echo "Invalid test: $TARGET"
			return 1
			;;
	esac

}

# For given tests check if they are already installed.
SKIPPED=()
for t in ${RUN_LIST[@]} ${EXECUTE_LIST[@]}
do
	check_if_installed $t
	
	[ $? -ne 0 ] && echo "$t: Not Installed. Skipping test." && SKIPPED+=($t) && continue
	
	Benchmark run $t
done

echo SKIPPED: ${SKIPPED[@]}


#set +x
