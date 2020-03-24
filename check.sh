#!/bin/bash
[ $# -ne 0 ] && if [ $1 = "-v" ]
then
	set -x
fi

fun(){
	: '
	for i in $@
	do
		echo $i 
	done
	'
	if [ $1 -eq 9 ];then return 0;else return 1;fi 
}
readdata(){
	
	echo Enter your data: && read var 
	if [ "$var" != "" ] 
	then
		for i in $var
		do
			echo You entered: $i
		done
	fi
}
#fun $@

fun 8
[ ! $? -eq 0 ] && echo Its 8
fun 8
echo RET-VAL: $?
fun 9 && echo Its 9

readdata
