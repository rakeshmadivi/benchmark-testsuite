#!/bin/bash
#--------------- STREAM Test ---------------------
stream_tests()
{
	: '
	echo -e "Do you want to run stream test?(y/n)"
	read op

	if [ "$op" = "y" ];then
		'#end-comment
		#location=`locate multi-streaam-scaling`
		if [ ! -d "stream-scaling" ];then
			echo -e "\nStream-scaling Folder not found in current working path.\nDownloading stream-scaling....\n"
			git clone --recursive https://github.com/jainmjo/stream-scaling.git
		fi
		cd stream-scaling
		outfile=stream_scaling_benchmark.txt
		iters=4
		testname=stream_scale_${iters}iters
		./multi-stream-scaling $iters  $testname
		./multi-averager $testname > stream.txt

		# Installing gnuplot
		which gnuplot 1>/dev/null 2>&1 || [ $? -ne 0 ] && sudo apt-get install gnuplot
		if [ "`which gnuplot`" != "" ];then
			echo -e "Plotting Triad..."
			gnuplot stream-plot
			echo -e "\nNOTE: If you want to plot for 'Scale', please edit find parameter to 'Scale' in stream-graph.py and re-run 'multi-averager'\n"
		fi
	: '
	else
		echo -e "STREAM TEST Cancelled by user...\n"
	fi
	'#end-comment
}
