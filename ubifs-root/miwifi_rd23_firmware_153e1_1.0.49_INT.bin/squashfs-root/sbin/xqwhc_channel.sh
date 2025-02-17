#!/bin/sh
# Copyright (C) 2021 Xiaomi

usage() {
	echo "$0 get_chan_2g"
	echo "$0 get_chan_5g"
	echo "$0 set_chan_2g XX"
	echo "$0 set_chan_5g XX"
	exit 1
}

get_chan_2g() {
	local ap_ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local channel_2g="`mtknetlink_cli $ap_ifname_2g getChannel|cut -d ':' -f 3`"
	echo "$channel_2g"
}

get_chan_5g() {
	local ap_ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local channel_5g="`mtknetlink_cli $ap_ifname_5g getChannel|cut -d ':' -f 3`"
	echo "$channel_5g"
}

set_chan_2g() {
	local channel=$1
	local ap_ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	iwpriv $ap_ifname_2g set Channel=$channel
}

set_chan_5g() {
	local new_channel=$1
	local netmode=$(uci -q get xiaoqiang.common.NETMODE)
	if [ "$netmode" = "whc_re" ]; then
		local ap_ifname_5g=$(uci -q get misc.wireless.ifname_5G)
		local current_channel="`iwlist $ap_ifname_5g channel | grep "Current Channel" | grep -Eo "[0-9]+"`"
		#local bit_rate=`iwinfo $ap_ifname_5g info | grep 'Bit Rate' | awk -F: '{print $2}' | awk '{gsub(/^\s+|\s+$/, "");print}'`

		#if [ "$new_channel" != "$current_channel" -a "$bit_rate" != "unknown" ] ; then
		if [ "$new_channel" != "$current_channel" ] ; then
			iwpriv $ap_ifname_5g set Channel=$new_channel
			echo "xqwhc_channel.sh set_chan_5g $new_channel" > /dev/console
			ifconfig $ap_ifname_5g down
			ifconfig $ap_ifname_5g up
		fi
	fi
}

case "$1" in
	get_chan_2g)
	get_chan_2g
	;;
	get_chan_5g)
	get_chan_5g
	;;
	set_chan_2g)
	set_chan_2g "$2"
	;;
	set_chan_5g)
	set_chan_5g "$2"
	;;
	*)
	usage
	;;
esac
