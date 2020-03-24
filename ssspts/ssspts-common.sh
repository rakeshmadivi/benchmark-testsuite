#!/bin/bash

THIS_SCRIPT=$0
#set -x

# Default values
#################################################
default_mix="100,95,65,50,35,5,0"	#w
default_blocks="4k,8k,16k,32k,64k,128k,1024k"	#b
default_skip_preconditioning=0	#c
default_skip_purge=0	#p
default_iodepth=1	#i
default_numjobs=1	#n
default_writepattern="0xfeed"	#t
default_activerange=100	#r
default_maxrounds=25	#m
default_runtime=1m	# No short option provided
#default_execute=1

ptsversion=1 #2	# 1-to use v1 ssspts variables; 2-to use v2 ssspts variables to check for steady state

# INITIALIZE USER OPTIONS WITH Default Values
#################################################
usr_rwmixwrite=$default_mix	#"100 95 65 50 35 5 0"	#w
usr_blocksizes=$default_blocks	#"4k 8k 16k 32k 64k 128k 1024k"	#b
usr_skip_preconditioning=$default_skip_preconditioning	#c
usr_skip_purge=$default_skip_purge	#p
usr_iodepth=$default_iodepth	#i
usr_numjobs=$default_numjobs	#n
usr_writepattern=$default_writepattern	#t
usr_activerange=$default_activerange	#r
usr_maxrounds=$default_maxrounds	#m
usr_runtime=$default_runtime
device=""	#d
execute=""	# You might want to assign default test

# STORE PROCESSED USER BLOCKS AND RWMIX 
#################################################
usr_mix=""
usr_blocks=""

# AVERAGE RESPONSE TIME,FIVE 9S, MAXIMUM RESPONSE TIMES (3.3 OF SECTION 9.2 IN SSSPTS PDF VERSION 2.0.1)
# Record AVG_RT, 5 9s, MAX_RT and IOPS
rtresult=response_times.json
rtfile=${testname}_rt.csv

