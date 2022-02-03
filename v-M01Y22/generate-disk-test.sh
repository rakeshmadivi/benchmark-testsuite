#!/bin/bash

[ $# -eq 1 ] && block_devs=($(echo $1 | xargs -n1 -d: | xargs) )

echo  "Provided: $1 [ $block_devs ,${#block_devs[$@]} Devices]"

res_dir=disk-bench-results

mkdir -p $res_dir
pushd $res_dir

for d in $(echo /dev/nvme{0..11}n1)
do
	#Preconditioning	
	precon_disk=$d
	disk_string=${precond_disk//\//_}

	fio --name=PreCondition --ioengine=libaio --filename=${precon_disk} --rw=write --bs=128k --iodepth=8 --numjobs=1 --direct=1 --group_reporting --size=6T

	for mix in 0 10 20 30 40 50 60 70 80 90 100; 
	do 
		echo $mix; 
		fio --ioengine=sync --filename=${precon_disk} --rw=randrw --rwmixread=$mix --bs=4k  --numjobs=48 --name=foo --direct=1 --group_reporting --runtime=60 --output-format=json | tee M7400_MTFDKCB3T8TDZ${disk_string}_$mix.json; 
	done															

	cat M7400*${disk_string}*.json | jq -r -c ' [."global options".rwmixread, .jobs[0].read.iops/3576, .jobs[0].write.iops/3576]  | @csv' | tee fio-bench${disk_string}.csv

	echo $precon_disk DONE.
	echo
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
