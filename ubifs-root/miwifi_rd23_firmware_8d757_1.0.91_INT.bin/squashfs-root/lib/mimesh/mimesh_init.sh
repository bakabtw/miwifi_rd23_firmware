#!/bin/sh 

# mimesh upper abstract layer support

. /lib/functions.sh
. /lib/mimesh/mimesh_public.sh
. /lib/miwifi/miwifi_core_libs.sh

nw_cfg="/tmp/log/nw_cfg"

# check bh white mac_list, return mac_list if valid
# $1 input type, 2g/5g
# $2 output mac_list after check
__check_bh_vap_mac_list()
{
	local mac_idx mac_list_t mac
	local type="$1"
	local macnum="`eval echo '$'{bh_macnum_"${type}"g}`"
	local maclist="`eval echo '$'{bh_maclist_"${type}"g}`"
	[ -n "${maclist}" ] && {
		for mac_idx in $(seq 1 ${macnum}); do
			mac="`echo $maclist | awk -F ',' '{print $jj}' jj="$mac_idx"`"
			mac="`echo $mac | sed 's/ //g' | sed 'y/abcdef/ABCDEF/'`"
			echo "$mac" | grep -q -o -E '^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$' && {
				mac_list_t="${mac_list_t}${mac_list_t:+","}${mac}"
			}
		done
	}
	eval "$2=$mac_list_t"
}

__init_wifi_cap()
{
	local iface="$1"
	local ifname_5g=$(uci -q get misc.wireless.iface_5g_ifname)
	local ifname_2g=$(uci -q get misc.wireless.iface_2g_ifname)
	local ifname_bh_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	config_get ifname $iface ifname
	# setup backhual ap iface
	if [ "$ifname" == "$ifname_bh_5g" ]; then
		local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
		local meshid=$(uci -q get xiaoqiang.common.NETWORK_ID)
		local support_mesh_ver4=$(mesh_cmd support_mesh_version 4)
		local mesh_version=$(mesh_cmd max_mesh_version)

		echo "_init_wifi_cap mesh_version = $mesh_version"

		uci -q set wireless.${iface}.ssid="$bh_ssid"
		uci -q set wireless.${iface}.encryption="$bh_mgmt"
		uci -q set wireless.${iface}.key="$bh_pswd"
		uci -q set wireless.${iface}.disabled=0
		uci -q set wireless.${iface}.hidden='1'
		uci -q set wireless.${iface}.backhaul='1'
		uci -q set wireless.${iface}.mesh_ver="$mesh_version"
		uci -q set wireless.${iface}.mesh_apmac="$lanmac"
		uci -q set wireless.${iface}.mesh_aplimit='9'
		uci -q set wireless.${iface}.wds='1'
		uci -q set wireless.${iface}.mesh_id="$meshid"

		return
	fi

	# setup main 2g and 5g iface
	if [ "$ifname" != "$ifname_5g" -a "$ifname" != "$ifname_2g" ]; then
		return
	fi

	local main_ssid main_encryption main_pwd
	if [ "$bsd" -eq 0 ]; then
		if [ "$ifname" == "$ifname_5g" ]; then
			main_ssid=$ssid_5g
			main_encryption=$mgmt_5g
			main_pwd=$pswd_5g
		else
			main_ssid=$ssid_2g
			main_encryption=$mgmt_2g
			main_pwd=$pswd_2g
		fi
	else
		main_ssid=$whc_ssid
		main_encryption=$whc_mgmt
		main_pwd=$whc_pswd
		uci -q set wireless.${iface}.bsd='1'
	fi

	uci -q set wireless.${iface}.miwifi_mesh='0'
	uci -q set wireless.${iface}.ssid="$main_ssid"
	uci -q set wireless.${iface}.disabled='0'
	uci -q set wireless.${iface}.encryption="$main_encryption"

	case "$main_encryption" in
		none)
			;;
		mixed-psk|psk2)
			uci -q set wireless.${iface}.key="$main_pwd"
			;;
		psk2+ccmp)
			uci -q set wireless.${iface}.sae='1'
			uci -q set wireless.${iface}.sae_password="$main_pwd"
			uci -q set wireless.${iface}.ieee80211w='1'
			;;
		ccmp)
			uci -q set wireless.${iface}.sae='1'
			uci -q set wireless.${iface}.sae_password="$main_pwd"
			uci -q set wireless.${iface}.ieee80211w='2'
			;;
	esac
}