# ARRAY TO STORE RESPONSE TIMES, FIVE9S PERCENTILES
rt=( iops clat.mean clat.percentile.\"99.99900\" clat.max ) 
rtnames=( IOPS "ART(mSec)" "99.999%(mSec)" "MRT(mSec)" ) 
rt_r=()
rt_w=()

# STORE RESUTANT VALUES TO OUTPUT JSON FOR THIS RUN
####################################################
store=()

################## EXECUTION LOG #############
# Run log
runlog=run.log

logit()	# $1: Module name, $2: Text to print
{
	echo "[`date`] $1 : $2" >> $runlog	
}

# CPU Usage
cpuusage()	# $1: Test name; $2: nproc; $3: no.of jobs
{
	logit "CPUUSAGE:" "mpstat nproc = ${2}, no.of jobs = $3"
	# Collects ALL CPU usage
	while true
	do
		mpstat | egrep -v "Linux|%" | awk -v np=$2 -v nj=$3 '{print $1,$2,$4,$6,$13,(100-$13)*(np/nj)}' | tr " " ","|grep -v ",,," >> ${1}.cpuusage.csv
		sleep 15	
	done
}

# DIE IF USER DIDN'T PROVIDE REQUIRED OPTIONS
#################################################
die() {
	echo "Error: " $@
	#show_tests
	
	echo "Eg: $0 -d /dev/<blockdev> -e 1	- For IOPS Test"
	exit 1
}

show_option_help()
{
echo -e "
USAGE: $0 [Options] <Option-value>
	OPTIONS:
	-d | --device	Device to be tested [Mandatory Option]
	-e | --execute	Test to be executed( Default: 1 - for IOPS; 2 - for TROUGHPUT; 3 - LATENCY ) [Mandatory Option]
	-h | --help	Show options and exit.
	-w | --rwmixwrite	ReadWrite Mix of Writes (Default: ${default_mix} )
	-b | --block-sizes	User provided block sizes (Default: ${default_blocks} )
	-c | --skip-preconditioning	Skip preconditioning (Default: Performs Pre-Conditioning)
	-p | --skip-purge	Skip Device purge operation (Default: Purges Device)
	-i | --iodepth	I/O Depth (Default: ${default_iodepth} )
	-n | --numjobs	Number of jobs to perform the test (Default: ${default_numjobs} )
	-t | --write-pattern	Pettern to fill IO Buffers content (Default: ${default_writepattern} )
	-r | --active-range	Address range of test operation (Default: ${default_activerange} )
	-m | --max-rounds	Max no.of rounds test to be executed (Default: ${default_maxrounds} )
	--run-time		Runtime for WDPC test stimulus (Default: ${default_runtime} )
"
exit 0;

	: '
	logit "HELP" "Removing created run directory"
	cd $work_dir
	rm -rf $run_dir

	logit "HELP" "Exiting."
	exit 0
	'
}

#--[ $# -ne 2 ] && die "Not enough arguments passed. Pass disk and test_id as arguments. "
# SHOW USER SET OPTIONS
#################################################
store_user_set_options()
{
	store+=(CONFIGURATION:VALUE)
	store+=(rwmixwrite:$usr_rwmixwrite)
	store+=(blocksizes:$usr_blocksizes)
	store+=(skip_preconditioning:$usr_skip_preconditioning)
	store+=(skip_purge:$usr_skip_purge)
	store+=(iodepth:$usr_iodepth)
	store+=(numjobs:$usr_numjobs)
	store+=(writepattern:$usr_writepattern)
	store+=(activerange:$usr_activerange)
	store+=(maxrounds:$usr_maxrounds)
	store+=(runtime:$usr_runtime)
	store+=(device:$device)
	store+=(execute:$execute)

	#for i in ${store[@]};do echo $i;done
}

format_user_input()
{

	logit "FORMAT USER INPUT" "Formatting user input for further process."
	# PROCESS USER GIVEN BLOCKS AND MIX
	if [ $ptsversion -eq 2  ]
	then
		usr_blocks=$(echo "$usr_blocksizes,4k,64k,1024k" | tr "," "\n" | sort -un | paste -d" " -s)
		usr_mix=$(echo "$usr_rwmixwrite,100,35,0" | tr "," "\n" | sort -unr | paste -d" " -s)
	else
		usr_blocks=$(echo "$usr_blocksizes,4k" | tr "," "\n" | sort -un | paste -d" " -s)
		usr_mix=$(echo "$usr_rwmixwrite,100" | tr "," "\n" | sort -unr | paste -d" " -s)
	fi

	logit "FORMAT USER INPUT" "usr_mix: $usr_mix usr_blocks: $usr_blocks"
}

# PARSING USER PROVIDED OPTIONS
#################################################
parse_options()
{
	#TEMP=`getopt -o h::w:b:c::p::i:n:t:r:m:d:e: --long help::,rwmixwrite:,block-sizes:,skip-preconditioning::,skip-purge::,iodepth:,numjobs:,write-pattern:,active-range:,max-rounds:,device:execute: --name $THIS_SCRIPT -- "$@"`
	TEMP=`getopt -o hw:b:cpi:n:t:r:m:d:e: --long help,rwmixwrite:,block-sizes:,skip-preconditioning,skip-purge,iodepth:,numjobs:,write-pattern:,active-range:,max-rounds:,device:,execute:,run-time: --name $THIS_SCRIPT -- "$@"`
	eval set -- "$TEMP"

	# extract options and their arguments into variables.
	while true ; do
		case "$1" in
			#0
			-h|--help) show_option_help;shift;;
			#1
			-w|--rwmixwrite)
				case "$2" in
					"")
						usr_rwmixwrite="NOTSET";	#${default_mix}; 
						shift 2;; 
					*) usr_rwmixwrite=$2; shift 2;;	#w
				esac ;;
			#2
			-b|--block-sizes)
				case "$2" in
					"") 
						usr_blocksizes="NOTSET";	#${default_blocks};	
						shift 2 ;;
					*) usr_blocksizes=$2; shift 2;;	#b
				esac ;;
			#3
			-c|--skip-preconditioning) usr_skip_preconditioning=1; shift;;
			
			#4
			-p|--skip-purge) usr_skip_purge=1; shift ;;
			
			#5
			-i|--iodepth)
				case "$2" in
					"") 
						usr_iodepth="NOTSET";	#${default_iodepth};	# Default value
						shift 2;; 
					*) usr_iodepth=$2 ; shift 2;;	#i
				esac ;;
			#6
			-n|--numjobs)
				case "$2" in
					"") 
						usr_numjobs="NOTSET";	#${default_numjobs};	#Default value
						shift 2;; 
					*) usr_numjobs=$2; shift 2;; 	#n
				esac ;;
			#7
			-t|--write-pattern)
				case "$2" in
					"") 
						usr_writepattern="NOTSET";	#${default_writepattern} ;	#---?- Default value
						shift 2;; 
					*) usr_writepattern=$2 ; shift 2;;	#t
				esac ;;
			#8
			-r|--active-range)
				case "$2" in
					"") 
						usr_activerange="NOTSET";	#${default_activerange}; #---?- Default value
						shift 2;; 
					*) usr_activerange=$2;shift 2;;	#r
				esac ;;
			#9
			-m|--max-rounds)
				case "$2" in
					"") 
						#die "Requires value for the option.";
						usr_maxrounds="NOTSET";	#${default_maxrounds} ;	# Default value ?
						shift 2;; 
					*) usr_maxrounds=$2 ; shift 2;;	#m
				esac ;;
			#10
			-d|--device)
				case "$2" in
					"") #shift 2;;
					device="NOTSET"; shift 2;;
					#die "Not enough arguments. -d|--device <Device> is a mandatory option.";;
					*) device=$2 ; shift 2;;	#d
				esac ;;
			#11
			-e|--execute)
				case "$2" in
					"") #shift 2;; 
					execute=1; shift 2;;	
					#die "Not enough arguments. -e|--execute <1|2> is mandatory option";;
					*) execute=$2 ; shift 2;;	#d
				esac ;;
			--run-time)
				case "$2" in
					"") #shift 2;; 
					execute=1; shift 2;;	
					#die "Not enough arguments. -e|--execute <1|2> is mandatory option";;
					*) usr_runtime=$2 ; shift 2;;	#d
				esac ;;
			--) shift ; break ;;
			
			#:) echo Missing ARGS;shift;;
				
			*) 
				echo "Internal error!" ;
				show_option_help
				exit 1 ;;
		esac
	done
}


