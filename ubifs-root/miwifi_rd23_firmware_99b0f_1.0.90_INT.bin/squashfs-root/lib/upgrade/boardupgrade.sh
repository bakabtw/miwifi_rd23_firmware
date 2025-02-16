#!/bin/sh
#

# RD23 upgrade file

. /lib/upgrade/libupgrade.sh

klogger() {
    local msg1="$1"
    local msg2="$2"

    if [ "$msg1" = "-n" ]; then
        echo -n "$msg2" >> /dev/kmsg 2>/dev/null
        echo -n "$msg2"
    else
        echo "$msg1" >> /dev/kmsg 2>/dev/null
        echo "$msg1"
    fi  

    return 0
}

board_prepare_upgrade() {
    # gently stop pppd, let it close pppoe session
    ifdown wan
    timeout=5
    while [ $timeout -gt 0 ]; do
        pidof pppd >/dev/null || break
        sleep 1
        let timeout=timeout-1
    done

    # down backhauls
    #ifconfig eth3 down
    #ifconfig wl01 down
    #ifconfig wl11 down

    # clean up upgrading environment
    # call shutdown scripts with some exceptions
    wait_stat=0
    klogger "@Shutdown service "
    for i in /etc/rc.d/*; do
        # filter out K01reboot-wdt and K99umount network dnsmasq

        case $i in
            *reboot-wdt | *umount | *network | *dnsmasq | *xqled)
                klogger "$i skipped"
                continue
            ;;
        esac

        [ -x "$i" ] || continue

        # wait for high-priority K* scripts to finish
        if echo "$i" | grep -qE "K7"; then
            if [ $wait_stat -eq 0 ]; then
                wait
                sleep 2
                wait_stat=1
            fi
            klogger "  service $i shutdown 2>&1"
            $i shutdown 2>&1
        else
            klogger "  service $i shutdown 2>&1 &"
            $i shutdown 2>&1 &
        fi
    done

    # flush cache and dump meminfo
    sync
    echo 3>/proc/sys/vm/drop_caches
    klogger "@dump meminfo"
    klogger "`cat /proc/meminfo | xargs`"
}

board_start_upgrade_led() {
    /usr/sbin/xqled sys_ota > /dev/null 2>&1
}

board_system_upgrade() {
    local filename=$1
	local secList="BL2 FIP crash firmware"
	
	# update sections
	for sec in $secList; do
		flash_section $sec $filename
	done
	
}
