#!/bin/bash
set -xue
THISFILE=${BASH_SOURCE}
readonly plt_dbgf=debug.$(basename ${THISFILE/.sh/})
exec 2> $plt_dbgf

VENDOR_MODEL=$(
	sudo ipmitool fru | egrep "Product Name|Product Manufacturer" | cut -f2 -d: | sed 's/^ *//g' | xargs |tr ' ' '_' 
	#sudo dmidecode -s system-manufacturer | xargs
)
#MODEL=$(sudo dmidecode -s system-product-name | xargs -n1 | xargs)
NUMA=$(lscpu | grep "NUMA node(" | sed 's/.*://g' | xargs)
CPU=$(lscpu | grep "Model name:" | cut -f2 -d: | xargs -n1 | xargs | tr -d '()@' | tr ' ' '_' |tr -s '_')

# Default values
OUT_TYPE=svg
OUTPUT=power-metrics-NUMA_$NUMA-$VENDOR_MODEL-$CPU

parse_plot_options(){
	
	this="${THISFILE}:${FUNCNAME[0]}()"

	[ -z "$(which gnuplot)" ] && echo "INSTALLING: gnuplot" && sudo apt-get install gnuplot -y

	declare -A plt_opt_map
	plt_opt_map["h"]="help"
	plt_opt_map["c:"]="config:"
	plt_opt_map["i:"]="input:"
	plt_opt_map["o:"]="output:"
	plt_opt_map["t:"]="plot-out-type:"
	plt_opt_map["j:"]="jbb-dir:"
	plt_opt_map["n:"]="rename-res-dir:"

	# SHORT
	SHORT=( $(printf "%s\n" ${!plt_opt_map[@]} | sort) )
	LONG=( $(for k in ${SHORT[@]};do echo "${plt_opt_map[$k]}";done) )

	help_msg="USAGE: $this <Options>\n"
	for idx in ${!SHORT[@]}
	do
		help_msg+="\t$(echo "-${SHORT[$idx]} | --${LONG[$idx]}" | sed 's/:/ <value>/g;')\n"
	done

	OPTS=$(getopt -o $(echo "${SHORT[@]}" | tr " " ",") -l $(echo ${LONG[@]} | tr ' ' ',') -n $this -- "$@" )

	eval set -- $OPTS

	# ---------------------------------------------AUTO GEN OPT SWITCH CASE ----------------------------------------------------------------
	AUTO_GEN_OPT_SWITCH=false
	declare -A default_val
	default_val[${plt_opt_map[h]}]="HELP"

	parse_cmd="
	eval set -- $OPTS
	while true
	do
		case \"\$1\" in
			$(
			_all_cases=""
			for i in ${!SHORT[@]}
			do
				_sopt="${SHORT[$i]}"
				_lopt="${LONG[$i]}"

				_case="
				$(
				if [ ! -z "$(echo "$_sopt" | tr -dc ':')" ]
				then
					echo "-$_sopt | --$_lopt) 
					VAR_${_lopt//-/_}=\$2; 
					shift 2;;
					" | tr -d ':'
				else
					echo "-$_sopt | --$_lopt) 
					VAR_${_lopt//-/_}=${default_val[$_lopt]};
					[[ \"$_sopt\" == h ]] || [[ \"$_sopt\" == help ]] && echo -e \"$help_msg\"
					shift ;;
					"
				fi
				)"
				_all_cases+="$_case"
			done

			echo "$_all_cases"
			)
			--) shift; break;;
			*) echo -e \"\$help_msg\"; shift; break;;
		esac
	done
	"
	[ "$AUTO_GEN_OPT_SWITCH" == "true" ] && eval "$parse_cmd" && exit
	# ----------------------------------------------------------------------------------------------------------------------------

	while true
	do
		case "$1" in
			--config | -c )
				config=$2
				shift 2;;
			--input | -i )
				IN_FILE=${2}
				shift 2;;
			--output | -o )
				OUTPUT=$2
				shift 2;;
			--plt-out-type | -t )
				PLT_OUT_TYPE=${2}
				shift 2;;
			--jbb-dir | -j )
				JBB_RES_DIR=$2
				shift 2;;
			--rename-res-dir | -n )
				RENAME_RES_DIR=$2
				shift 2;;
			--help | -h) 
				echo -e "$help_msg" 
				echo "PARSE-CMD:"
				echo "$parse_cmd"
				shift; exit;;
			--) 
				shift; break;;
			* )
				echo Invalid Option $1;
				echo -e "$help_msg";
				shift;
				break;;
		esac
	done
}