#################################### CALL PARSING USER OPTIONS ###############################
parse_options $@

# CHECK IF DEVICE NAME IS GIVEN
[ -z $device ] && die "Requires device name to be tested.";

############################################## INITIALIZE TEST PARAMS WITH USER GIVEN PARAMS ########################

# -d | --device	Device to be tested\n
test_file=$device	#$1

# CHECK IF GIVEN DEVICE IS VALID BLOCK DEVICE
[ ! -z $device ] && [ ! -b $test_file ] && die "$test_file is not a valid block device. Pass '/dev/<block dev>'"

######################## WORK & RESULTS DIRECTORIES ###############
# Work Directory
work_dir=$PWD

[ -z $execute ] && echo -e "Option Error: Empty value for 'excute' option. Ex. --execute=<1|2|3>" && show_option_help && exit;
testname=`if [ $execute -eq 1 ];then echo iops;elif [ $execute -eq 2 ];then echo tp;elif [ $execute -eq 3 ];then echo latency;fi`
todotest=${testname}_run_

# Current Run Directory
run_n=`ls -d ${todotest}* > /dev/null 2>&1 && ls -d ${todotest}* | wc -w`
run_dir=`mktemp -d ${todotest}XXXXX_${usr_numjobs}J`	#${todotest}$((run_n + 1))

# CREATE RUN DIRECTORY
echo Run Directory: $run_dir
mkdir -p $run_dir
cd $run_dir
store+=(RESULT_DIRECTORY:$run_dir)

