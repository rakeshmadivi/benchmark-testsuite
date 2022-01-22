#!/bin/bash
[ $# -eq 0 ] && echo Please provide device name. Ex: $0 <device-name> && exit
[ ! -b $1 ] && echo $1 : Not a valid device. && exit

device=$1
bs=16k
mixw=100,50,40,0
iodepth=64
output=std.out

for tests in 1 #2 3
do
	echo Rinning Test: $tests >> $output
	for numas in 0 1
	do
		echo -e "\tNUMA: $numas" >> $output
		for j in 20 40
		do
			echo -e "\tNO.OF JOBS: $j" >> $output
			date >> $output
			numactl -N $numas ./ssspts-main.sh -d $device --block-sizes=$bs --rwmixwrite=$mixw --numjobs=$j --iodepth=$iodepth -e $tests >> $output 2>&1
		done
	done
done