# netmode: 1 setmode 0 clearmode
# mode: whc_cap/whc_re is used for trafficd tbus
__set_netmode()
{
	local swt="$1"
	local netmode=$(uci -q get xiaoqiang.common.NETMODE)

	# netmode
	if [ "$swt" -eq 0 ]; then
		uci -q delete xiaoqiang.common.NETMODE
		nvram set mode=Router
	else
		if [ "$2" = "cap" ]; then
			if [ "$netmode" = "wifiapmode" -o "$netmode" = "lanapmode" ]; then
				uci -q set xiaoqiang.common.CAP_MODE="ap"
			else
				uci -q set xiaoqiang.common.NETMODE="whc_cap"
			fi
		else
			local mode="whc_$2"
			uci -q set xiaoqiang.common.NETMODE="$mode"
			[ "$2" = "re" ] && nvram set mode=AP
		fi
	fi

	uci commit xiaoqiang
	nvram commit

	return 0
}

## network cfg init on RE
__init_network_re()
{
	MIMESH_LOGI " setup network cfg on $whc_role "

	network_re_mode

	[ -f "$nw_cfg" ] && {
		local ip="`cat $nw_cfg | awk -F ':' '/ip/{print $2}'`"
		[ -n "$ip" ] && {
			local subnet="`cat $nw_cfg | awk -F ':' '/subnet/{print $2}'`"
			local dns="`cat $nw_cfg | awk -F ':' '/dns/{print $2}'`"
			local router="`cat $nw_cfg | awk -F ':' '/router/{print $2}'`"
			local hostname="`cat $nw_cfg | awk -F ':' '/ap_hostname/{print $2}'`"
			local vendorinfo="`cat $nw_cfg | awk -F ':' '/vendorinfo/{print $2}'`"
			local netmask="${subnet:-255.255.255.0}"
			local mtu="${mtu:-1500}"
			local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)

			MIMESH_LOGI " @@@@@@ ============ mesh re set ip=$ip gw=$router."

			dns="${dns:-$router}"
			uci -q set xiaoqiang.common.ap_hostname=$hostname
			if [ "$cap_mode" != "ap" ] ; then
				uci -q set xiaoqiang.common.vendorinfo="$vendorinfo"
			fi  
			uci commit xiaoqiang

			uci -q set network.lan=interface
			uci -q set network.lan.type=bridge
			uci -q set network.lan.proto=dhcp
			uci -q set network.lan.ipaddr=$ip
			uci -q set network.lan.netmask=$netmask
			uci -q set network.lan.gateway=$router
			uci -q set network.lan.mtu=$mtu
			uci -q del network.lan.dns
			uci -q del network.vpn
			for d in $dns
			do
				uci -q add_list network.lan.dns=$d
			done

			uci commit network

			/usr/sbin/ip_conflict.sh br-lan
		}
	}

	uci -q set network.lan.proto=dhcp
	uci commit network

	/usr/sbin/vasinfo_fw.sh off 2>/dev/null

	/etc/init.d/trafficd stop
	/etc/init.d/odhcpd stop

	ifdown vpn 2>/dev/null

	# workaround for lan.ipaddr in multiple init situation
	kill -SIGUSR1 `pidof udhcpc | xargs` 2>/dev/null
}

