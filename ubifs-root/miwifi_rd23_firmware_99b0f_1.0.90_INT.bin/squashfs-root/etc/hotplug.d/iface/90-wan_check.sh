#!/bin/sh
#logger -p notice -t "hotplug.d" "90-wan_chech.sh: run because of $INTERFACE $ACTION"
#this file called 90-wan_light_chech.sh is renamed 90-wan_chech.sh. 
# cr_ip_conflict.lua is used to update the data in message-box which is used by XQMessageBox.lua 

wanif=$(uci -q get network.wan.ifname)
if [ "$INTERFACE" = "wan" -o "$INTERFACE" = "$wanif" ]; then
    [ "$ACTION" = "ifdown" -o "$ACTION" = "ifup" ] && {
        /usr/sbin/wan_check.sh reset &
		lua /usr/sbin/cr_ip_conflict.lua &
    }
fi
