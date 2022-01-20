#!/bin/bash
# Reference: https://www.codebyamir.com/blog/parse-command-line-arguments-using-getopt
THISFILE=$(basename ${BASH_SOURCE})
dbgf=debug.${THISFILE/.sh/}

set -ue

# SAVE INPUT ARGS
ARGS="$@" # Args to this script

[ -f "debug.*" ] && rm debug.*

app_DEBUG=0 # Default

[ $app_DEBUG -eq 2 ] && set -x && exec 2>$dbgf

# SOURCE GLOBAL VARIABLES & UTILITY FUNCTIONS SCRIPT: utilites.sh
# SOURCE POWER STATS SCRIPT: power-stats.sh
# SOURCE PACKAGE INSTALLATION SCRIPT: install-required.sh
# SOURCE TEST EXECUTIONS: test-executions.sh

req_files=( utilities.sh power-stats.sh plot-power-metrics.sh install-required.sh test-executions.sh )

source_wrapper(){
	for f in ${req_files[@]}
	do
		[ $DEBUG -eq 2 ] && echo "Sourcing: $f"
		[ ! -f $f ] && echo "[ $f ] File Not Found."
		source $f
	done
}

DIRECT_SOURCE=1

if [ $DIRECT_SOURCE -eq 1 ]
then
	eval set --
	for i in ${req_files[@]}
	do
		source $i
	done
	eval set -- $ARGS
else
	# Source using a function to avoid $@ to be passed as arguments while sourcing.
	source_wrapper
fi

#app_update_sut_info
#app_print_sut_info
#exit

app_benchmark(){
	APP_OPTIONS="
S=sysbench${APP_DESC_DL}Run Sysbench (CPU,File I/O,MySQL Benchmark)
R=redis${APP_DESC_DL}Run Redis Benchmark (In-Memory Database Benchmark)
N=nginx${APP_DESC_DL}Run NGINX Benchmark Test (Web Server Benchmark)
n=iperf${APP_DESC_DL}Run IPERF3 (Network Performance Test)
m=stream${APP_DESC_DL}Run STREAM Test (Memory Bandwidth Benchmark)
j=specjbb${APP_DESC_DL}Run SPECJBB Test (Micro Benchmark)
J:=jbb-home:${APP_DESC_DL}specJBB home directory
h=help${APP_DESC_DL}Print Option help and exit.
i:=install:${APP_DESC_DL}Install specified test.
d=sss-pts${APP_DESC_DL}Run SSS-PTS (Disk I/O Benchmark)
c=speccpu${APP_DESC_DL}Run SPECCPU Test (Micro BenchMark)
y=ycsb${APP_DESC_DL}Run YCSB Benchmark (Default - go-ycsb)
Y:=ycsb-home:${APP_DESC_DL}YCSB home directory
"	# End of App Options

	
	# Set the APP Options. This sets app_SHORT, app_LONG, app_DESC arrays
	app_set_options "$APP_OPTIONS"

	# PARSE USER INPUT OPTIONS AGAINST APP OPTIONS
	app_parse_user_options $@

	# Perform test executions
	tests_to_run=()

	# Use app_SHORT[], app_LONG[] arrays to build key and user set values;

	for key in ${!app_USER_SET_VALS[@]} 
	do
		case "$key" in

			v:,verbose: ) 
				# Do Nothing
				;;

			i:,install: )
				for i in ${app_USER_SET_VALS[$key]//,/ }
				do
					echo "Installing ${i}"

					# Call respective function name using the option values
					echo "install_${i}"
				done
				;;

			h,help )
				# Do Nothing as it is already provided as part of parsing options
				echo -e "$app_HELP"
				;;

			* ) 
				# Optional Argument requirement.

				# Generate test function name from long option by appending '_tests'
				# ASSUMING: function name is of the form 
				# --------------------------------------
				# <long_option>_tests(){...}
				# --------------------------
				
				# DEFAULT VALUE FOR "NOT SET"
				NOT_SET=-0

				if [[ "$key" == "j,specjbb" ]] || [[ "$key" == "J:,jbb-home:" ]]
				then
					echo "[ $(app_get_fname) ] Processing Option: $key"