__update_wifi_cfg()
{
	local ifname="$1"
	local ssid="$2"
	local encryption="$3"
	local key="$4"

	MIMESH_LOGI "__update_wifi_cfg: $1 $2 $3 $4"
	case "$encryption" in
	none)
		iwpriv $ifname set AuthMode=OPEN
		iwpriv $ifname set EncrypType=NONE
		iwpriv $ifname set PMFMFPC=0
		iwpriv $ifname set PMFMFPR=0
		iwpriv $ifname set PMFSHA256=0
		;;
	psk2)
		iwpriv $ifname set AuthMode=WPA2PSK
		iwpriv $ifname set EncrypType=AES
		iwpriv $ifname set PMFMFPC=0
		iwpriv $ifname set PMFMFPR=0
		iwpriv $ifname set PMFSHA256=0
		iwpriv $ifname set SSID="$ssid"
		iwpriv $ifname set WPAPSK="$key"
		;;
	mixed-psk)
		iwpriv $ifname set AuthMode=WPAPSKWPA2PSK
		iwpriv $ifname set EncrypType=TKIPAES
		iwpriv $ifname set PMFMFPC=0
		iwpriv $ifname set PMFMFPR=0
		iwpriv $ifname set PMFSHA256=0
		iwpriv $ifname set SSID="$ssid"
		iwpriv $ifname set WPAPSK="$key"
		;;
	psk2+ccmp)
		iwpriv $ifname set AuthMode=WPA2PSKWPA3PSK
		iwpriv $ifname set EncrypType=AES
		iwpriv $ifname set PMFMFPC=1
		iwpriv $ifname set PMFMFPR=0
		iwpriv $ifname set PMFSHA256=1
		iwpriv $ifname set SSID="$ssid"
		iwpriv $ifname set WPAPSK="$key"
		;;
	ccmp)
		iwpriv $ifname set AuthMode=WPA3PSK
		iwpriv $ifname set EncrypType=AES
		iwpriv $ifname set PMFMFPC=1
		iwpriv $ifname set PMFMFPR=1
		iwpriv $ifname set PMFSHA256=1
		iwpriv $ifname set SSID="$ssid"
		iwpriv $ifname set WPAPSK="$key"
		;;
	esac

	iwpriv $ifname set SSID="$ssid"
}

