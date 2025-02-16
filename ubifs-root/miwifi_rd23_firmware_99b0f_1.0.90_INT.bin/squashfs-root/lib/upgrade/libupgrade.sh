#!/bin/sh

klogger() {
	local msg1="$1"
	local msg2="$2"

	if [ "$msg1" = "-n" ]; then
		echo -n "$msg2" >>/dev/kmsg 2>/dev/null
	else
		echo "$msg1" >>/dev/kmsg 2>/dev/null
	fi

	return 0
}

hndmsg() {
	if [ -n "$msg" ]; then
		echo "$msg"
		echo "$msg" >>/dev/kmsg 2>/dev/null

		echo $log >/proc/sys/kernel/printk
		stty intr ^C
		exit 1
	fi
}

uperr() {
	exit 1
}

get_mtd_device() {
	local partition_name=$1
	local mtd_dev=""

	grep ${partition_name} /proc/mtd -w | awk -F: '{print $1}'
}

pipe_upgrade_generic() {
	local package=$1
	local segment_name=$2
	local mtd_dev=$3
	local ret=0

	mkxqimage -c $package -f $segment_name
	if [ $? -eq 0 ]; then
		klogger -n "Burning $segment_name to $mtd_dev ..."

		exec 9>&1

		local pipestatus0=$( ( (mkxqimage -x $package -f $segment_name -n || echo $? >&8) |
			mtd write - /dev/$mtd_dev) 8>&1 >&9)
		if [ -z "$pipestatus0" -a $? -eq 0 ]; then
			ret=0
		else
			ret=1
		fi
		exec 9>&-
	fi

	return $ret
}

flash_section() {
	local sec=$1
	local package=$2
	local segment_name=""
	local mtd_dev=""
	local os_idx=0

	case "${sec}" in
	BL2)
		segment_name="preloader.bin"
		mtd_dev=$(get_mtd_device ${sec})
		;;
	FIP)
		segment_name="fip.bin"
		mtd_dev=$(get_mtd_device ${sec})
		;;
	crash)
		segment_name="crash.bin"
		mtd_dev=$(get_mtd_device ${sec})
		;;
	firmware)
		segment_name="firmware_ubi.bin"
		os_idx=$(nvram get flag_boot_rootfs)
		if [ ${os_idx:-1} -eq 0 ]; then
			mtd_dev=$(get_mtd_device ubi1)
		else
			mtd_dev=$(get_mtd_device ubi)
		fi
		;;
	*)
		echo "Section ${sec} ignored"
		return 1
		;;
	esac

	if [ -n "${segment_name}" -a -n ${mtd_dev} ]; then
		pipe_upgrade_generic ${package} ${segment_name} ${mtd_dev}
		if [ $? -eq 0 ]; then
			klogger "Done"
		else
			klogger "Error"
		fi
	else
		klogger "Error, failed to get segment_name and mtd_dev"
		return 1
	fi

	#klogger "Flashed ${sec}"
}

$1