plot_graph(){

	# PARSE OPTIONS
	parse_plot_options $@

	INPUT_FILE=$IN_FILE
	
	[ -z "$INPUT_FILE" ] && echo "No input data provided." && exit

	# Convert CSV to space delimited
	csv_to_space=csv-to-space.txt
	cat $INPUT_FILE | tr ',' ' ' > $csv_to_space	# Requirement: No Comment lines in the content.
	INPUT_FILE=$csv_to_space

	OUTPUT_TYPE=${PLT_OUT_TYPE:-svg}
	OUTPUT_FILE=${OUTPUT:-OUTPUT}.${OUTPUT_TYPE}
	
	CANVAS_SIZE_RATIO=0.8,0.8
	GRAPH_SIZE=1500,850 #1386,786

	FIELDS_ARR=( $(cat $INPUT_FILE | grep -v "^#" | head -1) )
	FIELDS_CNT=${#FIELDS_ARR[@]}

	# Uniq number to select LineType, LineColor, PointType; limited to 1-9 of each type
	# lt:lc:pt 1-9:1-9:1-9
	LT_LC_PT=( $(shuf -i 111-999 -n$FIELDS_CNT) )	# NNN
	
	# lt:lc:pt 1-9:0-99:0-99
	LT_LC_PT2=( $(shuf -i 10101-99999 -n$FIELDS_CNT) )	# NNNNN

	JOPS="{/:Bold $(grep RESULT $JBB_RES_DIR/controller.out | sed 's/^.*max-jOPS/max-jOPS/g' | awk -F, '{print $2,$1}')}"

	TITLE="POWER UTILIZATION METRICS\n$JOPS ( NUMA = $NUMA ) \n( $CPU / $VENDOR_MODEL )"

	# X-Axis
	XLABEL="DATE\\\_TIME"
	TIME_FORMAT="%d-%m-%y_%H:%M:%S"
	XRANGE="$(rs=$(cat $INPUT_FILE | grep -v "^#" | head -2 | tail -1 | awk '{print $1}'); re=$(cat $INPUT_FILE | grep -v "^#" | tail -1 | awk '{print $1}'); echo '["'$rs'":"'$re'"]' )"

	# Y-Axis

	# Array to store "min,max,avg" values
	MIN_MAX_AVG_ARR=()
	MMA_LABEL='set label "Paramater (Min/Max/Avg)" right'
	for i in $(seq 2 $FIELDS_CNT )
	do
		# Get Min,Max,Avg of each column
		#set -x
		COLUMN="$(cat $INPUT_FILE | awk '{print $'$i'}')"
		COL_HEADER="$(echo "$COLUMN" | head -1 )"
	       	COLUMN_VALS="$(echo "$COLUMN" | tail -n+2 | sort -n)"
		COLUMN_NR="$(echo "$COLUMN_VALS" | xargs | awk '{print NF}')"

		if [ $COLUMN_NR -gt 0 ]
		then		
			#echo "COLUMN-$i [ $COL_HEADER / $COLUMN_NR ] : $COLUMN_VALS" | xargs
			#echo "COLUMN-$i: $(echo "$COLUMN_VALS" | awk '{OFS=",";s+=$1;if(NR==1){min=$1}}END{print min,$1,s/NR}')"
			
			[ $i -eq 0 ] && MIN_MAX_AVG_ARR=(Min,Max,Avg)
			[ $i -gt 0 ] && MIN_MAX_AVG_ARR+=($(echo "$COLUMN_VALS"| awk '{OFS=",";s+=$1;if(NR==1){min=$1}}END{print min,$1,s/NR}' ;))
		else
			echo "COL-$i $COL_HEADER Has no values."
		fi
	done

	# Line styles for each field
	LINE_STYLES="$(
	for i in $(seq 0 $((FIELDS_CNT-1)) )
	do
		COL_NUM=$((i+1))
		lvals=( $( echo ${LT_LC_PT[$i]} | grep -o . | xargs) )
		
		#USE_V2=Y	# Uses NNNNN format

		LT=${lvals[0]}
		LC=${lvals[1]}
		PT=${lvals[2]}
		
		if [ ! -z "$USE_V2" ]
		then
			LID=${LT_LC_PT2[$i]}
			
			LT=$(echo ${LID} | grep -o . | sed -n 1p)
			LC=$(echo ${LID} | sed 's/^.//g' | grep -o .. | sed -n 1p | sed 's/^0*//g')
			PT=$(echo ${LID} | sed 's/^.//g' | grep -o .. | sed -n 2p | sed 's/^0*//g')
		fi


		#echo "set style line $((i+1)) lt ${lvals[0]} lc ${lvals[1]} pt ${lvals[2]} ps 0.3 lw 0.4"
		#1>&2 echo -n "[COL: $COL_NUM] LT-LC-PT: $LT-$LC-$PT" 
		#[ $((i%9)) -eq 0 ] && 1>&2 echo "\n" 
		echo "set style line $COL_NUM lt $LT lc $LC pt $PT ps 0.3 lw 0.4"
	done
	)"

	# Plot function text
	PLOT="$(
	for f in $(seq 1 $((FIELDS_CNT-1)) )
	do
		#echo "'$INPUT_FILE' u 1:$f w lp ls $f t '$(echo ${FIELDS_ARR[$f]} | sed 's/_/\\\_/g') [ ${MIN_MAX_AVG_ARR[$((f-1))]//,/, } ]' $([ $f -lt $((FIELDS_CNT-1)) ] && echo ', \')"
		echo "'$INPUT_FILE' u 1:$f w lp ls $f t '$(echo ${FIELDS_ARR[$f]} | sed 's/_/\\\_/g') [ ${MIN_MAX_AVG_ARR[$((f-1))]//,/, } ]' $([ $f -lt $((FIELDS_CNT-1)) ] && echo ', \')"
	done
	)"

	# GENERATE PLOT COMMANDS FILE
	CONFIG_FILE=metrics.config