#						jbb_home_cmdline=${app_USER_SET_VALS["J:,jbb-home:"]:-}
#						
#						if [ -z "${jbb_home_cmdline}" ]
#						then
#							echo "[ Error ] SPECJBB HOME Directory not provided."
#							exit
#						else
#							echo "[ JBB HOME ] $jbb_home_cmdline"
#							exec_fname="specjbb_tests"
#						fi

					# SPECJBB
					t_name=${app_USER_SET_VALS["j,specjbb"]:-$NOT_SET}
					t_home=${app_USER_SET_VALS["J:,jbb-home:"]:-${NOT_SET}}

					if [[ $t_name == $NOT_SET ]] || [[ $t_home == $NOT_SET ]]
					then
						
						[ $t_name == $NOT_SET ] && echo "SPECJBB Option [ -j,-specjbb ] Not Given."
						[ $t_home == $NOT_SET ] && echo "JBB HOME Directory Not Provided."
						#exit 1
					else
						jbb_home_cmdline=${app_USER_SET_VALS["J:,jbb-home:"]:-}
						echo "[ SPECJBB HOME ] $jbb_home_cmdline"
						tests_to_run+=( specjbb_tests )
					fi


				elif [[ "$key" == "y,ycsb" ]] || [[ "$key" == "Y:,ycsb-home:" ]]
				then
#						ycsb_home_cmdline=${app_USER_SET_VALS["Y:,ycsb-home:"]:-}
#						if [ -z "${ycsb_home_cmdline}" ]
#						then
#							echo "[ Error ] YCSB HOME Directory not provided."
#							exit
#						else
#							echo "[ YCSB HOME ] $ycsb_home_cmdline"
#							YCSB_HOME=$ycsb_home_cmdline
#							#exit
#						fi
#						exec_fname="ycsb_tests" 

					# SPECJBB
					t_name=${app_USER_SET_VALS["y,ycsb"]:-$NOT_SET}
					t_home=${app_USER_SET_VALS["Y:,ycsb-home:"]:-${NOT_SET}}

					if [[ $t_name == $NOT_SET ]] || [[ $t_home == $NOT_SET ]]
					then
						
						[ $t_name == $NOT_SET ] && echo "YCSBB Option [ -y,-ycsb ] Not Given."
						[ $t_home == $NOT_SET ] && echo "YCSB HOME Directory Not Provided."
						#exit 1
					else
						ycsb_home_cmdline=${app_USER_SET_VALS["Y:,ycsb-home:"]:-}
						YCSB_HOME=${ycsb_home_cmdline}
						echo "[ YCSB HOME ] $YCSB_HOME"
						tests_to_run+=( ycsb_tests )
					fi
				else
					tests_to_run+=("$(echo ${key##*,} | sed 's/$/_tests/g')")
				fi

				;;
		esac
	done

	# EXECUTE TESTS

	# Remove duplicate names
	tests_to_run=( $(echo ${tests_to_run[@]} | xargs -n1 | sort | uniq) )
	
	echo "[ TESTS TO RUN ] ${tests_to_run[@]}"

	for test_fname in ${tests_to_run[@]}
	do
		# CHECK if test function is in list of functions defined
		echo "${app_FUNCTIONS[@]}" | grep "$test_fname" >/dev/null && echo "Calling Test Function: $test_fname " || echo "[ $test_fname ] NOT-DEFINED" || return 1

		# RUN Test
		${test_fname}
	done
}

#----- STARTING THE TESTING PROCESS ----------------------

RUN_SAMPLE=0
if [ $RUN_SAMPLE -eq 1 ]
then
	app_sample_test "$@"
	exit 1
fi

[ $app_DEBUG -eq 4 ] && typeset -A

app_print_title "$APP_TITLE - $APP_VERSION"

app_update_sut_info

MAIN_HOME=$PWD
app_benchmark $@
exit