__init_wifi_re()
{
	local iface="$1"
	local ifname_5g=$(uci -q get misc.wireless.iface_5g_ifname)
	local ifname_2g=$(uci -q get misc.wireless.iface_2g_ifname)
	local ifname_bh_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local ifname_bh_5g_sta=$(uci get misc.backhauls.backhaul_5g_sta_iface)

	MIMESH_LOGI " setup wifi cfg on $whc_role iface = $iface mesh_type = $mesh_type"

	config_get ifname $iface ifname
	# setup backhual ap iface
	if [ "$ifname" == "$ifname_bh_5g" ]; then
		local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
		local meshid=$(uci -q get xiaoqiang.common.NETWORK_ID)
		local support_mesh_ver4=$(mesh_cmd support_mesh_version 4)
		local mesh_version=$(mesh_cmd max_mesh_version)

		__update_wifi_cfg "$ifname" "$bh_ssid" "$bh_mgmt" "$bh_pswd"

		iwpriv $ifname set ApMWDS=1
		iwpriv $ifname set mesh_id="$meshid"
		iwpriv $ifname set miwifi_mesh_apmac="$lanmac"
		iwpriv $ifname set miwifi_backhual=1
		iwpriv $ifname set mesh_ver="$mesh_version"

		uci -q set wireless.${iface}.ssid="$bh_ssid"
		uci -q set wireless.${iface}.encryption="$bh_mgmt"
		uci -q set wireless.${iface}.key="$bh_pswd"
		uci -q set wireless.${iface}.disabled='0'
		uci -q set wireless.${iface}.backhaul='1'
		uci -q set wireless.${iface}.hidden='1'
		uci -q set wireless.${iface}.mesh_ver="$mesh_version"
		uci -q set wireless.${iface}.mesh_apmac="$lanmac"
		uci -q set wireless.${iface}.wds='1'
		uci -q set wireless.${iface}.mesh_id="$meshid"

		# setup macfiter policy
		local mac_list
		__check_bh_vap_mac_list "5" mac_list
		# set bh ssid macfilter on re no matter whether mac_list is existed
		[ -n "$mac_list" ] && {
			mac_list="`echo $mac_list | sed "s/,/ /g"`"
			uci -q set wireless.${iface}.macfilter='allow'
			uci -q delete wireless.${iface}.maclist
			for mac in $mac_list; do
				uci -q add_list wireless.${iface}.maclist="$mac"
			done
		}

		return
	fi

	# mesh_type = apsta, re_connect already configured bh sta uci cfg
	# mesh_type = wps, setup backhual sta iface
	if [ "$ifname" == "$ifname_bh_5g_sta" -a "$mesh_type" != "apsta" ]; then
		uci -q set wireless.${iface}.ssid="$bh_ssid"
		uci -q set wireless.${iface}.encryption="$bh_mgmt"
		uci -q set wireless.${iface}.key="$bh_pswd"
		uci -q set wireless.${iface}.disabled="$eth_init"
		uci -q set wireless.${iface}.wds='1'

		[ "$eth_init" == "0" ] && {
			ifconfig $ifname down
			sleep 1
			ifconfig $ifname up
			iwpriv $ifname set ApCliEnable=0
			iwpriv $ifname set ApCliMWDS=1
			iwpriv $ifname set ApCliAuthMode=WPA2PSK
			iwpriv $ifname set ApCliEncrypType=AES
			iwpriv $ifname set ApCliSsid="$bh_ssid"
			iwpriv $ifname set ApCliWPAPSK="$bh_pswd"
			iwpriv $ifname set ApCliSsid="$bh_ssid"
			iwpriv $ifname set ApCliBssid="00:00:00:00:00:00"
			iwpriv $ifname set ApCliEnable=1
			iwpriv $ifname set ApCliAutoConnect=3

			ubus call network.interface.lan add_device "{\"name\":\"$ifname\"}"
		}
		return
	fi

	# setup main 2g and 5g iface
	if [ "$ifname" != "$ifname_5g" -a "$ifname" != "$ifname_2g" ]; then
		return
	fi

	local main_ssid main_encryption main_pwd
	if [ "$bsd" -eq 0 ]; then
		if [ "$ifname" == "$ifname_5g" ]; then
			main_ssid=$ssid_5g
			main_encryption=$mgmt_5g
			main_pwd=$pswd_5g
		else
			main_ssid=$ssid_2g
			main_encryption=$mgmt_2g
			main_pwd=$pswd_2g
		fi
	else
		main_ssid=$whc_ssid
		main_encryption=$whc_mgmt
		main_pwd=$whc_pswd
		uci -q set wireless.${iface}.bsd='1'
	fi

	__update_wifi_cfg "$ifname" "$main_ssid" "$main_encryption" "$main_pwd"
	iwpriv $ifname set miwifi_mesh=0

	uci -q set wireless.${iface}.miwifi_mesh='0'
	uci -q set wireless.${iface}.ssid="$main_ssid"
	uci -q set wireless.${iface}.disabled='0'
	uci -q set wireless.${iface}.encryption="$main_encryption"

	case "$main_encryption" in
		none)
			;;
		mixed-psk|psk2)
			uci -q set wireless.${iface}.key="$main_pwd"
			;;
		psk2+ccmp)
			uci -q set wireless.${iface}.sae='1'
			uci -q set wireless.${iface}.sae_password="$main_pwd"
			uci -q set wireless.${iface}.ieee80211w='1'
			;;
		ccmp)
			uci -q set wireless.${iface}.sae='1'
			uci -q set wireless.${iface}.sae_password="$main_pwd"
			uci -q set wireless.${iface}.ieee80211w='2'
			;;
	esac
}

## check if wifi has config backhaul
# 2 : uninit
# 1: init and wifi cfg change (ssid + key)
# 0: init and wifi cfg NO change
export WIFI_UNINIT=2
export WIFI_INIT_CHANGE=1   #init change need a restore
export WIFI_INIT_NOCHANGE=0
# only call before next cap/re retry, thus we can save wifi up time
mimesh_preinit()
{
	local role="$1"
	MIMESH_LOGI "*preinit"

	ret=$WIFI_INIT_NOCHANGE

	local netmode=$(uci -q get xiaoqiang.common.NETMODE)
	if [ $ret -eq $WIFI_INIT_NOCHANGE ]; then
		if [ "$role" = "cap" -o "$role" = "CAP" ]; then
			[ "$netmode" = "whc_cap" ] || {
				[ "$netmode" = "wifiapmode" -o "$netmode" = "lanapmode" ] && {
					[ "`uci -q get xiaoqiang.common.CAP_MODE`" = "ap" ] || {
						ret=$WIFI_INIT_CHANGE
					}
				} || {
					ret=$WIFI_INIT_CHANGE
				}
			}
		fi
	fi

	MIMESH_LOGI "*preinit done, ret=$ret"
	return $ret
}

