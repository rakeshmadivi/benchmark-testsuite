#!/bin/bash
#
# SAMPLE SPECJBB2015-MultiJVM SUBMISSION TEMPLATE
#

#set -x

[ $UID -ne 0 ] && echo "Please run script as super user." && exit 0
depStatus=$(
sudo which dmidecode  > /dev/null && \
	which lshw > /dev/null && \
	which jq > /dev/null && \
	which java > /dev/null 2>&1
echo $?
)

jre=$(apt-cache search "^openjdk-[0-9]+*-jre" | cut -f1,2,3 -d'-' |tr -d ' ' | uniq)

[ $depStatus -ne 0 ] && sudo apt-get install -y dmidecode lshw jq $jre

parseArgs(){

	argc=$#


	[ $((argc%2)) -ne 0 ] && echo  "Invalid no.of arguments." && exit

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
				hwVendor=$2
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
		esac
		cnt=$((cnt+2))
		echo COUNT: $cnt
	done

	#echo "Args:"
	#echo "${hwVendor} $vendorUrl $psus"
}

parseArgs $@
#exit


# TODO Add case statement here to read options from command line.
# Test Description
test_date=$(date +"%B %d, %Y")
test_internalReference="https://www.orginternal.com" #http://pluto.eng/specpubs/mar2000/
test_location="Hyderabad, India" #Santa Monica, CA
test_testSponsor=${testSponsor:-ABC Corp}
test_testedBy=${testedBy:-DEF Corp.}
test_testedByName=${testedByName:-Rakesh Madivi} 
test_hwVendor=${hwVendor:-NA} #Poseidon Technologies # TODO --- fill it as command line option
test_hwSystem=${hwSystemType:-Rack Server} #STAR T2 # TODO ----
# Enter latest availability dates for hw and sw when using multiple components
test_hwAvailability=${hwAvail:-May-2000} # TODO ----
test_swAvailability=${swAvail:-May-2000} # TODO ----

# SUT Details Test Aggregate
# Sample Detail Collection: lscpu | grep "NUMA node(s)" | xargs | awk -F: '{print $2}' | sed 's/^ //'

SUT_vendor=${hwVendor:-NA}
SUT_vendorurl=${vendorUrl:-NA}
SUT_systemSource=${SUT_systemSource:-NA}
SUT_systemDesignation=${SUT_systemDesignation:-NA}
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
SUT_totalMemoryInGB=$(expr $(grep "MemTotal" /proc/meminfo | xargs | cut -f2 -d' ') / 1000000 ) #8
SUT_totalOSImages=1
SUT_swEnvironment=Non-virtual # Non-virtual