# JSON RESULTS
json_dir=json_results
mkdir -p ${json_dir}

date > $runlog
format_user_input >&2
store_user_set_options >&2

window_size=5	# Default value

# HOW LONG WE WANT TO RUN EACH TEST COMBINATION
run_time=$usr_runtime
#echo RUN_TIME: $run_time ; exit

# Initial status for steady state
STATUS=N

echo -e "TESTING: ${test_file} \nConsidering WINDOW_SIZE: $window_size" >> echolog;sleep 1;

prep_result=prep_result.json

# FILES TO BE WRITTEN AND READ

# FILE TO STORE ALL TESTING RESULT
datafile=${testname}_all_data.txt
olddf=old.${datafile}

# Debug file
debugfile=debug.$testname

# SUM FILE
sumfile=${testname}_sum_ss_window.txt
oldsf=old.${sumfile}

# FILE TO STORE ONLY WRITES
writesfile=onlywrites.txt
oldwf=old.${writesfile}

# FILE TO STORE AVG OF ALL ROUNDS
avgfile=${testname}_all_averages.txt
oldaf=old.${avgfile}

# FILE TO STORE CSV DATA
forexcel=${testname}_measurement_window_tabular_data.csv
oldexcel=old.${forexcel}

measurement_win=$forexcel
oldmeasurement_win=old.${measurement_win}

# FILE TO STORE ONLY 100% WRITES FOR EACH BLOCK IN ALL ROUNDS
w100percent=${testname}_ss_convergence_report.csv

# 3rd Plot
ss_4k_plot=${testname}_ss_measurement_window_plot.csv

# Steady State log
sslog=steadystate.log
# File to store intermediate Y values,bestfit slope,bestfit const,min,max,range,avg values.
ydata_file=ydata.txt

# User output
userout=user_requested_output.csv
store+=("USER_OUTPUT:${PWD}/$userout")

####################### THROUGHPUT FILES #############
# FILES		0	1		2		3		4				5		6
tp_files=(tp_data.txt tp_writes.txt tp_reads.txt tp_average.txt tp_ss_convergence.csv tp_ss_measurement_window.csv tp_measurement_window_tabular_data.csv )

aggrlog=aggr_values.log
echo "" > $aggrlog

##################################### TEST CONDITIONS/PARAMETERS SETTING ################################
# Test Conditions
# Disable volatile cache using direct=1, non-buffered io
DIRECT=1	# Default value
SYNC=1

# thread_count
NUMJOBS=$numjobs	#4

# FOR PREP STEP
wipc_rw_type=write  # Sequential read write

# For PREP STEP
wipc_bs=128k	# Default Value

# FOR TESTING STEP
wdpc_rw_type=randrw

IOENGINE=libaio
    