cat <<EOF > $CONFIG_FILE
# gnuplot script for Power Utilization Metrics data
set title "{/Times-New-Roman:Bold=15 $(echo $TITLE | sed 's/_/\\\\_/g')}" textcolor lt 2 # noenhanced

$LINE_STYLES

set autoscale
set grid xtics ytics
set xlabel "{/Times-New-Roman:Bold=15 ${XLABEL}}" 
set xtics rotate font "Times-New-Roman,12" noenhanced
set xdata time

set timefmt "$TIME_FORMAT"
set format x "$TIME_FORMAT"
set xr $XRANGE

set ytics noenhanced
set logscale y
#set autoscale y 
set ylabel "{/Times-New-Roman:Bold=15 Parameter Values (logscale)}" rotate left

$MMA_LABEL
#set key outside right font ""
set key autotitle columnheader outside bottom center samplen 5 font ",9" maxrows $((FIELDS_CNT/4)) 

#set size $CANVAS_SIZE_RATIO
set terminal $OUTPUT_TYPE size $GRAPH_SIZE font "Times-New-Roman,12" #noenhanced

#set terminal $OUTPUT_TYPE font "Times-New-Roman,12" #noenhanced

set output "$OUTPUT_FILE"

#EXAMPLE: plot "150p.txt" u 1:2 w l, '150p.txt' u 1:3 w l,'150p.txt' u 1:4 w l

