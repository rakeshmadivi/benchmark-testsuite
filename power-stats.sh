#!/bin/bash
#--------------- POWER STATS -----------
powerstatfile=power_collect.status
POWERGET=""

modprobe_dev(){
	sudo modprobe ipmi_devintf
	sudo modprobe ipmi_si
}

function start_power_collection()
{
  outfile=power_stats.txt
  if [ -f "$powerstatfile" ];then
    echo Removing Existing power status file...
    rm -rf $powerstatfile
  fi
  
  collectstatfile=collect.status
  collectlog=ngcollect.log
  
  sudo ipmitool sdr list | grep "Watts" 2>&1 > /dev/null
  if [ "$?" = "1" ];then
    #export POWERGET=AMPS
    echo -e "Collecting Volts and Amps..."
    
    while true
    do
      timenow=`date +"%d-%b-%Y %H:%M:%S"`
      echo -e "${timenow} Collecting..." >> $collectlog
      date >> $outfile
      sudo ipmitool sdr list | egrep "Volts|Amps" >> $outfile
      
      if [ -f "$powerstatfile" ];then
        if [ "`cat $powerstatfile`" = "STOP" ] ;then
          echo -e "Got STOP Command...\nSTOPPING power collection...\n"
          exit
        fi
      else
        echo -en "\rCollecting Power Utilization (Volts,Amps)..."
      fi
      
      sleep 30
      
    done
  else
    #export POWERGET=WATTS
    echo -e "Collecting Watts..."
    while true
    do
      timenow=`date +"%d-%b-%Y %H:%M:%S"`
      echo -e "${timenow} Collecting..." >> $collectlog
      date >> $outfile
      sudo ipmitool sdr list | grep "Watts" >> $outfile
      
      if [ -f "$powerstatfile" ];then
        if [ "`cat $powerstatfile`" = "STOP" ] ;then
          echo -e "Got STOP Command...\nSTOPPING power collection...\n"
          exit
        fi
      else
        echo -en "\rCollecting Power Utilization (Watts)..."
      fi
      
      sleep 30
      
    done
  fi    
}
