#!/bin/bash
# Sample Command
# sudo ./fill-in-sut-data.sh --tested-by ORG --tested-by-name Rakesh.Madivi --vendor VENDOR --vendor-url www.vendor.com --test-sponsor ORG
#set -x

# [ $UID -ne 0 ] && echo "Please run script as super user." && exit 0

depStatus=$(
sudo which dmidecode  > /dev/null && \
	which lshw > /dev/null && \
	which jq > /dev/null && \
	which numactl > /dev/null && \
	which java > /dev/null 2>&1
echo $?
)

install_cpu_monitoring_utils(){
	sudo apt-get install tuned tuned-utils tuned-utils-systemtap -y
	sudo apt-get install linux-cpupower turbostat -y

}

format_and_mount(){
	[ $# -ne 2 ] && echo "Invalid no.of arguments. Required: <device> <mount-point>"
	device=$1
	mnt_point=$2
	read -p "Formatting: $device. Continue (y/n)? " conf
	if [ "$conf" == "y" ] 
	then
		sudo mkfs.ext4 $device $mnt_point
		if [ $? -eq 0 ]
		then
			sudo mount $device $mnt_point
			dev_fs_uuid=$(lsblk -o NAME,FSTYPE,UUID | egrep "${device//.*\//}" | awk '{print $2,$NF}')

			echo Appending mount point to /etc/fstab. 
			sleep 2
			
			echo -e "UUID=$(echo $dev_fs_uuid | awk '{print $1}') $mnt_point $(echo $dev_fs_uuid | awk '{print $2}')	defaults	0	0" | sudo tee -a /etc/fstab 
			sudo mount -a
			lsblk
		else
			echo Could not format: $device
			return 1
		fi
	else
		echo Formatting cancelled.
		return
	fi
}

streamReq(){
	py=($(cd /usr/bin; ls python*))

	[ ${#py[@]} -eq 0 ] && echo "Python Not Found. Please install python." && exit

	alternatives=$(sudo update-alternatives --list python)
	alt_exists=$?

	if [ $alt_exists -eq 0 ]
	then
		echo Alternatives Available:
		echo "$alternatives"
		return 0
	else
		#which update-alternatives > /dev/null 2>&1; [ $? -ne 0 ] && sudo apt-get install # ? 
		for i in ${py[@]}
		do
			sudo update-alternatives --install /usr/bin/python python /usr/bin/$i $(echo ${i##python} | tr -d '.')
		done

		sudo update-alternatives --config python
	fi

	which gnuplot >/dev/null 2>&1
	[ $? -ne 0 ] && sudo apt-get install gnuplot -y
}

#streamReq
#exit

jre=$(apt-cache search "^openjdk-[0-9]+*-jre" | cut -f1,2,3 -d'-' |tr -d ' ' | uniq)

jre=openjdk-17-jre

[ $depStatus -ne 0 ] && sudo apt-get install -y dmidecode lshw jq $jre numactl

sutInfo(){
	vendor=$(sudo dmidecode -s system-manufacturer | awk '{print $1}')
	model=$(sudo dmidecode -s system-product-name | xargs)
	numa_cnt=$(lscpu | grep "NUMA node(s)" | awk '{print $NF}')

	processor=$(sudo dmidecode -s processor-version | uniq | xargs)
	socket_cnt=$(lscpu | grep "Socket" | awk '{print $NF}')
	SPEC_STR="${vendor}_${model}_${socket_cnt}x$(echo "$processor" | sed 's/(R)//g; s/@//g' | xargs | tr ' ' '_')-${numa_cnt}NUMA"
	sut_spec_file=SUT-$SPEC_STR.txt
	touch $sut_spec_file
	export SPEC_STR
}

biosInfo(){
	bios_vendor=$(sudo dmidecode -s bios-vendor)
	bios_version=$(sudo dmidecode -s bios-version)
	bios_release_date=$(sudo dmidecode -s bios-release-date)
	bios_revision=$(sudo dmidecode -s bios-revision)
	firmware_revision=$(sudo dmidecode -s firmware-revision)
	
	echo BIOS:
	echo -----
	echo "Bios Vendor = ${bios_vendor:-NA}"
	echo "Bios Version = ${bios_version:-NA}"
	echo "Bios Release Date = ${bios_release_date:-NA}"
	echo "Bios Revision = ${bios_revision:-NA}"
	echo "Bios Firmware Revision = ${firmware_revision:-NA}"
}

systemInfo(){
	sys_manufact=$(sudo dmidecode -s system-manufacturer)
	sys_prod_name=$(sudo dmidecode -s system-product-name)
	sys_version=$(sudo dmidecode -s system-version)
	sys_sn=$(sudo dmidecode -s system-serial-number)
	sys_uuid=$(sudo dmidecode -s system-uuid)
	sys_sku=$(sudo dmidecode -s system-sku-number)
	sys_fam=$(sudo dmidecode -s system-family)
	
	echo SYSTEM INFO:
	echo ------------
	echo "System Manufacturer = ${sys_manufact:-NA}"
	echo "System Product Name = ${sys_prod_name:-NA}"
	echo "System Version = ${sys_version:-NA}"
	echo "System Serial Number = ${sys_sn:-NA}"
	echo "System UUID = ${sys_uuid:-NA}"
	echo "System SKU = ${sys_sku:-NA}"
	echo "System Family = ${sys_fam:-NA}"
}

cpuInfo(){

	echo PROCESSOR:
	echo ----------
	for i in  processor-manufacturer  processor-family processor-version processor-frequency
	do
		echo "$(echo $i | xargs -d- | xargs | awk '{print toupper(substr($1,1,1))substr($1,2),toupper(substr($2,1,1))substr($2,2)}') = $(sudo dmidecode -s $i | uniq | xargs)"
	done
}

memInfo(){
	partitions=$(lsblk)
	regx="Size|Locator|Speed|Manufacturer|Part Number|Serial Number"
	dimmInfo="$(sudo dmidecode -t memory | egrep "$regx" | cat -A | egrep "$(echo "I${regx//\|/\|I}")" |  sed 's/\^I//g; s/\$//g')"
	
	regx=Locator
	locator=$(echo "$dimmInfo" | grep "$regx" | cut -f2- -d: )

	regx=Size
	memsize=$(echo "$dimmInfo" | grep "$regx" | cut -f2- -d: )

	regx=Speed
	speed=$(echo "$dimmInfo" | grep "$regx" | cut -f2- -d: )

	regx=Manufacturer
	manufact=$(echo "$dimmInfo" | grep "$regx" | cut -f2- -d: )

	regx="Part Number"
	pn=$(echo "$dimmInfo" | grep "$regx" | cut -f2- -d: )

	regx="Serial Number"
	sn=$(echo "$dimmInfo" | grep "$regx" | cut -f2- -d: )

	{
	formatted="$(paste -d: \
	<(echo "$dimmInfo" | egrep Locator | awk -F':' '{print $2}') \
	<(echo "$dimmInfo" | egrep Size | awk -F':' '{print $2}') \
	<(echo "$dimmInfo" | egrep Speed | awk -F':' '{print $2}') \
	<(echo "$dimmInfo" | egrep "Part Number" | awk -F':' '{print $2}') \
	<(echo "$dimmInfo" | egrep "Serial Number" | awk -F':' '{print $2}') | sed 's/^ //g')"

	echo "$formatted"
	echo
	echo =============================
	echo "TOTAL: $(echo "$formatted" | egrep " [GM]B" | wc -l) DIMMs Installed."
	} > /dev/null

	# Print a word for N times using seq and sed
	# seq $(echo "$locator" | wc -l) | sed 'c Memory'

	out_mem_details="$(paste -d'|' \
	<( seq $(echo "$locator" | wc -l) | sed 'c Memory') \
	<(echo "$locator") <(echo "$memsize") <(echo "$speed") <(echo "$manufact") <(echo "$pn") <(echo "$sn") \
		)"

	overall_mem_conf="$(echo "$out_mem_details" | egrep "^Memory" | egrep " [GM]B" | awk -F'|' '{print $3,$4,$5,$6}' | sort -k1n | uniq -c | xargs -I{} echo "{}" | sed 's/ / x /2' | awk '{print}' ORS=',' | xargs | head -c -2)"

	echo "$out_mem_details"
	echo -------------------------
	echo "MEMORY CONF: $overall_mem_conf"
	
	# CACHE MEMORY
	cacheSizes=$(lscpu -C | awk '{print $1,$2}' | sed 's/.$/ &B/g' | tail +2)

	echo
	echo CACHE:
	echo ------
	echo "Cache L1 = $(echo "$cacheSizes" | grep "L1i" | awk '{print $2,$3}') I + $(echo "$cacheSizes" | grep "L1d" | awk '{print $2,$3}') D per core"
	echo "Cache L2 = $(echo "$cacheSizes" | grep "L2" | awk '{print $2,$3}') I+D per core"

	echo "Cache L3 = $(echo "$cacheSizes" | grep "L3" | awk '{print $2,$3}') I+D per chip"
}

diskInfo(){
	echo "Disk = $(lsscsi -s | awk '{print $3,$4,$NF}')"
}

# STORE SUT Info into a file
print_SUT_info(){
echo
sutInfo
{
echo
biosInfo
echo
systemInfo
echo
cpuInfo
echo
memInfo
echo
diskInfo
} | tee $sut_spec_file
}

# -------------------------- System, Memory, Disk, NIC Info-------------------------------------
set_common_info(){

# SYSTEM INFO
systemName="$(sudo dmidecode -s system-product-name)"

# MEMORY INFO
# CACHE MEMORY
cache=$(cat /sys/devices/system/cpu/cpu0/cache/index*/size | xargs | tr -d 'K' | awk '{print $1" KB I + "$2" KB D per core,", $3" KB I+D per core,", $4/1024" MB I+D per chip"}')

# PRIMARY MEMORY
memInfoDetails=$(memInfo)

memDIMMS="$(echo "$memInfoDetails" | grep Memory | egrep " [GM]B" | awk -F'|' '{print $3,$4,$5,$6}' | sort -k1n | uniq -c | xargs -I{} echo "{}" | sed 's/ / x /2' | awk '{print}' ORS=',' | xargs | head -c -2)"

#echo "$memDIMMS";exit

memDetails="$(echo "$memInfoDetails" | grep Memory | egrep -v "No Module Installed|===|TOTAL" | awk -F'|' '{print $2}' | xargs) Populated"

# DISK
diskSize=$(lsscsi -s | awk '{$1=$2=$3=""; print $NF}' | head -1) #$(sudo fdisk -l | grep "Disk /dev/sda" | cut -f1 -d ',' | awk -F: '{print $2}' | awk -F '.' '{print $1,$2}' | xargs | cut -f1,3 -d ' ' | tr -d 'i' )

disk_fs=$(sudo df -Th | grep "^/dev" | awk '{print $2}' | uniq -c | xargs -I{} echo "{}" | sed 's/ / x /1' | awk '{print}' ORS=','| head -c -1)
disk_fs=${disk_fs:-FS-not-Found-on-sda}

#echo "$disk_fs";exit

# NETWORK
nics="$(sudo lshw -c network -short | grep "en" | tr -s ' ' | cut -f2,4- -d' ' | uniq -c | xargs -I{} echo "{}" | sed 's/ / x /1' | awk '{print}' ORS=',')" #| awk '{print $1,"x",$2}' | tr '\n' ',')

nics=${nics:-None}

SUT_totalSystems=1
SUT_allSUTSystemsIdentical=YES # YES
SUT_totalNodes=$(lscpu | grep "NUMA node(s)" | xargs | awk -F: '{print $2}' | sed 's/^ //') #8 TODO May change in stress testing
SUT_allNodesIdentical=YES # YES
SUT_nodesPerSystem=$(lscpu | grep "NUMA node(s)" | xargs | awk -F: '{print $2}' | sed 's/^ //') #8
SUT_totalChips=$(lscpu | grep "Socket(s):" | xargs | awk -F: '{print $2}' | sed 's/^ //') #16
coresPerChip=$(lscpu | grep "Core(s) per socket:" | xargs | awk -F: '{print $2}' | sed 's/^ //')
SUT_totalCores=$(( coresPerChip * SUT_totalChips))  # 32
threadsPerCore=$(lscpu | grep "Thread(s) per core:" | xargs | awk -F: '{print $2}' | sed 's/^ //') #64
SUT_totalThreads=$(( SUT_totalCores * threadsPerCore )) #64
SUT_totalMemoryInGB=$(sudo lshw -c memory -short | grep "System Memory" | awk '{print $(NF-2)}' | tr -d 'i' ) #echo "$memDIMMS" | awk '{print $2*$3}' )
SUT_totalOSImages=1
SUT_swEnvironment=Non-virtual # Non-virtual

} # End of Common Info

specJbbConfig(){

	echo "[ Filling SUT info in SPEC JBB CONFIG file.... ]"

	set_common_info
	# ---------------------------------------------------------------
	licenseNum=${licenseNum:-000}
	# Test Description
	test_date=$(date +"%B %d, %Y")
	test_internalReference="https://www.orginternal.com" #http://pluto.eng/specpubs/mar2000/
	test_location="Hyderabad, India" #Santa Monica, CA
	test_testSponsor=${testSponsor:-ABC Corp}
	test_testedBy=${testedBy:-DEF Corp.}
	test_testedByName=${testedByName:-Rakesh Madivi} 
	test_hwVendor=${hwVendor:-NA} #Poseidon Technologies # TODO --- fill it as command line option
	test_hwSystem=${systemName} #${hwSystemType:-Rack Server} #STAR T2 # TODO ----
	# Enter latest availability dates for hw and sw when using multiple components
	test_hwAvailability=${hwAvail:-May-2021} # TODO ----
	test_swAvailability=${swAvail:-May-2021} # TODO ----

	# SUT Details Test Aggregate
	# Sample Detail Collection: lscpu | grep "NUMA node(s)" | xargs | awk -F: '{print $2}' | sed 's/^ //'

	SUT_vendor=${hwVendor:-NA}
	SUT_vendorurl=${vendorUrl:-NA}
	SUT_systemSource=${SUT_systemSource:-Single Supplier}
	SUT_systemDesignation=${test_hwSystem}

	javadetails=$(java --version | head -1 | tr ' ' ',') 
	sw='
	{
	"jvm":{
	"name":"'$(echo $javadetails | cut -f1 -d',')'",
	"version":"'$(echo $javadetails | cut -f2,3 -d ',')'",
	"vendor":"OpenJDK and Java Community",
	"vendorurl":"http://openjdk.java.net/",
	"avaiable":"'$(echo $javadetails | head -1 | awk -F, "{print \$NF}")'",
	"bitness":"64",
	"notes":"note"
	},
	"os":{
	"name":"'$(grep "^NAME" /etc/os-release | cut -f2 -d '=' | tr -d '"')'",
	"version":"'$(grep VERSION /etc/os-release | cut -f2 -d '=' | tr -d '"')'",
	"bitness":"'$(uname -m)'",
	"available":"'$(echo APR-2020)'",
	"vendor":"'$(echo Debian)'",
	"vendorurl":"'$(echo www.debian.org)'",
	"notes":"None"
	},
	"other":{
	"name":"None",
	"vendor":"None",
	"vendorurl":"None",
	"available":"None",
	"bitness":"None",
	"notes":"None"
	}
	}
	'
	psuInstalled=$(sudo dmidecode -t 39 | grep "System Power Supply" | uniq -c | xargs)
	psuInstalled=${psuInstalled:-None}

	sut_hw='
	{
	"sysHw":{
	"name":"'$(sudo dmidecode -s system-product-name)'",
	"model":"'$(sudo dmidecode -s system-product-name)'",
	"formFactor":"'$(sudo dmidecode -s chassis-type)'",
	"cpuName":"'$(sudo dmidecode -s processor-version | uniq)'",
	"cpuCharacteristics":"'$(echo $SUT_totalCores Cores, $(sudo dmidecode -s processor-frequency | uniq), $(lscpu | grep "L3 Cache:" | cut -f2 -d':'))'",
	"nSystems":"1",
	"nodesPerSystem":"'$SUT_totalNodes'",
	"chipsPerSystem":"'$SUT_totalChips'",
	"coresPerSystem":"'$SUT_totalCores'",
	"coresPerChip":"'$coresPerChip'",
	"threadsPerSystem":"'$SUT_totalThreads'",
	"threadsPerCore":"'$threadsPerCore'",
	"version":"'$(sudo dmidecode -s processor-version)'",
	"available":"'$test_hwAvailability'",
	"cpuFrequency":"'$(sudo dmidecode -s processor-frequency|awk '{print $1}')'",
	"primaryCache":"'$(echo "$memInfoDetails" | grep "Cache L1" | cut -f2 -d"=" )'",
	"secondaryCache":"'$(echo "$memInfoDetails" | grep "Cache L2" | cut -f2 -d"=")'",
	"tertiaryCache":"'$(echo "$memInfoDetails" | grep "Cache L3" | cut -f2 -d"=")'",
	"otherCache":"None",
	"disk":"'$diskSize'",
	"file_system":"'$disk_fs'",
	"memoryInGB":"'$SUT_totalMemoryInGB'",
	"memoryDIMMS":"'$memDIMMS'",
	"memoryDetails":"'$memDetails'",
	"networkInterface":"'$nics'",
	"psuInstalled":"'$psuInstalled'",
	"other":"None",
	"sharedEnclosure":"None",
	"sharedDescription":"None",
	"sharedComment":"None",
	"vendor":"None",
	"vendor_url":"None",
	"notes":"None"
	},
	"other":{
	"name":"None",
	"vendor":"None",
	"vendorurl":"None",
	"version":"None",
	"available":"None",
	"bitness":"None",
	"notes":"None"
	}
	}
	'

	echo $sw | jq .
	echo $sut_hw | jq . 

	# Fill in details or create new config file 
	jbbversion=jbb2015
	jbbDetails='
	{
		"test":{
		"prefix":"'$jbbversion'.test",
		"params":{
		"date":"'$test_date'",
		"internalReference":"'$test_internalReference'",
		"location":"'$test_location'",
		"testSponsor":"'$test_testSponsor'",
		"testedBy":"'$test_testedBy'",
		"testedByName":"'$test_testedByName'",
		"hwVendor":"'$test_hwVendor'",
		"hwSystem":"'$test_hwSystem'",
		"hwAvailability":"'$test_hwAvailability'",
		"swAvailability":"'$test_swAvailability'"}
		},

		"sutAggregate":{
		"prefix":"'$jbbversion'.test.aggregate.SUT",
		"params":{
		"vendor":"'$SUT_vendor'",
		"vendor__url":"'$SUT_vendorurl'",
		"systemSource":"'$SUT_systemSource'",
		"systemDesignation":"'$SUT_systemDesignation'",
		"totalSystems":"'$SUT_totalSystems'",
		"allSUTSystemsIdentical":"'$SUT_allSUTSystemsIdentical'",
		"totalNodes":"'$SUT_totalNodes'",
		"allNodesIndentical":"'$SUT_allNodesIdentical'",
		"nodesPerSystem":"'$SUT_nodesPerSystem'",
		"totalChips":"'$SUT_totalChips'",
		"totalCores":"'$SUT_totalCores'",
		"totalThreads":"'$SUT_totalThreads'",
		"totalMemoryInGB":"'$SUT_totalMemoryInGB'",
		"totalOSImages":"'$SUT_totalOSImages'",
		"swEnvironment":"'$SUT_swEnvironment'"}
		},
		
		"sutProduct":{
		
		"sw":{
		"prefix":"'$jbbversion'.product.SUT.sw",
		"params":{
		"jvm__jvm_1__name":"'$(echo $sw | jq -r .jvm.name )'",
		"jvm__jvm_1__version":"'$(echo $sw | jq -r .jvm.version )'",
		"jvm__jvm_1__vendor":"'$(echo $sw | jq -r .jvm.vendor )'",
		"jvm__jvm_1__vendor__url":"'$(echo $sw | jq -r .jvm.vendorurl )'",
		"jvm__jvm_1__available":"'$(echo $sw | jq -r .jvm.available )'",
		"jvm__jvm_1__bitness":"'$(echo $sw | jq -r .jvm.bitness )'",
		"jvm__jvm_1__notes":"'$(echo $sw | jq -r .jvm.notes )'",
		"os__os_1__name":"'$(echo $sw | jq -r .os.name )'",
		"os__os_1__version":"'$(echo $sw | jq -r .os.version )'",
		"os__os_1__bitness":"'$(echo $sw | jq -r .os.bitness )'",
		"os__os_1__available":"'$(echo $sw | jq -r .os.available )'",
		"os__os_1__vendor":"'$(echo $sw | jq -r .os.vendor )'",
		"os__os_1__vendor__url":"'$(echo $sw | jq -r .os.vendorurl )'",
		"os__os_1__notes":"'$(echo $sw | jq -r .os.notes )'",
		"other__other_1__name":"'$(echo $sw | jq -r .other.name )'",
		"other__other_1__vendor":"'$(echo $sw | jq -r .other.vendor )'",
		"other__other_1__vendor__url":"'$(echo $sw | jq -r .other.vendorurl )'",
		"other__other_1__version":"'$(echo $sw | jq -r .other.version )'",
		"other__other_1__available":"'$(echo $sw | jq -r .other.available )'",
		"other__other_1__bitness":"'$(echo $sw | jq -r .other.bitness )'",
		"other__other_1__notes":"'$(echo $sw | jq -r .other.notes )'"
	}
		},
		
		"hw":{
		"prefix":"'$jbbversion'.product.SUT.hw",
		"params":{

		"system__hw_1__name":"'$(sudo dmidecode -s system-product-name)'",
		"system__hw_1__model":"'$(echo $sut_hw | jq  -r .sysHw.model )'",
		"system__hw_1__formFactor":"'$(echo $sut_hw | jq -r .sysHw.formFactor)'",
		"system__hw_1__cpuName":"'$(echo $sut_hw | jq -r .sysHw.cpuName)'",
		"system__hw_1__cpuCharacteristics":"'$(echo $sut_hw | jq -r .sysHw.cpuCharacteristics)'",
		"system__hw_1__nSystems":"'$(echo $sut_hw | jq -r .sysHw.nSystems)'",
		"system__hw_1__nodesPerSystem":"'$(echo $sut_hw | jq -r .sysHw.nodesPerSystem)'",
		"system__hw_1__chipsPerSystem":"'$(echo $sut_hw | jq -r .sysHw.chipsPerSystem)'",
		"system__hw_1__coresPerSystem":"'$(echo $sut_hw | jq -r .sysHw.coresPerSystem)'",
		"system__hw_1__coresPerChip":"'$(echo $sut_hw | jq -r .sysHw.coresPerChip)'",
		"system__hw_1__threadsPerSystem":"'$(echo $sut_hw | jq -r .sysHw.threadsPerSystem)'",
		"system__hw_1__threadsPerCore":"'$(echo $sut_hw | jq -r .sysHw.threadsPerCore)'",
		"system__hw_1__version":"'$(echo $sut_hw | jq -r .sysHw.version)'",
		"system__hw_1__available":"'$(echo $sut_hw | jq -r .sysHw.available)'",
		"system__hw_1__cpuFrequency":"'$(echo $sut_hw | jq -r .sysHw.cpuFrequency)'",
		"system__hw_1__primaryCache":"'$(echo $sut_hw | jq -r .sysHw.primaryCache)'",
		"system__hw_1__secondaryCache":"'$(echo $sut_hw | jq -r .sysHw.secondaryCache)'",
		"system__hw_1__tertiaryCache":"'$(echo $sut_hw | jq -r .sysHw.tertiaryCache)'",
		"system__hw_1__otherCache":"'$(echo $sut_hw | jq -r .sysHw.otherCache)'",
		"system__hw_1__disk":"'$(echo $sut_hw | jq -r .sysHw.disk)'",
		"system__hw_1__file_system":"'$(echo $sut_hw | jq -r .sysHw.file_system)'",
		"system__hw_1__memoryInGB":"'$(echo $sut_hw | jq -r .sysHw.memoryInGB)'",
		"system__hw_1__memoryDIMMS":"'$(echo $sut_hw | jq -r .sysHw.memoryDIMMS)'",
		"system__hw_1__memoryDetails":"'$(echo $sut_hw | jq -r .sysHw.memoryDetails)'",
		"system__hw_1__networkInterface":"'$(echo $sut_hw | jq -r .sysHw.networkInterface)'",
		"system__hw_1__psuInstalled":"'$(echo $sut_hw | jq -r .sysHw.psuInstalled)'",
		"system__hw_1__other":"'$(echo $sut_hw | jq -r .sysHw.other)'",
		"system__hw_1__sharedEnclosure":"'$(echo $sut_hw | jq -r .sysHw.sharedEnclosure)'",
		"system__hw_1__sharedDescription":"'$(echo $sut_hw | jq -r .sysHw.sharedDescription)'",
		"system__hw_1__sharedComment":"'$(echo $sut_hw | jq -r .sysHw.sharedComment)'",
		"system__hw_1__vendor":"'$(echo $sut_hw | jq -r .sysHw.vendor)'",
		"system__hw_1__vendor__url":"'$(echo $sut_hw | jq -r .sysHw.vendor_url)'",
		"system__hw_1__notes":"'$(echo $sut_hw | jq -r .sysHw.notes)'",
		"other__network_1__name":"'$(echo $sut_hw | jq -r .other.name)'",
		"other__network_1__vendor":"'$(echo $sut_hw | jq -r .other.vendor)'",
		"other__network_1__vendor__url":"'$(echo $sut_hw | jq -r .other.vendor_url)'",
		"other__network_1__version":"'$(echo $sut_hw | jq -r .other.version)'",
		"other__network_1__available":"'$(echo $sut_hw | jq -r .other.available)'",
		"other__network_1__bitness":"'$(echo $sut_hw | jq -r .other.bitness)'",
		"other__network_1__notes":"'$(echo $sut_hw | jq -r .other.notes)'"}
		}
		}

	}'

	# Copy original file
	origJbbConf=template-M.raw
	newJbbConf=sample.raw

	[ ! -f $origJbbConf ] && echo "$origJbbConf: File not found in current location ($PWD)." && exit

	cp $origJbbConf $newJbbConf
	#chown -R $USER:$USER $newJBBConf

	echo $jbbDetails | jq . | tee $logfile

	for i in $(echo $jbbDetails | jq -r '.|keys[] as $k | "\($k)"' ) 
	do
		echo Key: $i
		if [ "$i" == "sutProduct" ]
		then
			for component in sw hw
			do
				for param in $(echo $jbbDetails | jq -r '.'$i'.'$component'.params | keys [] as $p | "\($p)"' )
				do
					_key=$(echo $jbbDetails | jq -r .$i.$component.prefix ).$param
					_value=$(echo $jbbDetails | jq -r .$i.$component.params.$param )

					#echo ${_key//__/.} = $_value | tr -d '"'

					match_str=${_key//__/.}
					replace_str="${match_str}=$(echo ${_value} | sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')"

					{
					echo "$match_str -> $replace_str"
					echo "#--------------------------"
					} | tee -a $logfile

					sed -i "s/$match_str=.*/${replace_str}/" $newJbbConf

				done
			done
		else
			for parameter in $(echo $jbbDetails | jq -r '.'$i'.params|keys [] as $p | "\($p)"' )
			do
				_key="$(echo $jbbDetails | jq -r .$i.prefix ).$parameter"
				_value="$(echo $jbbDetails | jq -r .$i.params.${parameter/./\.} )"

				#echo ${_key//__/.} = $_value | tr -d '"'

				
				match_str=${_key//__/.}
				replace_str="${match_str}=$(echo ${_value} | sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')"

				{
				echo "$match_str -> $replace_str"
				echo "#--------------------------"
				} | tee -a $logfile

				sed -i "s/$match_str=.*/$replace_str/" $newJbbConf
			done
		fi
	done

	# Update licese number
	sed -i "s/specLicense=.*/specLicense=$licenseNum/g" $newJbbConf

	# Ignore sw.other and hw.other 
	sed -i '/hw\.other\|sw\.other/ s/^/#/g' $newJbbConf
}

# Generate SPEC CPU Config
specCpuConfig(){


	echo "[ Filling SUT info in SPEC CPU CONFIG file.... ]"

	set_common_info
	# -------------------

	SPEC_HOME=${HOME}/spec2017
	echo "SPECCPU HOME: $SPEC_HOME"
	sleep 2

	originalFile=Example-gcc-linux-x86.cfg
	updatedFile=Updated-gcc-linux-x86.cfg
	[ ! -f $originalFile ] && echo "$originalFile: File not found in current location ($PWD)." && exit

	cp $originalFile $updatedFile

	# CONFIGURATION
	test_label=${test_label:-${hwVendor}${systemName}}

	gcc_version=$(gcc -v 2>&1 | tail -1 | cut -f3 -d ' ')

	tester=${testSponsor:-MyOrganization}
	test_sponsor=${testSponsor:-MyOrganization}
	hw_avail=${hw_avail:-$(date +"%B-%Y")}
	sw_avail=${sw_avail:-$(date +"%B-%Y")}
	hw_cpu_nominal_mhz=$(lscpu | grep "CPU MHz" | cut -f2 -d':' | cut -f1 -d '.' |xargs)  
	hw_cpu_max_mhz=$(lscpu | grep "CPU max MHz" | cut -f2 -d':' | cut -f1 -d '.' | xargs)  
	hw_model=$systemName 
	hw_ncores=$SUT_totalCores  
	hw_ncpuorder="$SUT_totalChips chips" #-1)) | xargs | tr ' ' '-' ) #lscpu | grep "node.*CPU" | cut -f2 -d':' | xargs | tr ' ' ',')  
	hw_nthreadspercore=$threadsPerCore  
	hw_other=${hw_other:-None}  
	hw_pcache=$(echo $sut_hw | jq -r .sysHw.primaryCache)  
	hw_scache=$(echo $sut_hw | jq -r .sysHw.secondaryCache) 
	hw_tcache=$(echo $sut_hw | jq -r .sysHw.tertiaryCache)  
	hw_ocache=$(echo $sut_hw | jq -r .sysHw.otherCache)  
	fw_bios="$(sudo dmidecode -s bios-vendor) Version $(sudo dmidecode -s bios-version) Released $(d=$(sudo dmidecode -s bios-release-date); date -d $d +"%b-%Y")"  
	sw_other=${sw_other:-None}  

	speccpu_conf_params='
	{

		"label":"%define label '$test_label'",
		"gcc_dir":"%define gcc_dir /usr",
		"sw_compiler001": "C/C++/Fortran: Version '$gcc_version' of GCC, the",
		"sw_compiler002": "GNU Compiler Collection",
		"hw_vendor":"'$SUT_vendor'", 
		"tester":"'$tester'", 
		"test_sponsor":"'$test_sponsor'", 
		"license_num":"'${licenseNum}'", 
		"hw_avail":"'$hw_avail'", 
		"sw_avail":"'$sw_avail'", 
		"hw_cpu_nominal_mhz":"'$hw_cpu_nominal_mhz'", 
		"hw_cpu_max_mhz":"'$hw_cpu_max_mhz'", 
		"hw_model":"'$hw_model'", 
		"hw_ncores":"'$hw_ncores'", 
		"hw_ncpuorder":"'$hw_ncpuorder'", 
		"hw_nthreadspercore":"'$hw_nthreadspercore'", 
		"hw_other":"'$hw_other'", 
		"hw_pcache":"'$hw_pcache'", 
		"hw_scache":"'$hw_scache'", 
		"hw_tcache":"'$hw_tcache'", 
		"hw_ocache":"'$hw_ocache'", 
		"fw_bios":"'$fw_bios'", 
		"sw_other":"'$sw_other'" 
	}
	'

	echo $speccpu_conf_params 
	echo $speccpu_conf_params | jq .

	for confKey in $(echo $speccpu_conf_params | jq -r '.|keys [] as $k | "\($k)"' )
	do
		echo KEY: $confKey

		defines=(label gcc_dir)
		matched=$(echo ${defines[@]} | tr ' ' '\n' | grep -x "$confKey" > /dev/null; echo $?)

		if [ $matched -eq 0 ]
		then
			[ "$confKey" == "label" ] && value=$(echo $jbbDetails | jq -r '.sutProduct.hw.params.system__hw_1__name,.sutProduct.hw.params.system__hw_1__cpuName' | xargs )
			[ "$confKey" == "gcc_dir" ] && value="/usr"

			confValue=$(echo $value | sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')
			echo CONF-VALUE: $confValue

			sed -i "s/^%[[:blank:]].*define[[:blank:]].*$confKey[[:blank:]].*$/%define $confKey $confValue/" $updatedFile
		else
			confValue=$(echo $speccpu_conf_params | jq -r ".$confKey" | sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')
			echo CONF-VALUE: $confValue

			sed -i "s/^[[:blank:]]*$confKey[[:blank:]]*=/\t$confKey = $confValue #/" $updatedFile
		fi
	done

	# Finally Append Compiler Flags Required for GCC > 10 to avoid Build Errors
	ccFlags=" -fcommon"
	cxxFlags=" -fcommon"
	fortranFlags=" -std=legacy -fallow-argument-mismatch"

	lineEnd="$"

	testLabel=$(sudo dmidecode -s system-manufacturer | awk '{print $1}')-$(sudo dmidecode -s processor-version | sed 's/(R)//g; s/@//g' | uniq | xargs | tr ' ' '-')

	echo Setting Test Label: $testLabel
	sed -i "s/mytest/$testLabel/" $updatedFile

	echo "Updating Compiler Flags... [ CC: $ccFlags; CXX: $cxxFlags; Fortran: $fortranFlags ]"
	sleep 1

	sed -i "/CC   / s/$lineEnd/$ccFlags/g" $updatedFile
	sed -i "/CXX   / s/$lineEnd/$cxxFlags/g" $updatedFile
	sed -i "/FC   / s/$lineEnd/$fortranFlags/g" $updatedFile

	# ADD FLAGS DESCRIPTIONS TO ${SPEC_HOME}/config/flags/gcc.xml
	flagDescFile=flags-description.json
	[ ! -f $flagDescFile ] && echo "No Flag description file found." && exiting

flagDesc=$(cat <<EOF
<flag name="fcommon"
	class="other">
	<example>-fcommon</example>
	<![CDATA[<p>
		$(jq -r '."-fcommon"' $flagDescFile)
	</p>]]>
</flag>

<flag name="std-legacy-gcc"
      compilers="gfortran"
      class="optimization"
      regexp="-std=legacy"
      >
	<example>-std=legacy</example>
	<![CDATA[<p>
		      Sets the language dialect to include syntax from the Fortran Legacy standard.
	</p>]]>
</flag>

<flag name="fallow-argument-mismatch"
	class="other">
	<example>-fallow-argument-mismatch</example>
	<![CDATA[<p>
		$(jq -r '."-fallow-argument-mismatch"' $flagDescFile)
	</p>]]>
</flag>
EOF
)

	echo "ARGUMENTS DESCRIPTION:"
	escaped=$(printf "%q" "$flagDesc" | sed "s/\$'//; s/'$//")
	#echo "${escaped}" ;exit
	origFlags=gcc.xml
	newFlags=updated-gcc.xml
	line=$( grep -n "</flagsdescription>" $origFlags |cut -f1 -d:)
	cat $origFlags | sed "$line i ${escaped}" > $newFlags

	# COPY to respective test config locations
	echo Copying to test locations...
	sleep 1
	cp $updatedFile $SPEC_HOME/config/updated-gcc-linux-x86.cfg
	cp $newFlags $SPEC_HOME/config/flags/gcc.xml

}

###################### PARSE COMMAND LINE
parseArgs(){

	PARSE_V=1

	if [ $PARSE_V -eq 1 ]
	then
		argc=$#

		[[ $# -eq 0 ]] || [[ $((argc%2)) -ne 0 ]] && echo  "Invalid no.of arguments." && exit

		parts=$((argc/2))
		
		# Check for SPECCPU location
		cpu_jbb=$(echo "$@" | xargs | tr ' ' '\n'| egrep "\-\-spec-cpu-loc|\-\-spec-jbb-loc" )
		[ $? -eq 0 ] && [ $(echo -e "$cpu_jbb" | wc -l) -ne 2 ] && echo "Please pass SPECCPU and SPECJBB Install locations." && exit

		# Loop until all parameters are used up
		cnt=0
		while [ "$1" != "" ]; do
			[ $cnt -gt $((parts*2)) ] && exit

			case "$1" in
				# TODO Pre-check if valid arguments are given

				--check)
					memInfo 
					exit
					shift 2;;
				--cpu-config)
					cpuConfig=$2
					shift 2;;
				--jbb-config)
					jbbConfig=$2
					shift 2;;
				--spec-cpu-loc)
					cpuLoc=$2
					shift 2;;
				--spec-jbb-loc)
					jbbLoc=$2
					shift 2;;
				--test-sponsor)
					testSponsor=$2
					shift 2;;
				--tested-by)
					testedBy=$2
					shift 2;;
				--tested-by-name)
					testedByName=$2
					shift 2;;
				--vendor) 
					hwVendor=${2^^}
					shift 2;;
				--vendor-url) 
					vendorUrl=$2
					shift 2;;
				--hw-available-on) 
					hwAvail=$2
					shift 2;;
				--sw-available-on) 
					swAvail=$2
					shift 2;;
				--psus)
					psus=$2
					shift 2;;
				--license-num)
					licenseNum=${2}
					shift 2;;
				*)
					echo Invalid Option: $1
					exit;;
			esac
			cnt=$((cnt+2))
			echo COUNT: $cnt
		done

	else
		# Version 2
		echo "[ fill-in-sut-data.sh ] Using Parse Version 2"
		declare -A fill_in_opts
		fill_in_opts["m"]="mem-check"
		fill_in_opts["j"]="specjbb-config"
		fill_in_opts["c"]="speccpu-config"
		fill_in_opts["J:"]="specjbb-home:"
		fill_in_opts["C:"]="speccpu-home:"
		fill_in_opts["l:"]="license-num:"
		fill_in_opts["s:"]="test-sponsor:"
		fill_in_opts["t:"]="tested-by:"
		fill_in_opts["n"]="tested-by-name:"
		fill_in_opts["v:"]="vendor:"
		fill_in_opts["u:"]="vendor-url:"
		fill_in_opts["h:"]="hw-avail-on"
		fill_in_opts["p:"]="psus:"

		S=()
		L=()
		for k in ${!fill_in_opts[@]}
		do
			s=$k
			l=${fill_in_opts[$k]}

			matched=$(echo -e "$s\n${l}" | grep ":" | wc -l)

			if [[ "$matched" == "[02]" ]]
			then
				S+=($s)
				L+=($l)
			else
				echo "[ Error ] Invalid Argument Definition. [ Short, Long ] = [ $s, $l]"
				exit 1
			fi
		done

		CONF_OPTS=$(getopt -o $(echo ${S[@]} | xargs -n1  | paste -d, -s) -l $(echo ${L[@]} | xargs -n1 | paste -d, -s ) -n $0 -- $@; ec=$? [ $ec -ne 0 ] &&  echo failed > /tmp/conf-opt-parsing )

		[ $(cat /tmp/conf-opt-parsing) == failed ] && echo "[ fill-in-sut-data.sh FAILED ] Option parsing failed." && exit 1

		eval set -- ${CONF_OPTS}

		while true
		do
			case "$1" in
				* ) break;;
				-- ) shift; break;;
			esac
		done

	fi

	[ "$cpuConfig" != "" ] && specCpuConfig
	[ "$jbbConfig" != "" ] && specJbbConfig
}

parseArgs $@