# Capacity 2X, BlockSize=128KiB, sequential write file_service_type=sequential
block_size=$(cat /sys/block/${test_file/\/dev\//}/size)
#size=$(( (($block_size * 512) / 1024 / 1024 / 1024 )  * 2 ))G
size=10M #4G
echo BLOCK_SIZE: $size

test -z `which jq` && echo "Installing 'jq' package..." && sudo apt-get install jq -y

#################################### FUNCTIONS #############################################

purge()
{
	#blkdiscard
	#OR
	sudo su -c "nvme format $device"
}

# Pass user options
# $1=Block sizes, $2=rwmix
generate_usr_requested()
{
	local _mix=`echo $2 | tr "," "\n"| sort -unr | paste -d" " -s`
	
	cols=$(echo `for i in $_mix ;do awk -F, -v ui="$((100-i))/$i" '{for(i=1;i<=NF;i++) {if($i==ui){print i}}}' $measurement_win ;done` | tr " " "\n" | paste -d, -s )
	
	#echo USER_COLS: $cols
	echo "BLK_SIZE,`for i in $_mix;do echo "$((100-i))/${i}";done | tr " " "\n" |paste -d, -s`">>$userout

	for i in $(echo $1 | tr "," "\n" | sort -un | paste -d" " -s) 
	do
		grep "$i" $measurement_win |cut -d, -f 1,$cols >> $userout
	done
}

####################### CHECK SS CONDITIONS ####################
# Arguments: $1:Y2 values, $2:Round
function check_ss_conditions()
{
	echo -n " "
	[ $# -eq 0 ] || [ "$1" = "" ] || [ "$2" = ""  ]
	if [ $? -eq 0 ];then logit "CHECK_SS_CONDITIONS" "Error: Invalid Argumets" ;echo No/Empty Arguments passed.;exit 1;fi

	y=(`echo ${1}|sed 's/"//g'`)
	#echo SED_CHECK: $1 =\> ${y[@]}; 
	ymean=$(echo "scale=2;$ysum / ${#y[@]}" | bc)
	
	# CONDITIONS TO CHECK
	maxY=${y[0]}	minY=${y[0]}
	
	for i in `seq 1 $((${#y[@]}-1))`;do 
		minY=$(awk -v n1="$minY" -v n2="${y[$i]}" 'BEGIN{ if(n2 < n1){print n2}else{print n1} }')
		maxY=$(awk -v n1="$maxY" -v n2="${y[$i]}" 'BEGIN{ if(n2 > n1){print n2}else{print n1} }')
	done;
	echo maxY:$maxY minY:$minY >> echolog

	#let rangeY=$maxY-$minY
	rangeY=`echo "$maxY-$minY"|bc`
	echo rangeY: $rangeY >> echolog

	echo Round Y Bestfit-slope Bestfit-const MinY MaxY rangeY YMean >> ${ydata_file}
	echo SS@$2 [`echo ${1}|sed 's/ /,/g'`] $BEST_SLOPE $BEST_CONST $minY $maxY $rangeY $ymean >> ${ydata_file}
	
	logit "CHECK_SS_CONDITION" "Round Y Bestfit-slope Bestfit-const MinY MaxY rangeY YMean"
	logit "CHECK_SS_CONDITOIN" "SS@$2 [`echo ${1}|sed 's/ /,/g'`] $BEST_SLOPE $BEST_CONST $minY $maxY $rangeY $ymean"

	export STATUS=`awk -v rangey="$rangeY" -v avgy="$ymean" -v slopey="$slope" 'BEGIN{ if( (rangey < 0.2*avgy) && (slopey < 0.1*avgy)){print "Y"} else{print "N"}  }'`

	[ "$STATUS" = "Y"  ]
	if [ $? -eq 0 ];then echo STEADY STATE REACHED IN ROUND-$2 >> echolog ;fi
}

######################## BEST-FIT FUNCTION ##############
function bestfit(){

	[ $# -eq 0 ] || [ "$1" = "" ] || [ "$2" = ""  ]
	if [ $? -eq 0 ];then logit "BEST_FIT" "Error: Invalid Arguments( Arg1: $1 Arg2: $2 )";echo No/Empty Arguments passed.;exit 1;fi
	echo Calculating Bestfit... >> echolog
	x=(`echo $1|sed 's/"//g'`)
	y=(`echo $2|sed 's/"//g'`)

	[ ${#x[@]} -ne 5 ] && [ ${#y[@]} -ne 5 ] && echo "Invalid Input X,Y sizes" && exit 1;
	#echo Recieved Input:
	#echo X2: ${x[@]}
	#echo Y2: ${y[@]}

	xtot=0
	ytot=0
	#for i in ${!x[@]};do let xtot+=${x[$i]};done
	#for i in ${!y[@]};do let ytot+=${y[$i]};done
	for i in ${!x[@]};do xtoto=$(echo "${xtot}+${x[$i]}" | bc );done
	for i in ${!y[@]};do ytot=$(echo "${ytot}+${y[$i]}" | bc );done
	echo xtot: $xtot ytot: $ytot >> echolog
		
	declare -a dA
	declare -a dB
	xsum=$xtot	#$(echo ${x[@]}| awk '{for(i=1;i<=NF;i++){sum+=$i}{print sum}}')
	ysum=$ytot	#$(echo ${y[@]}| awk '{for(i=1;i<=NF;i++){sum+=$i}{print sum}}')
	xmean=$(echo "scale=2;$xsum / ${#x[@]}" | bc)
	ymean=$(echo "scale=2;$ysum / ${#y[@]}" | bc)
	for i in ${!x[@]} ; do
		a=$(echo "scale=2;${x[$i]}-$xmean" | bc)
		b=$(echo "scale=2;${y[$i]}-$ymean" | bc)
		v1=$(echo "scale=2;$a * $b" | bc) #awk '{print $1 * $2}')
		#v1=$(echo $a * $b | awk '{print $1 * $2}')
		v2=$(echo "scale=2; (${x[$i]} - $xmean)^2" | bc)	#awk '{print ($1 - $2)**2}')
		dA[${#dA[@]}]=$v1
		dB[${#dB[@]}]=$v2
	done
	#
	#echo dA: ${dA[@]}
	#echo dB: ${dB[@]}

	mul=$(echo ${dA[@]}|sed 's/ /+/g'|bc) #$(dtot=0;for i in ${!dA[@]};do let dtot+=${dA[$i]};done;echo $dtot) 	#$(echo ${!dA[@]} | awk '{for(i=1;i<=NF;i++){sum+=$i} {print sum}}')
	xmeansq=$(echo ${dB[@]}|sed 's/ /+/g'|bc) 	#$(echo ${dB[@]} | awk '{for(i=1;i<=NF;i++){sum+=$i} {print sum}}')

	#echo CALCULATED: mul=$mul xmeansq:$xmeansq
	slope=$(echo "$mul $xmeansq" | awk '{printf "%f\n", $1/$2}')
	yinter=$(echo "$ymean $slope $xmean" | awk '{printf "%f\n", $1 - ($2 * $3)}')
	
	echo SLOPE:$slope CONST:$yinter >> echolog
	logit "BEST_FIT" "SLOPE:$slope CONST:$yinter"

	# Exporting SLOPE and CONSTANT of BESTFIT CURVE
	export BEST_SLOPE=$slope; export BEST_CONST=$yinter;
}

#bestfit

########################### CHECK STEADY STATE #######################
# Arguments to the fuction would be: rwmix% blksize round datafile
check_steady_state()
{
	end_iter=$3
	from=$((window_size-1))

	window=`seq $((end_iter-from)) $end_iter`
	echo Checking STEADY STATE for [ $1 $2 ] in WINDOW: ${window} >> echolog;
	
	rf=$4	#$datafile
	grepexpr=$(echo `for i in $window ;do echo "$1 $2 $i|";done`|sed -e 's/| /|^/g') #^100 4k 2|100 4k 3|100 4k 4"
	#echo CHECK STRING: $grepexpr
	check=${grepexpr::-1}

	#egrep "^[0] 128k 1|^[0] 128k 2|^[0] 128k 3|^[0] 128k 4|^[0] 128k 5" 
	check2=$(echo $check|sed 's/|/|^/g')
	echo check2: $check2 >> echolog

	echo Checking: $check >> echolog
	export SS_WINDOW=$check

	echo Retrieving X and Y Coordinates... >> echolog
	#set -x
	# Read Iteration Value
	x1=$(echo `egrep "^${check2}" $rf |awk '{print $3}'`|sed -e 's/ /,/g'|tr -d ' ')
	echo CHECK: GETTING PROPER VALUES: >> echolog
	echo `egrep "^${check2}" $rf |awk '{print $3}'`|sed -e 's/ /,/g'|tr -d ' ' >> echolog

	# Read Write Ops from datafile
	writes=$(echo `egrep "^${check2}" $rf |awk -v r=$1 '{if(r != 0)print $5;else print $4}'`|sed -e 's/ /,/g'|tr -d ' ')
	

	[ $1 -eq 0 ] && reads=$(echo `egrep "^${check2}" $rf |awk '{print $4}'`|sed -e 's/ /,/g'|tr -d ' ')
	echo Reads: $reads >> echolog

	local _iops=$(echo `egrep "^${check2}" $rf | awk '{print $6}'`|tr " " "\n"|tr "\n" " ")

	echo X1: $x1  >> echolog
	#echo Y1w: $writes >> echolog
	echo Y1w: $_iops >> echolog

	# Using bestfit() function
	x2=$(echo `egrep "^${check}" $rf | awk '{print $3}'`)
	y2=$(echo `egrep "^${check2}" $rf | awk '{print $6}'`|tr " " "\n"|tr "\n" " ")
	#y2=$_iops	#$(echo `egrep "^${check}" $rf |awk -v r=$1 '{if(r != 0)print $5;else print $4}'`)
	
	logit "CHECK_SS_STATE" "Calling  bash_bestfit() with X: $x2 Y: $y2" #>> echolog
	bestfit "$x2" "$y2"

	# Using python script for best fit
	# IF PYTHON SCRIPT TO BE CALLED UNCOMMENT FOLLOWING 2 LINES and COMMENT THE LINE READING 'STATUS' variable.
	#python best_fit.py $x1 $writes $2
	#status=$(if [ $? -eq 0 ];then echo Y;else echo N;fi)

	# CALL STEADY STATE CONDITIONS CHECK
	check_ss_conditions "$y2" $end_iter

	# IF FOUND STEADY STATE STOP THE RUN
	if [ "$STATUS" = "Y" ]
	then
		export YDATA="$y2"; export SS_ROUND=$3;
		echo SS_ROUND: $SS_ROUND YDATA: $YDATA >> echolog
		echo SS@$round [$1,$2,`echo $window|tr " " "-"`] [`echo $y2|tr " " ","`] $BEST_SLOPE $BEST_CONST >> $sslog
		echo "Steady state reached at Round: $3 ... Stopping run now...\n" >> echolog
		#export STOP_NOW=y
		return 0;
	else
		return 1;
	fi
}

############################ [ IOPS TEST ] #############################
############################ IOPS POST RUN #######################
post_run()
{
	set -x
	tname=$(echo $testname | tr [:lower:] [:upper:])
	
	echo -e "\nPerforming post run data formatting...\n" >> echolog
	# GET ONLY WRITES
	echo Retrieving only writes... >> echolog
	#awk '{print $1" "$2" "$3" "$5}' $datafile > $writesfile
	awk '{print $1" "$2" "$3" "$6}' $datafile > $writesfile

	# SUM: write READS+WRITES of SS WINDOW to sumfile.
	rm -rf $sumfile
	win_frm=$((SS_ROUND - $((window_size - 1))))
	for i in `seq $win_frm  $SS_ROUND`
	do
		#egrep "k $i " $datafile | awk -v iter=$i '{sum=$4+$5;print $1" "$2" "$3" "sum}' >> ${sumfile}
		awk -v iter=$i '{if($3==iter)print $1" "$2" "$3" "$6}' $datafile >> ${sumfile}
	done
	#echo Done creating sums file...;exit

	rm -rf $w100percent

	tf=temp.txt
	rm -rf $tf

	logit "POST_RUN($tname)" "Generating SS Convergence Report."

	echo Generating Data for $tname Steady State Convergence Plot \[All Block Sizes\]... >> echolog
	echo Round,`echo ${usr_blocks}|tr " " "\n" | paste -d, -s` > $w100percent
	for i in `seq  $((SS_ROUND - $((window_size - 1)))) $SS_ROUND`
	do 
		#echo -n "$i," >> $w100percent #$tf
		{
			echo "$i" 
			for j in $usr_blocks	
			do 
				#grep "^100 ${j} ${i} " $writesfile|awk '{print $4}'
				grep "^100 ${j} ${i} " $sumfile|awk '{print $4}'
			done
		}|tr " " "\n"|paste -d, -s >> $w100percent
	done

	logit "POST_RUN($tname)" "Calculating Averages of SS Window."
	echo "Calculating Average of all rounds..." >> echolog
	for i in ${usr_mix}	#100 95 65 50 35 5 0
	do 
		for j in ${usr_blocks}	#4k 8k 16k 32k 64k 128k 1024k
		do 
			echo -n "${i} ${j} " >> $avgfile 
			echo `grep "^${i} ${j} " ${sumfile} |awk '{sum+=$4} END {print sum / NR}'` >> $avgfile
		done
	done

	logit "POST_RUN($tname)" "Generating  Measurement Window Tabular Data."
	echo Generating $tname Measurement Window Tabular Data \[ All RWMix, Block Sizes \]... >> echolog
	echo RW_MIX,`echo ${usr_mix}|awk '{for(i=1;i<=NF;i++) print 100-$i"/"$i}' | tr " " "\n" |paste -d, -s` > $forexcel
	for i in ${usr_blocks}	
	do 
		echo -n "${i}," >>$forexcel
		local avgs=$(grep " ${i} " $avgfile |awk '{print $3}'|tr " " "\n"|paste -d, -s)
		logit "POST_RUN($tname)" "Averages($i): $avgs"
		echo $avgs >> $forexcel
	done
	
	#echo "Measurement Window tabular Data File:" $(pwd)/$forexcel
	store+=("Measurement_Window_Tabular_Data_File:$(pwd)/$forexcel")

	logit "POST_RUN($tname)" "Generating SS Plot."
	echo "Round,100%w-IOPS,100%-Avg,110%-Avg,90%-Avg,Best_fit" >> $ss_4k_plot
	fldnum=`head -n1 $w100percent | awk -F, '{for(i=1;i<=NF;i++){if($i=="4k"){print i}}}'`
	avg=$(grep -v "k" $w100percent |awk -F ',' -v f=$fldnum '{sum+=$f}END{print sum/NR}')
	cnt=$win_frm #1
	best_m=$(tail -n-1 ${ydata_file} | awk '{print $3}')
	best_c=$(tail -n-1 ${ydata_file} | awk '{print $4}')

	for i in `echo  $(grep -v "k" $w100percent |awk -F ',' -v f=$fldnum '{print $f}')`  
	do
		w110p=`echo "1.1 * $avg" | bc`
		w90p=`echo "0.9 * $avg"|bc`
		bestfit_val=$(echo "(${best_m}*${cnt})+${best_c}"|bc)	# y=mx+c
		echo "$cnt,$i,$avg,$w110p,$w90p,${bestfit_val}" >> $ss_4k_plot
		cnt=$((cnt+1))
	done

	# IF IT IS LATENCY TEST, CAPTURE AVGRT,5 9S,MAXRT, IOPS
	if [ "$testname" = "latency" ]
	then
		lat_tab_file=${tname}_measurement_window_tabular_data.csv
		#logit "POST_RUN($tname)" "Calculating Averages IOPS, ART, 5 9s, MRT of SS Window."
		logit "POST_RUN($tname)" "Generating LAT Measurement Window Tabular Data"
		
		echo "Calculating Averages of ALL RWMix,ALL Blocks for SS rounds..." >> echolog
		
		echo VAR RW-W% ${usr_blocks}|tr " " "," > $lat_tab_file 
		for idx in ${!rt[@]}
		do 
			echo Generating for : ${rt[$idx]}
			for _mix in ${usr_mix}
			do
				{	
					echo ${rtnames[$idx]} $_mix
					for _blk in ${usr_blocks}
					do
						#echo == $idx,$_mix,$_blk == >> ${testname}_tab_data.txt
						{
							for i in `seq $win_frm  $SS_ROUND`
							do
								grep "^$_mix $_blk $i " $datafile | awk '{print $5" "$7" "$8" "$9}'
							done
						} | awk -v idx=$idx '{sum+=$idx}END{print sum/(1000*NR)}' #
					done
				}|tr " " "\n"| paste -d, -s >> $lat_tab_file 

			done
		done
	fi
	set +x
}

