#!/bin/bash
set -x
which fio || sudo apt-get install -y fio

[ $# -eq 1 ] && block_devs=($(echo $1 | xargs -n1 -d: | xargs) ) #|| echo "[Usage] $0 dev1:dev2:dev3" && exit 1


echo  "Provided: $1 [ $block_devs ,${#block_devs[$@]} Devices]"

#PRECONDITION='
pconf=PRECONDITION.fio

cat << "EOF" | tee $pconf
#fio --name=PreCondition --ioengine=libaio --filename=${precon_disk} --rw=write --bs=128k --iodepth=8 --numjobs=1 --direct=1 --group_reporting --size=6T

[global]
name=PreCondition
filename=$DEVNAME
ioengine=libaio
direct=1
bs=1m
rw=write
numjobs=1

[PRE-CONDITION-v1]
bs=128k
iodepth=8
group_reporting

[PRE-CONDITION-v2-fio-plot]
iodepth=64
buffered=0
size=100%
loops=2
randrepeat=0
norandommap=1
refill_buffers=1
write_bw_log=${OUTPUT}/${MODE}-iodepth-1-numjobs-8
write_lat_log=${OUTPUT}/${MODE}-iodepth-1-numjobs-8
write_iops_log=${OUTPUT}/${MODE}-iodepth-1-numjobs-8
log_avg_msec=${LOGINTERVAL}

EOF
#'

for d in ${block_devs[@]} #$(echo /dev/nvme{0..11}n1)
do
	#Preconditioning	
	precon_disk=$d

	NVME_DISK=$(echo $precon_disk | grep "/nvme" || echo $?)
	
	disk_string="$(echo ${precon_disk} | tr '/' '_')"

	# PRECONDITION
	prefix=""
	if [ "$PRE_CONDITION" = "true" ]
	then
		echo Running Preconditioning on : $DEVNAMES
		fio --name=PreCondition --ioengine=libaio --filename=${precon_disk} --rw=write --bs=128k --iodepth=8 --numjobs=1 --direct=1 --group_reporting --loops=2 --size=3576Gi

		prefix="PreConditioned-"
	fi

	echo PRECONDITION = ${PRE_CONDITION}

	# get Disk Model

	which lshw || sudo apt-get install -y lshw nvme-cli

	if [ $NVME_DISK -eq 0 ]
	then
		echo "Testing NVME SSD"
		disk_details="$(sudo nvme list | grep "$precon_disk")"
		disk_model="$(echo $disk_details | awk '{if(NF == 15){print $3}else{print $3"_"$4}}')"

		# Irrespective of No.of Fields, NF-6 refers Unit, NF-7 refers to Disk Size
		disk_size_GiB=$(
		echo $disk_details | awk '{if($(NF-6) == "TB"){
		printf "%.f", $(NF-7)*931.323
		}else if($(NF-6) == "GB"){
		printf "%.f", $(NF-7)/1.074} # or multiply with 0.931323
		}' 
		)
	else
		disk_model="$(sudo fdisk -l $d | grep "Disk model" | awk '{print $3}')"
		disk_size_GiB="$(sudo fdisk -l $d | head -n1 | awk '{printf "%.f",$3}')"
	fi
	
	echo "DISK-MODEL: $disk_model Size: $disk_size_GiB"
	sleep 3

	res_dir=${prefix}disk-bench-results-${disk_model}

	mkdir -p $res_dir
	pushd $res_dir

	#fio --name=PreCondition --ioengine=libaio --filename=${precon_disk} --rw=write --bs=128k --iodepth=8 --numjobs=1 --direct=1 --group_reporting --size=6T
	# Generate Precondition for device
	#cat << EOF | tee precondition$disk_string.fio