# sample: openjdk-15-jdk/groovy,now 15+36-1 amd64 [installed]
javadetails=$(java --version | head -1 | tr ' ' ',') #apt list --installed 2>/dev/null | grep "jdk/")
sw='
{
"jvm":{
"name":"'$(echo $javadetails | cut -f1 -d',')'",
"version":"'$(echo $javadetails | cut -f2 -d ',')'",
"vendor":"OpenJDK and Java Community",
"vendorurl":"http://openjdk.java.net/",
"avaiable":"'$(java -version 2>&1 | head -1 | cut -f3 -d ' '| tr -d '"')'",
"bitness":"64",
"notes":"note"
},
"os":{
"name":"'$(grep "^NAME" /etc/os-release | cut -f2 -d '=' | tr -d '"')'",
"version":"'$(grep VERSION /etc/os-release | cut -f2 -d '=' | tr -d '"')'",
"bitness":"'$(uname -m)'",
"available":"'$(echo APR-2020)'",
"vendor":"'$(echo Canonical)'",
"vendorurl":"'$(echo www.canonical.org)'",
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

disk_fs=$(sudo df -Th | grep "/dev/sda" | awk '{print $2}' | uniq -c | xargs )
disk_fs=${disk_fs:-FS-not-Found-on-sda}

nics=$(sudo lshw -c network -short | grep "en" | tr -s ' ' | cut -f2,4- -d' ' | uniq -c | awk '{print $1,"x",$2}' | tr '\n' ',')
nics=${nics:-None}

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
"available":"to-be-filled",
"cpuFrequency":"'$(sudo dmidecode -s processor-frequency|awk '{print $1}')'",
"primaryCache":"'$(lscpu | grep -E "L1[d,i] cache" | awk '{print $3,$4}' | tr '\n' '+' | sed 's/+$//')' per core",
"secondaryCache":"'$(lscpu | grep -E "L2 cache" | awk '{print $3,$4}')' per core",
"tertiaryCache":"'$(lscpu | grep -E "L3 cache" | awk '{print $3,$4}')' per chip",
"otherCache":"None",
"disk":"'$(sudo fdisk -l | grep "Disk /dev/sda" | cut -f1 -d ',' | awk -F: '{print $2}')'",
"file_system":"'$disk_fs'",
"memoryInGB":"'$SUT_totalMemoryInGB'",
"memoryDIMMS":"'$(sudo dmidecode -t memory | grep -v "No Module" | sed 's/^[[:space:]]+*//' | grep "^Size:" | uniq -c | awk '{print $1,"x",$3,$4}' | xargs)'",
"memoryDetails":"'$(sudo dmidecode -t memory | grep Locator | grep -v Bank | cut -f2 -d ' ' | xargs)'",
"networkInterface":"'$nics' x Ethernet",
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

#exit

# Fill in details or create new config file 
jbbversion=jbb2015
details='
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
	"jvm__jvm_1__name":"'$(echo $sw | jq .jvm.name| tr -d '"' )'",
	"jvm__jvm_1__version":"'$(echo $sw | jq .jvm.version| tr -d '"' )'",
	"jvm__jvm_1__vendor":"'$(echo $sw | jq .jvm.vendor| tr -d '"' )'",
	"jvm__jvm_1__vendor__url":"'$(echo $sw | jq .jvm.vendorurl| tr -d '"' )'",
	"jvm__jvm_1__available":"'$(echo $sw | jq .jvm.available| tr -d '"' )'",
	"jvm__jvm_1__bitness":"'$(echo $sw | jq .jvm.bitness| tr -d '"' )'",
	"jvm__jvm_1__notes":"'$(echo $sw | jq .jvm.notes| tr -d '"' )'",
	"os__os_1__name":"'$(echo $sw | jq .os.name| tr -d '"' )'",
	"os__os_1__version":"'$(echo $sw | jq .os.version| tr -d '"' )'",
	"os__os_1__bitness":"'$(echo $sw | jq .os.bitness| tr -d '"' )'",
	"os__os_1__available":"'$(echo $sw | jq .os.available| tr -d '"' )'",
	"os__os_1__vendor":"'$(echo $sw | jq .os.vendor| tr -d '"' )'",
	"os__os_1__vendor__url":"'$(echo $sw | jq .os.vendorurl| tr -d '"' )'",
	"os__os_1__notes":"'$(echo $sw | jq .os.notes| tr -d '"' )'",
	"other__other_1__name":"'$(echo $sw | jq .other.name| tr -d '"' )'",
	"other__other_1__vendor":"'$(echo $sw | jq .other.vendor| tr -d '"' )'",
	"other__other_1__vendor__url":"'$(echo $sw | jq .other.vendorurl| tr -d '"' )'",
	"other__other_1__version":"'$(echo $sw | jq .other.version| tr -d '"' )'",
	"other__other_1__available":"'$(echo $sw | jq .other.available| tr -d '"' )'",
	"other__other_1__bitness":"'$(echo $sw | jq .other.bitness| tr -d '"' )'",
	"other__other_1__notes":"'$(echo $sw | jq .other.notes| tr -d '"' )'"
}
	},
	
	"hw":{
	"prefix":"'$jbbversion'.product.SUT.hw",
	"params":{

	"system__hw_1__name":"'$(sudo dmidecode -s system-product-name)'",
	"system__hw_1__model":"'$(echo $sut_hw | jq .sysHw.model| tr -d '"' )'",
	"system__hw_1__formFactor":"'$(echo $sut_hw | jq .sysHw.formFactor| tr -d '"' )'",
	"system__hw_1__cpuName":"'$(echo $sut_hw | jq .sysHw.cpuName| tr -d '"' )'",
	"system__hw_1__cpuCharacteristics":"'$(echo $sut_hw | jq .sysHw.cpuCharacteristics| tr -d '"' )'",
	"system__hw_1__nSystems":"'$(echo $sut_hw | jq .sysHw.nSystems| tr -d '"' )'",
	"system__hw_1__nodesPerSystem":"'$(echo $sut_hw | jq .sysHw.nodesPerSystem| tr -d '"' )'",
	"system__hw_1__chipsPerSystem":"'$(echo $sut_hw | jq .sysHw.chipsPerSystem| tr -d '"' )'",
	"system__hw_1__coresPerSystem":"'$(echo $sut_hw | jq .sysHw.coresPerSystem| tr -d '"' )'",
	"system__hw_1__coresPerChip":"'$(echo $sut_hw | jq .sysHw.coresPerChip| tr -d '"' )'",
	"system__hw_1__threadsPerSystem":"'$(echo $sut_hw | jq .sysHw.threadsPerSystem| tr -d '"' )'",
	"system__hw_1__threadsPerCore":"'$(echo $sut_hw | jq .sysHw.threadsPerCore| tr -d '"' )'",
	"system__hw_1__version":"'$(echo $sut_hw | jq .sysHw.version| tr -d '"' )'",
	"system__hw_1__available":"'$(echo $sut_hw | jq .sysHw.available| tr -d '"' )'",
	"system__hw_1__cpuFrequency":"'$(echo $sut_hw | jq .sysHw.cpuFrequency| tr -d '"' )'",
	"system__hw_1__primaryCache":"'$(echo $sut_hw | jq .sysHw.primaryCache| tr -d '"' )'",
	"system__hw_1__secondaryCache":"'$(echo $sut_hw | jq .sysHw.secondaryCache| tr -d '"' )'",
	"system__hw_1__tertiaryCache":"'$(echo $sut_hw | jq .sysHw.tertiaryCache| tr -d '"' )'",
	"system__hw_1__otherCache":"'$(echo $sut_hw | jq .sysHw.otherCache| tr -d '"' )'",
	"system__hw_1__disk":"'$(echo $sut_hw | jq .sysHw.disk| tr -d '"' )'",
	"system__hw_1__file_system":"'$(echo $sut_hw | jq .sysHw.file_system| tr -d '"' )'",
	"system__hw_1__memoryInGB":"'$(echo $sut_hw | jq .sysHw.memoryInGB| tr -d '"' )'",
	"system__hw_1__memoryDIMMS":"'$(echo $sut_hw | jq .sysHw.memoryDIMMS| tr -d '"' )'",
	"system__hw_1__memoryDetails":"'$(echo $sut_hw | jq .sysHw.memoryDetails| tr -d '"' )'",
	"system__hw_1__networkInterface":"'$(echo $sut_hw | jq .sysHw.networkInterface| tr -d '"' )'",
	"system__hw_1__psuInstalled":"'$(echo $sut_hw | jq .sysHw.psuInstalled| tr -d '"' )'",
	"system__hw_1__other":"'$(echo $sut_hw | jq .sysHw.other| tr -d '"' )'",
	"system__hw_1__sharedEnclosure":"'$(echo $sut_hw | jq .sysHw.sharedEnclosure| tr -d '"' )'",
	"system__hw_1__sharedDescription":"'$(echo $sut_hw | jq .sysHw.sharedDescription| tr -d '"' )'",
	"system__hw_1__sharedComment":"'$(echo $sut_hw | jq .sysHw.sharedComment| tr -d '"' )'",
	"system__hw_1__vendor":"'$(echo $sut_hw | jq .sysHw.vendor| tr -d '"' )'",
	"system__hw_1__vendor__url":"'$(echo $sut_hw | jq .sysHw.vendor_url| tr -d '"' )'",
	"system__hw_1__notes":"'$(echo $sut_hw | jq .sysHw.notes| tr -d '"' )'",
	"other__network_1__name":"'$(echo $sut_hw | jq .other.name| tr -d '"' )'",
	"other__network_1__vendor":"'$(echo $sut_hw | jq .other.vendor| tr -d '"' )'",
	"other__network_1__vendor__url":"'$(echo $sut_hw | jq .other.vendor_url| tr -d '"' )'",
	"other__network_1__version":"'$(echo $sut_hw | jq .other.version| tr -d '"' )'",
	"other__network_1__available":"'$(echo $sut_hw | jq .other.available| tr -d '"' )'",
	"other__network_1__bitness":"'$(echo $sut_hw | jq .other.bitness| tr -d '"' )'",
	"other__network_1__notes":"'$(echo $sut_hw | jq .other.notes| tr -d '"' )'"}
	}
	}

}'