plot $PLOT
EOF

echo Plot configuration file stored in: $CONFIG_FILE

echo generating Graph...
sleep 1

gnuplot $CONFIG_FILE
if [ $? -eq 0 ]
then
	echo Plotted graph stored in: $([ ! -z "$JBB_RES_DIR" ] && [ -d "$JBB_RES_DIR" ] && mv $OUTPUT_FILE $JBB_RES_DIR/$OUTPUT_FILE && echo "$JBB_RES_DIR/")$OUTPUT_FILE
fi


}

multi_plot(){

	app_log_stdout "[ $(app_get_fname) ] Generating Multi-Plot..."

	# PARSE OPTIONS
	parse_plot_options $@

	INPUT_FILE=${IN_FILE:-}

	[ ! -f ${INPUT_FILE} ] && echo "[ $(app_get_fname) ] Input File Not Found." && return 0

	metric_files=( $(app_get_sut_info "metricfiles") )

	[ ${#metric_files[@]} -eq 0 ] && metric_files=( $(echo ipmi.txt memory.txt turbo.txt load.txt pstrack.txt cpufreq.txt | xargs -n1 | sort | xargs) )

	MOVE_STAT_FILES=true	# Added below section in multiple-jbb-runs.sh

	if [ "$MOVE_STAT_FILES" == "true" ]
	then
		# Move metrics files to JBB result directory
		mv $INPUT_FILE $JBB_RES_DIR/
		
		for mf in ${metric_files[@]} 
		do
			#sed -i 's/,/ /g' $mf #$indi.txt

			[ $mf == ipmi.txt ] && [ $IPMI_PRESENT -eq 0 ] && echo "[ No IPMI ] Skipping $mf" && continue

			mv $mf $JBB_RES_DIR/ #${mf/.txt/spaced.txt}
		done
	fi

	# Goto JBB result directory and perform action
	pushd $JBB_RES_DIR
	#-----------------

	# TODO: If all file data to be presented as single plot graph, combine data from different files into one file.
	
	COMBINE_ALL_METRICS=false

	if [ "$COMBINE_ALL_METRICS" == "true" ]
	then
		COMBINED_OUTPUT=all-in-one-${OUTPUT}.txt

		paste_cmd="paste -d ' ' "

		cnt=1
		for mf in ${metric_files[@]} #$(printf "%s\n" ${!STATS_FILE[@]} | sort)
		do

			if [ $cnt -eq 1 ]
			then
				paste_cmd+="<(cat $mf) "
			else
				paste_cmd+="<(cat $mf | cut -f2- -d, ) "
			fi

			cat $mf | sed -i 's/,/ /g' | tee ${mf/.txt/spaced.txt}

			cnt=$((cnt+1))
		done
		
		eval "$paste_cmd" | tr ',' ' ' | tee ${COMBINED_OUTPUT} 

		stats_files=( $(ls *spaced.txt) )
	fi

	JOPS="{/:Bold $(grep RESULT controller.out | sed 's/^.*max-jOPS/max-jOPS/g' | awk -F, '{print $2,$1}')}"

	# Get count of Groups, TxInjectors
	GROUP_COUNT=$(ls Group*Back*.log | wc -l)
	TXI_PER_GROUP_COUNT=$(ls Group1*Tx*.log | wc -l)

	# Get Heap Settings
	HEAP_SETTINGS="$(grep "cmdline=" config/template-M.raw | cut -f2,3 -d'_')"
	CNTR_CMDLINE="$(echo -e "$HEAP_SETTINGS" | grep "Ctr_1" | cut -f2 -d'=' | xargs)"
	BE_CMDLINE="$(echo -e "$HEAP_SETTINGS" | grep "Backend_1" | cut -f2 -d'=' | xargs)"
	TXI_CMDLINE="$(echo -e "$HEAP_SETTINGS" | grep "TxInjector_1" | cut -f2 -d'=' | xargs)"

	MEM_CONF="$(app_get_sut_info memory | xargs -n1 | xargs)"
	
	# Generate Title of the Graph
	TITLE="{/Times-New-Roman:Bold=15 POWER UTILIZATION METRICS\n$JOPS \n( NUMA = $NUMA GROUPS = $GROUP_COUNT TxInjectors-Per-Group = $TXI_PER_GROUP_COUNT ) \nSUT-Memory: $MEM_CONF\nController: $CNTR_CMDLINE\nBackend: $BE_CMDLINE\nTxInjector: $TXI_CMDLINE\n( $CPU / $VENDOR_MODEL )}"

	# MULTIPLOT
	echo "MULTI-PLOT SECTION"

	MULTI_OUT_TYPE=svg
	MULTI_OUT_FILE=multi-plot-$OUTPUT.${MULTI_OUT_TYPE}

	# REPLACE COMMA WITH SPACE
	for f in ${metric_files[@]}
	do
		cat $f | sed 's/,/ /g' | tee ${f/.txt/-spaced.txt}
	done
	stats_files=( $(ls *spaced.txt | sort) )

	# Command / Configuration file to generate Multi Plot
	MULTI_CONF=multi-plot.plt
cat <<EOF > $MULTI_CONF
set autoscale
set grid xtics ytics

# output related settings
set key outside right noenhanced
set key outside bottom center maxrows 8 noenhanced
h=1248*2
w=h*1.4
set terminal svg size w,h
#set terminal svg size 2864,1264
set output '$MULTI_OUT_FILE'

#---------------- MULTI PLOT
r=3
c=2
mxsize=0.1
mysize=0.1

list = "${stats_files[@]}" # redfish"

total_files=words(list)
c=2
r=(total_files/c)+1

set multiplot layout r,c rowsfirst title "$(echo "$TITLE" | sed 's/_/\\\\_/g')" textcolor lt 2

do for [file in list]{
	filename=sprintf("%s",file)
	cmd="cat ".filename." | head -1 | xargs -n1 | wc -l"
	data_cols=system(cmd)

	fname_caps=system("echo ".filename." | tr [a-z] [A-Z]")
	set title "Metrics from: ".filename

	set xtics rotate font "Times-New-Roman,12" noenhanced
	set xdata time

	set timefmt "%d-%m-%y_%H:%M:%S"
	set format x "%d-%m-%y_%H:%M:%S"

	t1_cmd="cat ".file." | sed -n '2p' | awk '{print \$1}'"
	t2_cmd="cat ".file." | sed -n '\$p' | awk '{print \$1}'"
	t1=system(t1_cmd)
	t2=system(t2_cmd)
	set xr [t1:t2]

	set logscale y
	label_y=sprintf("Parameter Values (Logscale)")
	set ylabel label_y rotate

	# Change delimiter from , to space
	csv2ssv_cmd="sed -i 's/,/ /g' ".filename
	system(csv2ssv_cmd)

	# Min,Avg,Max
	mam_cmd="f=".filename." ; for i in \$(seq 1 ".(data_cols-1)."); do cat \$f | cut -f2- -d ' ' | awk '{print $'\$i'}' | tail -n+2 | cut -f2- -d' ' | sort -n | awk '{if(NR==1)print \$0;s+=\$1}END{print s/NR,\$0}' | xargs | tr ' ' ','; done | xargs "

	MAM_STR=system(mam_cmd)

	plot for [coln=2:data_cols ] filename u 1:coln w lp title columnhead(coln)." [ ".word(MAM_STR,coln-1)." ]"
}
EOF

	echo -e "[ $PWD ] Generating MULTI-PLOT: \n$MULTI_CONF | $MULTI_OUT_FILE"
	gnuplot $MULTI_CONF

popd

# RENAME RESULT DIRECTORY to easily identify test-configuration
# -----------
mv $JBB_RES_DIR $RENAME_RES_DIR

}

if [ $# -gt 0 ]
then
	#plot_graph $@

	multi_plot $@
	echo "[ Multi-Plot Generation ] DONE."
fi