$PRECONDTION
#EOF

	RESULT=()
	mix=(0 5 35 50 65 95 100)
	NJ=(4 6 8 12 16 20 24 32 48 64 128 144)
	IOD=(1 2 4 8 16) # Note that increasing iodepth beyond 1 will not affect synchronous ioengines
	for mix in ${mix[@]}	
	do
		for j in ${NJ[@]}
		do
			echo RUNNING: Read:$mix Jobs:$j
			#outf=${prefix}${disk_model}${disk_string}_$mix.json
			outf=${disk_model}_read${mix}_jobs${j}.json

			fio --ioengine=sync --filename=${precon_disk} --rw=randrw --rwmixread=$mix --bs=4k  --numjobs=$j --name=${outf/.json/} --direct=1 --group_reporting --runtime=60 --output-format=json | tee $outf;
			RESULT+=( $(cat $outf | jq -r -c ' [."global options".rwmixread, ."global options".numjobs, .jobs[0].read.iops, .jobs[0].read.clat_ns.percentile."99.000000", .jobs[0].write.iops, .jobs[0].write.clat_ns.percentile."99.000000"]  | @csv' | tr -d '"' ) )

			nres=${#RESULT[@]}

			[ ! -z "$nres" ] && echo "[Mix vs #Jobs] ${RESULT[$((nres-1))]}"

		done
	done

	{
		echo "rwmixRead vs #Jobs vs IOPS : $disk_model"
		echo "rwmixRead,#Jobs,Read-IOPS,Read-P99-Lat,Write-IOPS,Write-P99-Lat"
		printf "%s\n" ${RESULT[@]} 
	} | tee rwmixread-jobs-iops-latency-${disk_model}.csv

	echo "RWMIX READ Test DONE."

	RESULT=()
	for mix in 0 10 20 30 40 50 60 70 80 90 100; 
	do 
		echo RWReadMIX: $mix;

		outf=${prefix}${disk_model}${disk_string}_$mix.json

		fio --ioengine=sync --filename=${precon_disk} --rw=randrw --rwmixread=$mix --bs=4k  --numjobs=48 --name=foo --direct=1 --group_reporting --runtime=60 --output-format=json | tee $outf;
		RESULT+=( $(cat $outf | jq -r -c ' [."global options".rwmixread, .jobs[0].read.iops/'$disk_size_GiB', .jobs[0].write.iops/'$disk_size_GiB']  | @csv' | tr -d '"' ) )

	done															

	#cat ${disk_model}${disk_string}*.json | jq -r -c ' [."global options".rwmixread, .jobs[0].read.iops/3576, .jobs[0].write.iops/3576]  | @csv' | tee fio-bench${disk_string}.csv

	{
		echo IOPS per GiB: $disk_model
	echo "RWMIXREAD,READ_IOPS/GiB,WRITE_IOPS/GiB"
	printf "%s\n" ${RESULT[@]} 
	} | tee fio-bench-${disk_model}.csv

	# for #jobs run randread, randwrite
	
	rwoutf=${prefix}randread_randwrite_${disk_model}.csv

	NJ=(1 2 4 6 8 12 16 20 24 32 48 60)
	
	RESULT=()
	# RandRead
	for j in ${NJ[@]}; do
	       routf=${prefix}${disk_model}_randread-$j.json	
		fio --direct=1 --ioengine=libaio --iodepth=1 --numjobs=$j --sync=1 --name=foo --group_reporting --runtime=60 --output-format=json --rw=randread --filename=$precon_disk | tee $routf
		RESULT+=($(cat $routf | jq -r '[ ."global options".numjobs, .jobs[0].read.iops, .jobs[0].read.clat_ns.mean, .jobs[0].read.clat_ns.percentile."99.000000" ] | @csv')) 
	done

	HEADER="RandRead#jobs,READ-IOPS,READ-LAT-MEAN,P99-LAT"
	{
		echo Read Latency: $disk_model
		echo "$HEADER"
		printf "%s\n" ${RESULT[@]} 
	} | tee $rwoutf

	# RandWrite
	RESULT=()
	for j in ${NJ[@]}; do 
	       woutf=${prefix}${disk_model}_randwrite-$j.json	
	       fio --direct=1 --ioengine=libaio --iodepth=1 --numjobs=$j --sync=1 --name=foo --group_reporting --runtime=60 --output-format=json --rw=randwrite --filename=$precon_disk | tee $woutf

	       RESULT+=($(cat $woutf | jq -r '[ ."global options".numjobs, .jobs[0].write.iops, .jobs[0].write.clat_ns.mean, .jobs[0].write.clat_ns.percentile."99.000000" ] | @csv')) 
	done
	
	HEADER="RandWrite#jobs,WRITE-IOPS,WRITE-LAT-MEAN,P99-LAT"
	{
		echo
		echo Write Latency: $disk_model
		echo "$HEADER"
		printf "%s\n" ${RESULT[@]}
	} | tee -a ${rwoutf}


	echo $precon_disk DONE.
	echo
	popd
done
echo Exiting...
exit

echo 
echo Generating Jobfiles of different IODEPTHs...

IODEPTH=(1 2 4 8 16 32 64)

for i in ${IODEPTH[@]}
do
tname=disk-benchmark-IOD_${i}.fio

cat <<EOF | tee $tname

[global]
name=$tname

# If block device is specified, skip 'size' option else skip 'filename' & enable 'size' option
# filename/size option
$(

if [ ${#block_devs[@]} -eq 0 ]
then
	#f_size=$()
	echo size=200M
else
	echo filename=$1 #${block_devs[@]}
fi

direct=1

[ $direct -eq 1 ] && echo -e "direct=$direct\nsync=0" || echo -e "direct=$direct\nsync=1"

)
buffered=0

# delay can be range. but for this test we use fixed.
startdelay=4

ramp_time=5

runtime=2m
iodepth=1

numjobs=1

# This pattern can be anything hex,integer,string
buffer_pattern=0xdeadface

percentile_list=99.999 
write_lat_log=latlog 
group_reporting

# Try writes of (%) 100 95 65 50 35 5 0
#rwmixwrite=100

stonewall

[READ-BW]
rw=read
bs=4k

[WRITE-BW]
rw=write
bs=4k

[randread]
rw=randread
bs=128k

[randwrite]
rw=randwrite
bs=128k

[readwrite]
rw=readwrite
bs=4k

EOF

echo RUNNING: $tname


fio --output-format=json $tname | tee ${tname/.fio/.json}

done
