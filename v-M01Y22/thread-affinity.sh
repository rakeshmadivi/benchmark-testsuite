#!/bin/bash
THISFILE=$(basename $BASH_SOURCE)
readonly dbgf=debug.${0/.sh/}
set -xe
exec 2> $dbgf

thread_affinity_parse(){

	if [ $# -ge 1 ]
	then
		declare -n opts_map=$1
	else
		local declare -A opts_map
		opts_map["g:"]="groups:/No.of Groups "
		opts_map["t:"]="type:/Affinity Type < compact | distributed >"
		opts_map["t:"]="threads-per-group:/Threads per group"
	fi
	
	local opts_order=(${!opts_map[@]})

	local short=""
	local long=""

	opts_help="$THISFILE <Options>"

	for i in ${!opts_order[@]}
	do
		key=${opts_order[$i]}
		short+="$key,"
		long+="${opts_map[$key]},"

		s_out="-${key/:/ <value>}"
		l_out="--${opts_map[$key]/:/ <value>}"
		opts_help+="\n\t ${s_out} | ${l_out}"
	done

	local opts=$(getopt -o ${short} -l ${long} -n $THISFILE -- $@ )

	eval set -- $opts

	while true
	do
		case $1 in

		esac
	done
}

NODES=( $(ls -d /sys/devices/system/node/node*) )

THREADS_MAP=()
CNT_MAP=()
for n in ${!NODES[@]}
do
	cpulist="$(cat ${NODES[$n]}/cpu*/topology/thread_siblings_list | sort -k1n | uniq | paste -d, -s)"
	THREADS_MAP+=( $cpulist )

	CNT_MAP+=( $(echo $cpulist | awk -F, '{print NF}') )
done

SORTED_MAP="$(
	for i in ${!CNT_MAP[@]}
	do
		echo "$i ${CNT_MAP[$i]}"
	done | sort -k2nr
)"

echo "Nodes: ${NODES[@]}"
for n in ${!THREADS_MAP[@]}
do
	echo "$n: ${THREADS_MAP[$n]}"
done

echo "${SORTED_MAP}"

# Get CPULIST for compact, distribute
get_cpulist_for(){

	[ $# -ne 1 ] && echo "Require argument"

	local return_cpulist=""

	max_th_map=$(echo "$SORTED_MAP" | head -n1)

	if [ $TH_PER_GRP -le ${max_th_map##* } ]
	then
		nodeid=${max_th_map%% *}

		return_cpulist+="$(echo ${THREADS_MAP[$nodeid]} | cut -f1-${TH_PER_GRP} -d,)"
	else
		echo "TODO: Need to implement."
	fi

	echo $return_cpulist

}

get_cpulist_for 5


