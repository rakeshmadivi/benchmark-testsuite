#!/bin/bash

# Ref: https://documentation.suse.com/sles/11-SP4/html/SLES-all/cha-tuning-power.html
# Processor Operating States C-States
# ------------------------------------------
# 
# Mode | Definition
# C0 | Operational state. CPU fully turned on.
# 
# C1 | First idle state. Stops CPU main internal clocks via software. Bus interface unit and APIC are kept running at full speed.
# 
# C2 | Stops CPU main internal clocks via hardware. State where the processor maintains all software-visible states, but may take longer to wake up through interrupts.
# 
# C3 | Stops all CPU internal clocks. The processor does not need to keep its cache coherent, but maintains other states. Some processors have variations of the C3 state that differ in how long it takes to wake the processor through interrupts.

# Processor Performance States P-States
# ------------------------------------------
# P-states are operational states that relate to CPU frequency and voltage.
# P0 is always the highest-performance state. Higher P-state numbers represent slower processor speeds and lower power consumption.

# Using following options in boot command line
# processor.max_cstates=1 idle=POLL 

# Power Management QoS
# /dev/cpu_dma_latency

# The file /dev/cpu_dma_latency is the interface which when opened registers a quality-of-service request for latency with the operating system. A program should open /dev/cpu_dma_latency, write a 32-bit number to it representing a maximum response time in microseconds and then keep the file descriptor open while low-latency operation is desired.  Writing a zero means that you want the fastest response time possible

# Opening /dev/cpu_dma_latency and writing a zero to it will prevent transitions to deep sleep states while the file descriptor is held open. Additionally, writing a zero to it emulates the idle=poll behavior.

qos="0x$(sudo hexdump -C /dev/cpu_dma_latency | head -1 | xargs | cut -f1 -d '|' | cut -f2- -d' ' --output-delimiter=$'\n' | rev | xargs | rev | tr -d ' ')"
echo "Current Power Management QoS set to = $(($qos)) us"

# Check if cpufreq subsystem is enabled

[ ! -z "$(ls /sys/devices/system/cpu/cpu*/cpufreq)" ] && echo "Frequency Subsystem Enabled =  true"
