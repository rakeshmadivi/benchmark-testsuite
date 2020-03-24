#!/bin/bash
# Reference: https://www.codebyamir.com/blog/parse-command-line-arguments-using-getopt
#set -x 
chelp(){
	echo -e "
	-c | --speccpu \t Run SPECCPU Test (Micro BenchMark)
	-j | --specjbb \t Run SPECJBB Test (Micro Benchmark)
	-m | --stream \t Run STREAM Test (Memory Bandwidth Benchmark)
	-d | --sss-pts \t Run SSS-PTS (Disk I/O Benchmark)
	-n | --iperf \t Run IPERF3 (Network Performance Test)
	-M | --sysbench \t Run Sysbench (CPU,File I/O,MySQL Benchmark)
	-R | --redis \t Run Redis Benchmark (In-Memory Database Benchmark)
	-N | --nginx \t Run NGINX Benchmark Test (Web Server Benchmark)"

	: '
	long=(${LONG//,/ });
	for i in $(seq 0 $(expr ${#1} - 1))
	do
		echo "-${1:$i:1} ${long[$i]}"
	done
	'
	exit
}
[ $# -eq 0 ] && echo -e "Error: Invalid no.of arguments" && chelp

# SOURCE ALL GLOBAL VARIABLES
source global-variables

# SOURCE POWER STATS SCRIPT
source power-stats.sh

# SOURCE PACKAGE INSTALLATION SCRIPT
source install-required.sh

# SOURCE TEST EXECUTIONS
source test-executions.sh

check_if_all_files_exists(){
	hdir=${PWD}
	echo CHECKING DIRECTORIES: ${directories[@]}
	for i in ${!directories[@]}
	do
		local cdir=${directories[$i]}
		if [ $cdir = "ssspts" ]
		then
			local pat=${hdir}/${cdir}/${cdir} # pattern to match Eg: $PWD/ssspts/ssspts-*.sh
			[ -f ${pat}-test.sh ] && [ -f ${pat}-main.sh ] && [ -f ${pat}-common.sh ] && [ -f ${pat}-iops.sh ] && [ -f ${pat}-tp.sh ] && [ -f ${pat}-latency.sh ]
			return $?
		else
			[ -f ${hdir}/${cdir}/${cdir}-test.sh ]
			return $?
		fi
	done
}

starting(){
	echo Preparing to run... ${@^^}
}

# actions=()	-> Moved to global-variables.sh

check_for_installation(){
	for i in $@
	do
		ifinstalled $i
		[ ! $? -eq 0 ] && tobeinstalled+=($i)
	done
	local n=${#tobeinstalled[@]}
	return $n
}

display_install_candidates(){
	echo Following sofware are going to be installed:
	for i in $@
	do
		echo -e "\t${longopts[$i]}"
	done
}

#: '
parse(){
	if [ $# -eq 0 ]
	then
		echo -e "Error: no install/test action provided to proceed.\nEx. $0 <Test-Name>";
		chelp;
		exit
	fi

	OPTS=$(getopt --options $SHORT --long $LONG --name $0 -- "$@")

	eval set -- $OPTS
	#set +x

	while true
	do
		#echo Checking $1
		case $1 in
			-h | --help) 
				chelp $SHORT $LONG
				shift;;
			-c | --speccpu ) #starting spec-cpu
				actions+=(0)
				shift;;

			-j | --specjbb ) #starting spec-jbb
				actions+=(1)
				shift;;

			-m | --stream )	#starting stream
				actions+=(2)
				shift;;

			-d | --sss-pts ) #starting sss-pts
				actions+=(3)
				shift;;

			-n | --iperf ) #starting iperf
				actions+=(4)
				shift;;

			-M | --sysbench ) #starting sysbench
				actions+=(5)
				shift;;

			-R | --redis ) #starting redis
				actions+=(6)
				shift;;

			-N | --nginx ) #starting nginx
				actions+=(7)
				shift;;
			-i | --install ) #starting Instalation of $2
				# Call Install for $2
				install $2
				shift;;
			--) shift;break
				;;
			#*) echo "STAR";break;;
		esac
	done
}

# Perform User Requested Action/Operation
# @arg1 id-of-user-action
perform_actions(){
	for i in $@
	do
		testfunction=${test_fun[$i]}
		echo PREPARING FOR TEST: $testfunction
		sleep 2
		$testfunction	
	done
}

#'
#----- STARTING THE TESTING PROCESS ----------------------
# Checking if required files are present in current directory
check_if_all_files_exists
[ $? -ne 0 ] && echo Error: Required files are not present. && exit;

# Parse the user options
parse $@

# Check if any software needs to be installed
check_for_installation ${actions[@]}
if [ $? -ne 0 ]
then
	display_install_candidates ${tobeinstalled[@]}
	#exit
	install ${tobeinstalled[@]}
else
	echo No installations required. Good to go
fi

# Perform user requested Tests
perform_actions ${actions[@]}

