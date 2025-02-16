#!/bin/sh

rm -f /tmp/mtk_dut.txt
killall mtk_dut

count=0
start_daemon=0
while [ $count -lt 20 ]; do
	echo "Wait $count seconds for WIFI interface up" >> /tmp/mtk_dut.txt

	inf1=`ifconfig | grep ra0 | awk '{print $1}' | sed -n 1p`
	if [ "$inf1" = "ra0" ]; then
		echo "$inf1 is up, run mtk_dut" >> /tmp/mtk_dut.txt
		start_daemon=1
	fi

	inf2=`ifconfig | grep rax0 | awk '{print $1}' | sed -n 1p`
	if [ "$inf2" = "rax0" ]; then
		echo "$inf2 is up, run mtk_dut" >> /tmp/mtk_dut.txt
		start_daemon=1
	fi

	if [ $start_daemon -eq 1 ]; then
		sleep 1
		mtk_dut ap br-lan 9000 &
		break
	fi
	sleep 1
	count=$((count + 1))
done
