#!/bin/bash

#set -x

list_invalid_results(){
	invalid=()

	for d in $(find -type d | sed 's/result.*//g' | xargs readlink -f | egrep "[0-9]{2}-[0-9]{2}-[0-9]{2}_" | egrep -v "config" | sort | uniq)
	do

		grep -R "INVALID" $d > /dev/null 2>&1
		
		notvalid=$?

		if [ $notvalid -eq 0 ]
		then
			echo "[INVALID-RESULT] $d" && invalid+=($d)
		else
			echo "$d: $(grep RESULT $d/*out | sed 's/^.*max-/max-/g')"
		fi
	done

	[ ${#invalid[@]} -gt 0 ] && echo -e "\nResults Marked as INVALID are:" && echo "${invalid[@]}" | xargs -n1 | tee invalid-results.txt 
}

updatelist=tbd-update-config-list.txt
find_update_list(){
> $updatelist

for d in $(find -name "*1TxI*" -type d | xargs readlink -f)
do
	echo
	echo Directory: $d
	echo jOPS: $(grep RESULT $d/*out  | sed 's/^.*max-jOPS/max-jOPS/g')

	echo
	#echo HW/SW Details: 
	conf_f=$d/config/template-M.raw

	sys_model="$(egrep "Designation" $conf_f | awk -F= '{print $NF}')"
	mem_part_num="$(egrep "memoryDIMMS" $conf_f | awk -F= '{print $NF}')"

	# Check System Model and part numbers in directory name
	echo "$d" | grep "$sys_model" > /dev/null 2>&1 && echo "$d" | grep "$mem_part_num" >/dev/null 2>&1 || echo "${d},$sys_model,$mem_part_num" | tee -a $updatelist

	grep -R "HWMemModules" $d | awk '{print $2}' | grep "$mem_part_num" || echo "$d,$sys_model,$mem_part_num [RE-GENERATE HTML]" | tee -a $updatelist
done

}

do_update(){
	for i in $(cat $updatelist | egrep -v "*MB")
	do
		folder="$(basename $(echo $i | cut -f1 -d,) )"
		model=$(echo $i | cut -f2 -d,)
		mem=$(echo $i | cut -f3 -d,)

		echo
		echo "FOLDER: $folder"
		echo "Model: $model"
		echo "mem: $mem"

		conf_file=$folder/config/template-M.raw

		#egrep  "memoryDIMMS" $folder/config/template-M.raw | sed "s/=.*/=$(grep MEMORY $folder/SUT-info.txt | awk -F= '{print $2}')/g"

		sed -i "s/memoryDIMMS=.*/memoryDIMMS=$(grep MEMORY $folder/SUT-info.txt | awk -F= '{print $2}')/g" $conf_file
		egrep  "Designation|memoryDIMMS" $conf_file #$folder/config/template-M.raw 
	done
}

re_generate_report(){

	curr_dir=$PWD
	jdir=~/specjbb15

	pushd $curr_dir

	for d in $(find -name controller.log -type f | xargs -n1 readlink -f | xargs -n1 dirname) #$(cat $updatelist | cut -f1 -d,) # | xargs -n1 basename) #find -name "*TxI*" -type d | xargs -n1 readlink -f)
	do
		echo
		echo "Processing: $d"

		pushd $jdir

		rawf=${d}/config/template-M.raw
		bin_log="$(ls $d/*0001.data.gz | xargs basename)"
		
		# Run Reporter
		reporter_log=reporter-run.log
		
		java -Xms2g -Xmx2g -jar ./specjbb2015.jar -m reporter -raw ${d}/config/template-M.raw -s $d/*.data.gz | tee $reporter_log

		generated_report="$(cat $reporter_log | grep "\.html" | awk '{print $NF}' | xargs dirname)"
		
		from=$PWD/$generated_report 
		to=$d/$generated_report
		echo Moving Generated Report:
		echo "FROM: $from"
		echo "TO: $to"	

		backup_name=$(date +%Y%b%d-%H%M%S)

		[ -d $to ] && mv $to $(dirname $to)/$backup_name.$(basename $to)

		mv $generated_report $d/$generated_report

		popd
	done
}

[ $# -ne 1 ] && echo "Require function name to call." && exit 1
$1
