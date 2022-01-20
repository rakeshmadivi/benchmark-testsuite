#!/bin/bash

line_styles='
set style line 1 lt 1 lw 0.3 pt 1 ps 0.9 lc  rgb "navy" pi -1
set style line 2 lt 1 lw 0.3 pt 2 ps 0.3 lc  rgb "red" pi -1
set style line 3 lt 1 lw 0.3 pt 3 ps 0.3 lc  rgb "blue" pi -1
set style line 4 lt 1 lw 0.3 pt 4 ps 0.3 lc  rgb "olive" pi -1
set style line 5 lt 1 lw 0.3 pt 5 ps 0.3 lc  rgb "black" pi -1
set style line 6 lt 1 lw 0.3 pt 6 ps 0.3 lc  rgb "gray20" pi -1
set style line 7 lt 1 lw 0.3 pt 7 ps 0.3 lc  rgb "cyan" pi -1
'
parse_plot_options(){
	OPTS=$(getopt -o c:,i:,o:,t:,d: -l config:,input:,output:,output-type:,out-dir -n $0 -- "$@" )

	eval set -- $OPTS

	#echo $# : $@
	help_msg="Usage: $0 -c|--config <conf-name> -i|--input <input-data-file> -o|--output <output-file-name> -t|--output-type <png,svg(default)> -d|--out-dir <output-dir>"
	[ $# -eq 1 ] && echo  $help_msg && exit;

	# Default values
	OUTPUT=power-metrics
	OUT_TYPE=svg

	while true
	do
		case "$1" in
			--config | -c )
				config=$2
				shift 2;;
			--input | -i )
				INPUT=$2
				shift 2;;
			--output | -o )
				OUTPUT=$2
				shift 2;;
			--output-type | -t )
				OUT_TYPE=${2}
				shift 2;;
			--out-dir | -d )
				OUT_DIR=$2
				shift 2;;
			-- ) 
				echo "$help_msg" 
				shift; break;;
			* )
				echo Invalid Option $1;
				echo "$help_msg";
				shift;
				break;;
		esac
	done
}


generate_power_metrics_graph(){

colors=(
'#0072bd' # blue
'#d95319' # orange
'#edb120' # yellow
'#7e2f8e' # purple
'#77ac30' # green
'#4dbeee' # light-blue
'#a2142f' # red
	)
dash_types=(- _ . ... '-...')
dt_size=${#dash_types[@]}
}

plot_graph(){

	INPUT_DATA=$INPUT
	[ -z "$INPUT_DATA" ] && echo "No input data provided." && exit

	# Store only content without comments within data file
	DATA="$(cat $INPUT_DATA | grep -v "^#")"

	OUTPUT_TYPE=$OUT_TYPE
	OUTPUT_FILE=$OUTPUT.$OUTPUT_TYPE
	GRAPH_SIZE=1386,786

	FIELDS_ARR=( $(cat $INPUT_DATA | grep -v "^#" | head -1) )
	FIELDS_CNT=${#FIELDS_ARR[@]}

	# Uniq number to select LineType, LineColor, PointType; limited to 1-9 of each type
	# lt:lc:pt 1-9:1-9:1-9
	LT_LC_PT=( $(shuf -i 111-999 -n$FIELDS_CNT) )

	VENDOR=$(sudo dmidecode -s system-manufacturer | xargs)
	MODEL=$(sudo dmidecode -s system-product-name | xargs -n1 | xargs)
	CPU=$(lscpu | grep "Model name:" | xargs | cut -f2 -d:) # xargs -n1 | xargs)

	# Get critical-jOPS, max-jOPS from OUT_DIR
	jops=$(grep "RESULT" $OUT_DIR/controller.out | sed 's/^.*max-jOPS/max-jOPS/g' | cut -f2,1 -d,)

	TITLE="POWER METRICS ( $CPU / $MODEL / $VENDOR ) "

	# X-Axis
	XLABEL=DATE_TIME
	TIME_FORMAT="%d-%m-%y_%H:%M:%S"
	XRANGE="$(rs=$(cat $INPUT_DATA | grep -v "^#" | head -2 | tail -1 | awk '{print $1}'); re=$(cat $INPUT_DATA | grep -v "^#" | tail -1 | awk '{print $1}'); echo '["'$rs'":"'$re'"]' )"

	# Y-Axis

	# Line styles for each field
	LINE_STYLES="$(
	for i in $(seq 0 $((FIELDS_CNT-1)) )
	do
		lvals=( $( echo ${LT_LC_PT[$i]} | grep -o . | xargs) )
		#echo "set style line $((i+1)) lt ${lvals[0]} lc ${lvals[1]} pt ${lvals[2]} ps 0.3 lw 0.4 "

		# Get Min,Max Values of current column


		echo "set style line $((i+1)) lt 1 lc ${lvals[1]} pt ${lvals[2]} ps 0.3 lw 0.4 "
	done
	)"

	# Plot function text
	PLOT="$(
	for f in $(seq 2 $((FIELDS_CNT-1)) )
	do
		echo "'$INPUT_DATA' u 1:$f ls $f t '${FIELDS_ARR[$f]}' $([ $f -lt $((FIELDS_CNT-1)) ] && echo ', \')"
	done
	)"

	# GENERATE PLOT COMMANDS FILE
	CONFIG_FILE=metrics.config

cat <<EOF > $CONFIG_FILE
# gnuplot script for Power Utilization Metrics data
set title "$TITLE" textcolor lt 2

set termoption noenhanced

$LINE_STYLES

set autoscale
set grid xtics ytics
set xlabel noenhanced "$XLABEL" 
set xtics rotate
set xdata time

set timefmt "$TIME_FORMAT"
set format x "$TIME_FORMAT"
set xr $XRANGE

set logscale y

set key outside right
set terminal $OUTPUT_TYPE size $GRAPH_SIZE # noenhanced

set output "$OUTPUT_FILE"

#plot "150p.txt" u 1:2 w l, '150p.txt' u 1:3 w l,'150p.txt' u 1:4 w l
plot $PLOT
EOF

echo Plot configuration file stored in: $CONFIG_FILE

echo generating Graph...
sleep 1

gnuplot $CONFIG_FILE
if [ $? -eq 0 ]
then
	echo Plotted graph stored in: $([ ! -z "$OUT_DIR" ] && [ -d "$OUT_DIR" ] && mv $OUTPUT_FILE $OUT_DIR/$OUTPUT_FILE && echo "$OUT_DIR/")$OUTPUT_FILE
fi


}

#generate_power_metrics_graph $@

parse_plot_options $@
plot_graph