__init_cap()
{
	MIMESH_LOGI " __init_cap: continue..."

	__set_netmode 1 cap

	config_load wireless
	config_foreach __init_wifi_cap wifi-iface
	uci commit wireless

	if [ "$restart_network" != "0" ]; then
		/etc/init.d/network reconfig_switch
		ubus call network reload
		/sbin/wifi update
	fi

	return 0
}

init_re_network()
{
	MIMESH_LOGD " re_network_init: continue..."

	__set_netmode 1 re
	__init_network_re
	/etc/init.d/network reconfig_switch
	ubus call network reload
	(/etc/init.d/firewall stop;/etc/init.d/firewall disable) &
}

__init_re()
{
	local lan_ports
	lan_ports=$(port_map port class lan)

	MIMESH_LOGD " __init_re: continue..."

	config_load wireless
	config_foreach __init_wifi_re wifi-iface
	uci commit wireless

	if [ "$mesh_type" != "apsta" ]; then
		__set_netmode 1 re
		__init_network_re
		/etc/init.d/network reconfig_switch
		ubus call network reload
	fi

	whc_re_open

	network_accel_hook "whc_re" "open"

	/etc/init.d/ipv6 ip6_fw close

	/sbin/wifi update
	/etc/init.d/timezone restart
	/etc/init.d/messagingagent.sh restart
	/etc/init.d/miio_client reload
	/usr/sbin/port_service restart

	phyhelper restart "$lan_ports"

	[ "$eth_init" != "1" ] && {
		local ifname_bh_5g_sta=$(uci get misc.backhauls.backhaul_5g_sta_iface)
		ifconfig $ifname_bh_5g_sta down
		sleep 1
		ifconfig $ifname_bh_5g_sta up
		sleep 1
		iwpriv $ifname_bh_5g_sta set ApCliAutoConnect=3
	}

	return 0
}

# check if ssid & encryption & key changed
# 1: wifi cfg changed
# 0: wifi cfg NO change
__check_wifi_cfg_no_changed()
{
	local key word word_cur

	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname=\'$ifname_2g\'" | awk -F"." '{print $2}')
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname=\'$ifname_5g\'" | awk -F"." '{print $2}')

	local ssid_5g_cur="`uci -q get wireless.$iface_5g.ssid`"
	local mgmt_5g_cur="`uci -q get wireless.$iface_5g.encryption`"
	local pswd_5g_cur="`uci -q get wireless.$iface_5g.key`"
	local ssid_2g_cur="`uci -q get wireless.$iface_2g.ssid`"
	local mgmt_2g_cur="`uci -q get wireless.$iface_2g.encryption`"
	local pswd_2g_cur="`uci -q get wireless.$iface_2g.key`"
	local key_lists="ssid_5g mgmt_5g pswd_5g ssid_2g mgmt_2g pswd_2g"
	for key in $key_lists; do
		if [ "$bsd" -eq 0 ]; then
			word="`eval echo '$'"$key"`"
		else
			word="`eval echo '$'"whc_${key:0:4}"`"
		fi
		word_cur="`eval echo '$'"${key}_cur"`"
		[ "$word" != "$word_cur" ] && {
			MIMESH_LOGI "      wifi init with cfg changed, [$word_cur]->[$word]"
			MIMESH_LOGI "      [$ssid_5g_cur][$mgmt_5g_cur][$pswd_5g_cur][$ssid_2g_cur][$mgmt_2g_cur][$pswd_2g_cur]->"
			[ "$bsd" -eq 0 ] && {
				MIMESH_LOGI "      [$ssid_5g][$mgmt_5g][$pswd_5g][$ssid_2g][$mgmt_2g][$pswd_2g]"
			} || {
				MIMESH_LOGI "      [$whc_ssid][$whc_mgmt][$whc_pswd]"
			}
			return 1
		}
	done

	return 0
}