# Copy original file
cp template-M.raw sample.raw

mod_file=sample.raw
logfile=log.sample
echo $details | jq . | tee $logfile

for i in $(echo $details | jq '.|keys[] as $k | "\($k)"' | tr -d '"') 
do
	echo Key: $i
	if [ "$i" == "sutProduct" ]
	then
		for component in sw hw
		do
			for param in $(echo $details | jq '.'$i'.'$component'.params | keys [] as $p | "\($p)"' | tr -d '"')
			do
				_key=$(echo $details | jq .$i.$component.prefix | tr -d '"').$param
				_value=$(echo $details | jq .$i.$component.params.$param | tr -d '"')

				echo ${_key//__/.} = $_value

				match_str=${_key//__/.}
				replace_str="${match_str}=$(echo ${_value} | sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')"

				{
				echo "#--------------------------"
				echo Replacing with: $replace_str
				echo "#--------------------------"
				} | tee -a $logfile

				sed -i "s/$match_str=.*/${replace_str}/" $mod_file

				: '
				if [[ "$param" =~ "other" ]]
				then
					echo Exiting... with:
					echo PARAM: $component $param $_key
					echo "MATCHING: $match_str => $replace_str"
					exit
				fi
				#'

			done
		done
	else
		for parameter in $(echo $details | jq '.'$i'.params|keys [] as $p | "\($p)"' | tr -d '"')
		do
			_key="$(echo $details | jq .$i.prefix | tr -d '"').$parameter"
			_value="$(echo $details | jq .$i.params.${parameter/./\.} | tr -d '"')"

			echo ${_key//__/.} = $_value
			
			match_str=${_key//__/.}
			replace_str="${match_str}=$(echo ${_value} | sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')"

			{
			echo "#--------------------------"
			echo Replacing with: $replace_str
			echo "#--------------------------"
			} | tee -a $logfile

			sed -i "s/$match_str=.*/$replace_str/" $mod_file
		done
	fi
done

# Generate SPEC CPU Config

# FILE COPY
originalFile=Example-gcc-linux-x86.cfg
updatedFile=Updated-gcc-linux-x86.cfg
[ ! -f $originalFile ] && echo "$originalFile: File not found in current location ($PWD)." && exit


cp $originalFile $updatedFile

# CONFIGURATION
systemName="$(sudo dmidecode -s system-product-name)"
test_label=${test_label:-MyTest}

gcc_version=$(gcc -v 2>&1 | tail -1 | cut -f3 -d ' ')

tester=${tester:-MyOrganization}
test_sponsor=${test_sponsor:-MyOrganization}
hw_avail=${hw_avail:-$(date +"%B-%Y")}
sw_avail=${sw_avail:-$(date +"%B-%Y")}
hw_cpu_nominal_mhz=$(lscpu | grep "CPU min MHz" | cut -f2 -d':' | xargs)  
hw_cpu_max_mhz= $(lscpu | grep "CPU min MHz" | cut -f2 -d':' | xargs)  
hw_model=$systemName 
hw_ncores=$SUT_totalCores  
hw_ncpuorder=$(lscpu | grep "node.*CPU" | cut -f2 -d':' | xargs | tr ' ' ',')  
hw_nthreadspercore=$threadsPerCore  
hw_other=${hw_other:-None}  
hw_pcache=$(echo $sut_hw | jq .sysHw.primaryCache | tr -d '"')  
hw_scache=$(echo $sut_hw | jq .sysHw.secondaryCache | tr -d '"') 
hw_tcache=$(echo $sut_hw | jq .sysHw.tertiaryCache | tr -d '"')  
hw_ocache=$(echo $sut_hw | jq .sysHw.otherCache | tr -d '"')  
fw_bios="$(sudo dmidecode -s bios-vendor) $(sudo dmidecode -s bios-version) $(sudo dmidecode -s bios-release-date)"  
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
	"license_num":"nnn-nnn-nnn", 
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

for confKey in $(echo $speccpu_conf_params | jq '.|keys [] as $k | "\($k)"' | tr -d '"')
do
	echo KEY: $confKey

	defines=(label gcc_dir)
	matched=$(echo ${defines[@]} | tr ' ' '\n' | grep -x "$confKey" > /dev/null; echo $?)

	if [ $matched -eq 0 ]
	then
		[ "$confKey" == "label" ] && value=$(echo $details | jq '.sutProduct.hw.params.system__hw_1__name,.sutProduct.hw.params.system__hw_1__cpuName' | xargs | tr -d '"')
		[ "$confKey" == "gcc_dir" ] && value="/usr"

		confValue=$(echo $value | sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')
		echo CONF-VALUE: $confValue

		sed -i "s/^%[[:blank:]].*define[[:blank:]].*$confKey[[:blank:]].*$/%define $confKey $confValue/" $updatedFile
	else
		confValue=$(echo $speccpu_conf_params | jq ".$confKey" | tr -d '"'| sed 's/\//\\\//g; s/)/\\)/g; s/(/\\(/g')
		echo CONF-VALUE: $confValue

		sed -i "s/^[[:blank:]]*$confKey[[:blank:]]*=/\t$confKey = $confValue/" $updatedFile
	fi


done
