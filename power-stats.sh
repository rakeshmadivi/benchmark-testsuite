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

# Power Collection using Redfish API
redfishPowerReading(){
        [ $# -ne 1 ] && echo -e "Error: BMC IP is not provided." && exit
        bmcIP=$1
        powerConsumed=$(curl -skL https://${bmcIP}/redfish/v1/Chassis/Self/Power -u admin:password | jq '.PowerControl[0]|.PowerConsumedWatts')
        powerMetrics=( $(echo $(curl -skL https://${bmcIP}/redfish/v1/Chassis/Self/Power -u admin:password | jq '.PowerControl[0]|.PowerMetrics' | tr -d [{},\"] | awk '{print $2}')) )
        avgP=${powerMetrics[0]}
        maxP=${powerMetrics[2]}
        minP=${powerMetrics[3]}
        echo -e "$(date +%D-%T),$powerConsumed,$avgP,$minP,$maxP"
}

redfishPowerCollectionOn(){
	# Get BMC IP 
	[ $# -eq 0 ] && read -p "Enter BMC IP of Redfish server: " bmc_ip
	[ "$bmc_ip" = "" ] && echo -e "No BMC IP provided. Skipping Redfish Power Collection." && return 1
	
        redfishPowerFile=redfish-power-stats.txt

        if [ -f "$powerstatfile" ];then
                echo Removing Existing power status file...
                rm -rf $powerstatfile
        fi

        while true
        do
                redfishPowerReading $bmc_ip >> $redfishPowerFile
                if [ -f "$powerstatfile" ];then
                        if [ "`cat $powerstatfile`" = "STOP" ] ;then
                                echo -e "Got STOP Command...\nSTOPPING power collection...\n"
                                exit
                        fi
                else
                        echo -en "\r[ Redfish ] Collecting Power Consumption on: $bmc_ip ..."
                fi

                sleep 30
        done
}