mimesh_init_done()
{
	local role="$1"

	local mesh_version=$(uci -q get xiaoqiang.common.MESH_VERSION)
	[ -z "$mesh_version" ] && {
		uci -q set xiaoqiang.common.MESH_VERSION=$(mesh_cmd max_mesh_version)
		uci commit xiaoqiang
	}

	MIMESH_LOGI " config init done. postpone handle mi services."
	uci -q set xiaoqiang.common.INITTED=YES
	uci commit xiaoqiang

	# turn off web init redirect page
	/usr/sbin/sysapi webinitrdr set off &

	# set wps state for qca wifi
	/usr/sbin/set_wps_state 2 &

	#xqled mesh_finish

	if [ "$role" = "re" ]; then
		(/etc/init.d/firewall stop;/etc/init.d/firewall disable) &
		/etc/init.d/meshd stop

		# mesh4.0通过apsta方式组网，re初始化完成后由miwifi-discovery进行关灯操作，此处取消关掉，与
		# cap进行关掉同步。
		if [ "$mesh_type" != "apsta" ]; then
			# Re初始化成功后由自身进程立即执行取消闪灯的操作，不依赖于cab_meshd进程退出前的取消闪灯。
			# 因实际运行过程中出现light_blink.status文件未删除导致灯一直闪烁的异常
			xqled mesh_finish
			MIMESH_LOGI "re change light status."
		fi
	fi

	if [ "$role" = "cap" ]; then
		# for CAP, led blue on after init
		led_check

		# 不是mesh_ver4的路由以及mesh_ver4的单只装在此处进行firewall restart，与之前mesh逻辑保持一致
		[ "$support_mesh_ver4" != "1" -o "$meshsuite" != "1" ] && /etc/init.d/firewall restart &
		[ "$restart_miwifi_discovery" == "1" ] && /etc/init.d/miwifi-discovery restart &

		MIMESH_LOGI "Device was initted! clear br-port isolate_mode!"
		echo 0 > /sys/devices/virtual/net/wl0/brport/isolate_mode 2>&1
		echo 0 > /sys/devices/virtual/net/wl1/brport/isolate_mode 2>&1
	fi

	/etc/init.d/wan_check restart
	# trafficd move into dhcp_apclient.sh callback
	/etc/init.d/mosquitto restart &

	# mesh_ver4, restart xq_info_sync_mqtt only config changed after cap initted
	if [ "$restart_xq_info_sync_mqtt" == "1" -o "$support_mesh_ver4" != "1" ]; then
		/etc/init.d/xq_info_sync_mqtt restart &
	fi
	/etc/init.d/dnsmasq restart &
	/etc/init.d/xqbc restart &
	/etc/init.d/tbusd restart &
	/etc/init.d/trafficd restart &
	/etc/init.d/xiaoqiang_sync restart &
	/etc/init.d/messagingagent.sh restart &
	/etc/init.d/miio_client reload &
	/etc/init.d/miwifi-roam restart &
	/etc/init.d/topomon restart &

	return 0
}

mimesh_init()
{
	export bsd=1
	export method="$(json_get_value "$1" method)"
	export params="$(json_get_value "$1" params)"
	
	local eth_init=$2
	[ -z "$2" ] && eth_init=0
	export eth_init="$eth_init"

	local para_bsd="`json_get_value \"$params\" \"bsd\"`"
	[ "$para_bsd" = "0" ] && bsd=0
	MIMESH_LOGI " keys:<bsd:$bsd>"
	[ "$bsd" -eq 0 ] && key_list="whc_role ssid_2g mgmt_2g pswd_2g ssid_5g mgmt_5g pswd_5g" || key_list="whc_role whc_ssid whc_pswd whc_mgmt"

	key_list="$key_list bh_ssid bh_mgmt bh_pswd bh_macnum_5g bh_maclist_5g"

	for key in $key_list; do
		eval "export $key=\"\""
		eval "$key=\"`json_get_value \"$params\" \"$key\"`\""

		[ -z "$key" ] && {
			MIMESH_LOGE " error whc_init, no $key exist"
			message="\" error whc_init, no $key exist\""
			return $ERR_PARAM_NON
		}
	done

	if [ "$bsd" -eq 0 ]; then
		[ -z "$ssid_2g" ] && ssid_2g="!@Mi-son" || ssid_2g="`printf \"%s\" \"$ssid_2g\" | base64 -d`"
		[ -z "$mgmt_2g" ] && mgmt_2g="mixed-psk"
		[ -z "$pswd_2g" ] && mgmt_2g="none" || pswd_2g="`printf \"%s\" \"$pswd_2g\" | base64 -d`"
		[ -z "$ssid_5g" ] && ssid_5g="!@Mi-son_5G" || ssid_5g="`printf \"%s\" \"$ssid_5g\" | base64 -d`"
		[ -z "$mgmt_5g" ] && mgmt_5g="mixed-psk"
		[ -z "$pswd_5g" ] && mgmt_5g="none" || pswd_5g="`printf \"%s\" \"$pswd_5g\" | base64 -d`"

		[ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
		[ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2+ccmp"
		[ -z "$bh_pswd" ] && bh_mgmt_5g="none"
		[ -z "$bh_macnum_2g" -o "$bh_macnum_2g" == "0" ] && bh_maclist_2g=""
		[ -z "$bh_macnum_5g" -o "$bh_macnum_5g" == "0" ] && bh_maclist_5g=""
		MIMESH_LOGI " keys:<$whc_role>,<$bsd>,<$ssid_2g>,<$pswd_2g>,<$mgmt_2g>,<$ssid_5g>,<$pswd_5g>,<$mgmt_5g>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
		MIMESH_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"
	else
		[ -z "$whc_ssid" ] && whc_ssid="!@Mi-son" || whc_ssid="`printf \"%s\" \"$whc_ssid\" | base64 -d`"
		[ -z "$whc_mgmt" ] && whc_mgmt="mixed-psk"
		[ -z "$whc_pswd" ] && whc_mgmt="none" || whc_pswd="`printf \"%s\" \"$whc_pswd\" | base64 -d`"

		[ -z "$bh_ssid" ] && bh_ssid_5g="MiMesh_A1B2"
		[ -z "$bh_mgmt" ] && bh_mgmt_5g="psk2"
		[ -z "$bh_pswd" ] && bh_mgmt_5g="none"
		[ -z "$bh_macnum_2g" -o "$bh_macnum_2g" == "0" ] && bh_maclist_2g=""
		[ -z "$bh_macnum_5g" -o "$bh_macnum_5g" == "0" ] && bh_maclist_5g=""
		MIMESH_LOGI " keys:<$whc_role>,<$bsd>,<$whc_ssid>,<$whc_pswd>,<$whc_mgmt>,<$bh_ssid>,<$bh_pswd>,<$bh_mgmt>"
		MIMESH_LOGI " keys:<$bh_macnum_2g>,<$bh_maclist_2g>,<$bh_macnum_5g>,<$bh_maclist_5g>"
	fi

	case "$whc_role" in
		cap|CAP)
			# check if wireless is not default, then recreate it for a safe multi calling
			mimesh_preinit "$whc_role"
			ret=$?
			[ $ret -eq $WIFI_INIT_NOCHANGE ] || {
				[ "$support_mesh_ver4" == "1" ] && export restart_xq_info_sync_mqtt=1
				__init_cap
				ret=$?
			}
			;;
		re|RE)
			__init_re
			ret=$?
			;;
		*)
			MIMESH_LOGE " invalid role $whc_role"
			message="\" error whc_init, invalid role $whc_role\""
			ret=$ERR_PARAM_INV
			;;
	esac

	[ "$ret" -ne 0 ] && {
		MIMESH_LOGE "    init $whc_role error!"
	}

	MIMESH_LOGI " --- "
	return 0
}
