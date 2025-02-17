#!/bin/sh
# Copyright (C) 2020 Xiaomi

. /lib/mimesh/mimesh_public.sh
. /lib/mimesh/mimesh_stat.sh
. /lib/mimesh/mimesh_init.sh

log() {
	logger -t "meshd connect: " -p9 "$1"
}

check_re_initted() {
	initted=`uci -q get xiaoqiang.common.INITTED`
	[ "$initted" == "YES" ] && { log "RE already initted. exit 0." ; exit 0; }
}

run_with_lock() {
	{
		log "$$, ====== TRY locking......"
		flock -x -w 60 1000
		[ $? -eq "1" ] && { log "$$, ===== GET lock failed. exit 1" ; exit 1 ; }
		log "$$, ====== GET lock to RUN."
		$@
		log "$$, ====== END lock to RUN."
	} 1000<>/var/log/mesh_connect_lock.lock
}

usage() {
	echo "$0 re_start xx:xx:xx:xx:xx:xx"
	echo "$0 help"
	exit 1
}

eth_down() {
	local ifnames=$(uci -q get network.lan.ifname)
	local wan_ifname=$(uci -q get network.wan.ifname)
	for if_name in $ifnames
	do
		ifconfig $if_name down
	done

	[ -n "$wan_ifname" ] && {
		ifconfig $wan_ifname down
	}
}

eth_up() {
	local ifnames=$(uci -q get network.lan.ifname)
	local wan_ifname=$(uci -q get network.wan.ifname)

	for if_name in $ifnames
	do
		ifconfig $if_name up
	done

	[ -n "$wan_ifname" ] && {
		ifconfig $wan_ifname up
	}
}

set_network_id() {
	local bh_ssid=$1
	local pre_id=$(uci -q get xiaoqiang.common.NETWORK_ID)
	local new_id=$(echo "$bh_ssid" | md5sum | cut -c 1-8)
	if [ -z "$pre_id" -o "$pre_id" != "$new_id" ]; then
		uci set xiaoqiang.common.NETWORK_ID="$new_id"
		uci commit xiaoqiang
	fi
}

# statpoint to record if meshed
set_meshed_flag() {
	uci -q set xiaoqiang.common.MESHED="YES"
	uci commit xiaoqiang
}

# not used by others
cap_close_wps() {
	local ifname=$(uci -q get misc.wireless.ifname_5G)

	iwpriv $ifname set WscStop=1
	iwpriv $ifname set miwifi_mesh=3
}

cap_disable_wps_trigger() {
	local ifname=$1

	iwpriv $ifname set miwifi_mesh=3
}

re_clean_vap() {
	local ifname=$(uci -q get misc.wireless.apclient_5G)
	local ifname_bh5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	local lanip=$(uci -q get network.lan.ipaddr)
	if [ "$lanip" != "" ]; then
		ifconfig br-lan $lanip
	else
		ifconfig br-lan 192.168.31.1
	fi

	ubus call network.interface.lan remove_device "{\"name\":\"$ifname\"}"

	eth_up
	wifi
	iwpriv $ifname_bh5g set DfsEnable=1
}

mimesh_mtk_ping_capip()
{
	local cap_ip=$(uci -q get xiaoqiang.common.CAP_IP)

	if [ -n "$cap_ip" ]; then
		ping $cap_ip -c 1 -w 2 > /dev/null 2>&1
		[ $? -eq 0 ] && return 0
	else
		MIMESH_LOGI "  NO find valid cap ip!"
	fi

	return 1
}

# check RE assoc CAP status
# return 0: associated
# return else: not associated
mimesh_mtk_re_assoc_check()
{
	local iface_5g_bh=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
	[ -z "$iface_5g_bh" ] && iface_5g_bh="apclii0"

	local conn_status=$(iwpriv "$iface_5g_bh" Connstatus|grep Connected > /dev/null;echo $?)
	[ $conn_status -eq 0 ] && return 0

	mimesh_gateway_ping
	[ $? -eq 0 ] && return 0

	local gw_ip=$(uci -q get network.lan.gateway)
	local cap_ip=$(uci -q get xiaoqiang.common.CAP_IP)
	[ "$gw_ip"x != "$cap_ip"x ] && {
		mimesh_mtk_ping_capip
		return $?
	}

	return 1
}

check_re_init_status_v2() {
	for i in $(seq 1 60)
	do
		mimesh_mtk_re_assoc_check > /dev/null 2>&1
		[ $? = 0 ] && break
		sleep 2
	done

	mimesh_init_done "re"
	/etc/init.d/meshd stop
	/etc/init.d/cab_meshd stop
	eth_up

	# statpoint to record if meshed
	set_meshed_flag
}

do_re_init() {
	local ifname_bh5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local device=$(uci -q get misc.wireless.if_5G)

	# wps or apsta
	local mesh_type=${11}
	case "$mesh_type" in
		apsta) # mesh4.0
			export restart_xq_info_sync_mqtt=1
			export mesh_type="apsta"
			init_re_network
		;;
		*) # default to wps
			export mesh_type="wps"
		;;
	esac

	local ssid_2g="$1"
	local pswd_2g=
	local mgmt_2g=$3

	[ "$mgmt_2g" = "none" ] || pswd_2g="$2"

	local ssid_5g="$4"
	local pswd_5g=
	local mgmt_5g=$6

	[ "$mgmt_5g" = "none" ] || pswd_5g="$5"
	local bh_ssid=$(printf "%s" "$7" | base64 -d)
	local bh_pswd=$(printf "%s" "$8" | base64 -d)
	local bh_mgmt=$9

	set_network_id "$bh_ssid"

	touch /tmp/bh_maclist_5g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')

	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

	mimesh_init "$buff" "${10}"
	sleep 2
	check_re_init_status_v2
	network_accel_hook "start"
	iwpriv $ifname_bh5g set DfsEnable=1
	exit 0
}

do_re_init_bsd() {
	local ifname_bh5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local device=$(uci -q get misc.wireless.if_5G)

	# wps or apsta
	local mesh_type=$8
	case "$mesh_type" in
		apsta) # mesh4.0
			export restart_xq_info_sync_mqtt=1
			export mesh_type="apsta"
			init_re_network
		;;
		*) # default to wps
			export mesh_type="wps"
		;;
	esac

	local whc_ssid="$1"
	local whc_pswd=
	local whc_mgmt=$3

	[ "$whc_mgmt" = "none" ] || whc_pswd="$2"

	local bh_ssid=$(printf "%s" "$4" | base64 -d)
	local bh_pswd=$(printf "%s" "$5" | base64 -d)
	local bh_mgmt=$6

	set_network_id "$bh_ssid"

	touch /tmp/bh_maclist_5g
	local bh_maclist_5g=$(cat /tmp/bh_maclist_5g | sed 's/ /,/g')
	local bh_macnum_5g=$(echo $bh_maclist_5g | awk -F"," '{print NF}')

	do_re_init_json

	local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"RE\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"${bh_mgmt}\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

	mimesh_init "$buff" "$7"
	sleep 2
	check_re_init_status_v2
	network_accel_hook "start"
	iwpriv $ifname_bh5g set DfsEnable=1
	exit 0
}

do_re_init_json() {
	local jsonbuf=$(cat /tmp/extra_wifi_param 2>/dev/null)
	[ -z "$jsonbuf" ] && return

	#set max mesh version we can support
	local version_list=$(uci -q get misc.mesh.version)
	if [ -z "$version_list" ]; then
		log "version list is empty"
		return
	fi

	local max_version=1
	for version in $version_list; do
		if [ $version -gt $max_version ]; then
			max_version=$version
		fi
	done

	uci set xiaoqiang.common.MESH_VERSION="$max_version"
	uci commit

	local device_2g=$(uci -q get misc.wireless.if_2G)
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)

	local hidden_2g=$(json_get_value "$jsonbuf" "hidden_2g")
	local hidden_5g=$(json_get_value "$jsonbuf" "hidden_5g")
	local disabled_2g=$(json_get_value "$jsonbuf" "disabled_2g")
	local disabled_5g=$(json_get_value "$jsonbuf" "disabled_5g")
	local ax_2g=$(json_get_value "$jsonbuf" "ax_2g")
	local ax_5g=$(json_get_value "$jsonbuf" "ax_5g")
	local txpwr_2g=$(json_get_value "$jsonbuf" "txpwr_2g")
	local txpwr_5g=$(json_get_value "$jsonbuf" "txpwr_5g")
	local bw_2g=$(json_get_value "$jsonbuf" "bw_2g")
	local bw_5g=$(json_get_value "$jsonbuf" "bw_5g")
	local txbf_2g=$(json_get_value "$jsonbuf" "txbf_2g")
	local txbf_5g=$(json_get_value "$jsonbuf" "txbf_5g")
	local ch_2g=$(json_get_value "$jsonbuf" "ch_2g")
	local ch_5g=$(json_get_value "$jsonbuf" "ch_5g")
	local web_passwd=$(json_get_value "$jsonbuf" "web_passwd")
	local web_passwd256=$(json_get_value "$jsonbuf" "web_passwd256")

	/sbin/wifi backup_cfg

	uci set wireless.$device_5g.channel="$ch_5g"
	uci set wireless.$device_2g.channel="$ch_2g"

	uci set wireless.$device_5g.ax="$ax_5g"
	uci set wireless.$device_2g.ax="$ax_2g"

	uci set wireless.$device_5g.txpwr="$txpwr_5g"
	uci set wireless.$device_2g.txpwr="$txpwr_2g"

	uci set wireless.$device_5g.txbf="$txbf_5g"
	uci set wireless.$device_2g.txbf="$txbf_2g"

	uci set wireless.$device_2g.bw="$bw_2g"

	local support160_cur=$(uci -q get misc.features.support160Mhz)
	if [ "$support160_cur"x == "0"x -a "$bw_5g" == "160" ]; then
		uci set wireless.$device_5g.bw="80"
	else
		uci set wireless.$device_5g.bw="$bw_5g"
	fi

	local iface_2g=$(uci show wireless | grep -w "ifname='$ifname_2g'" | awk -F"." '{print $2}')
	local iface_5g=$(uci show wireless | grep -w "ifname='$ifname_5g'" | awk -F"." '{print $2}')

	uci set wireless.$iface_2g.hidden="$hidden_2g"
	uci set wireless.$iface_5g.hidden="$hidden_5g"
	
	uci set wireless.$iface_2g.disabled="0"
	uci set wireless.$iface_5g.disabled="0"
	uci commit wireless

	enc_mode=$(/usr/sbin/check_encrypt_mode.lua 2>>/dev/null)
	if [ "$enc_mode" = "1" ] && [ -n "$web_passwd256" ]; then
		uci set account.common.admin="$web_passwd256"
		uci set account.legacy.admin="$web_passwd"
		uci commit account
	elif [ -n "$web_passwd" ]; then
		uci -q set account.legacy=
		uci set account.common.admin="$web_passwd"
		uci commit account
	fi

	#cap_mode
	local cap_mode=$(json_get_value "$jsonbuf" "cap_mode")
	uci set xiaoqiang.common.CAP_MODE="$cap_mode"

	local cap_ip=$(json_get_value "$jsonbuf" "cap_ip")
	[ -n "$cap_ip" ] && uci -q set xiaoqiang.common.CAP_IP="$cap_ip"

	if [ "$cap_mode" = "ap" ]; then
		local vendorinfo=$(json_get_value "$jsonbuf" "vendorinfo")
		uci set xiaoqiang.common.vendorinfo="$vendorinfo"
	fi
	uci commit xiaoqiang

	local tz_index=$(json_get_value "$jsonbuf" "tz_index")
	local timezone=$(json_get_value "$jsonbuf" "timezone")
	local lang=$(json_get_value "$jsonbuf" "lang")
	local CountryCode=$(json_get_value "$jsonbuf" "CountryCode")

	if [ -n "$timezone" ]; then
		uci set system.@system[0].timezone=$timezone
		[ -n "$tz_index" ] && uci set system.@system[0].timezoneindex=$tz_index
		uci commit system
		/etc/init.d/timezone restart
	fi

	if [ -n "$CountryCode" -a "$CountryCode" != "CN" ]; then
		uci set luci.main.lang=$lang
		uci commit luci

		nvram set CountryCode=$CountryCode
		nvram commit

		local srv_region=
		local srv_section=
		local srv_name=
		local srv_domain=

		srv_region=$(uci get "country_mapping.$CountryCode.region")
		srv_section="server_${srv_region}"

		for srv_name in "S" "APP" "API" "STUN" "BROKER"; do
			if [ -n "$srv_region" ]; then
				srv_domain=$(uci get "server_mapping.$srv_section.$srv_name")
			else
				#if region not exist, try to use remote config
				srv_domain=$(json_get_value "$jsonbuf" "server_${srv_name}")
			fi

			uci set "miwifi.server.$srv_name=$srv_domain"
		done

		uci commit miwifi
	fi
}

cac_ctrl() {
	local cmd="$1"
	local ifname_bh5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	case "$cmd" in
		enable)
			iwpriv $ifname_bh5g set DfsEnable=1
			log "cac_ctrl: enable $ifname_bh5g dfs"
			;;
		disable)
			iwpriv $ifname_bh5g set DfsEnable=0
			log "cac_ctrl: disable $ifname_bh5g dfs"
			;;
	esac
}

# only used when init meshv4
cap_init_mesh_ver4() {
	local ifname_bh_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local ifname_ap_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname='$ifname_ap_5g'" | awk -F"." '{print $2}')
	local bh_ssid=$(uci -q get wireless.bh_ap.ssid)
	local lanmac=$(ifconfig br-lan | grep HWaddr | awk '{print $5}')
	local meshid

	set_network_id "$bh_ssid"

	meshid=$(uci -q get xiaoqiang.common.NETWORK_ID)

	iwpriv $ifname_ap_5g set miwifi_mesh=0
	iwpriv $ifname_bh_5g set mesh_aplimit=9
	iwpriv $ifname_bh_5g set ApMWDS=1
	iwpriv $ifname_bh_5g set mesh_id="$meshid"
	iwpriv $ifname_bh_5g set miwifi_mesh_apmac="$lanmac"
	iwpriv $ifname_bh_5g set miwifi_backhual=1

	uci -q set wireless.$iface_5g.miwifi_mesh=0
	uci -q set wireless.bh_ap.mesh_aplimit=9
	uci -q set wireless.bh_ap.wds=1
	uci -q set wireless.bh_ap.backhaul=1
	uci -q set wireless.bh_ap.mesh_id="$meshid"
	uci -q set wireless.bh_ap.mesh_apmac="$lanmac"
	uci commit wireless

	__set_netmode 1 cap
}

init_cap_mode() {
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname='$ifname_5g'" | awk -F"." '{print $2}')
	local support_mesh_ver4=$(mesh_cmd support_mesh_version 4)
	local mesh_suites=$(mesh_cmd mesh_suites)
	local initted=$(uci -q get xiaoqiang.common.INITTED)
	local mode="$1"
	local fac_band=$(uci -q get misc.backhauls.backhaul)

	# update bh_band
	mesh_cmd backhaul set band "$fac_band"
	
	/etc/init.d/meshd stop

	if [ "$support_mesh_ver4" == "1" ] && [ -n "$mode" -a "$mode" != "0" ]; then
		local do_cap_bh_init=0

		case "$mode" in
			1)
				# 单只装在第一次添加re时，由miwifi-discovery初始化并生效，mode=1
				do_cap_bh_init=1
				export restart_miwifi_discovery=0
				export restart_network=1
			;;
			2)
				# web初始化，同步创建好回程ap
				do_cap_bh_init=1
				export meshsuite=1
				export restart_miwifi_discovery=1
				export restart_network=0
			;;
		esac

		if [ "$do_cap_bh_init" -eq 1 ]; then
			export support_mesh_ver4=1
			export restart_xq_info_sync_mqtt=1

			# 初始化bh_ap
			cap_init_mesh_ver4
			mimesh_init_done "cap"
			/usr/sbin/topomon_action.sh cap_init
		fi
	fi

	uci set wireless.$iface_5g.miwifi_mesh=0
	uci commit wireless
}

cap_down_vap() {
	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)

	ubus call network.interface.lan remove_device "{\"name\":\"$ifname\"}"
	ifconfig $ifname down
}

cap_clean_vap() {
	local ifname=$1
	local name=$(echo $2 | sed s/[:]//g)

	#networking failed statpoints
	sp_log_info.sh -k mesh.re.conn.fail -m "SYNC_FAILED:1"

	cap_down_vap
	echo "failed" > /tmp/${name}-status
}

mimesh_mtk_cap_bh_check()
{
	local iface_5g_bh=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	[ -z "$iface_5g_bh" ] && iface_5g_bh="wl5"

	iwpriv $iface_5g_bh get mimesh_backhaul | grep -wq "get:1"

	return $?
}

check_cap_init_status_v2() {
	local ifname=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local device_5g=$(uci -q get misc.wireless.if_5G)
	local re_5g_mac=$2
	local is_cable=$5
	local re_mesh_ver=$6
	local re_5g_obssid=$7
	[ -z "$is_cable" ] && is_cable=0

	for i in $(seq 1 60)
	do
		mimesh_mtk_cap_bh_check > /dev/null 2>&1
		if [ $? = 0 ]; then
			mimesh_init_done "cap"
			sleep 2
			init_done=1
			break
		fi
		sleep 2
	done

	if [ $init_done -eq 1 ]; then
		# statpoint to record if meshed
		set_meshed_flag

		for i in $(seq 1 90)
		do
			local assoc_count1=$(mtknetlink_cli $ifname stalist | grep -i -c $3)
			local assoc_count2=$(mtknetlink_cli $ifname stalist | grep -i -c $4)
			local assoc_count3=0

			if [ $(expr $i % 5) -eq 0 ]; then
				assoc_count3=$(ubus call trafficd hw | grep -iwc $re_5g_mac)
			fi

			local total_count=$(expr $assoc_count1 + $assoc_count2 + $assoc_count3)
			if [ $is_cable == "1" -o $total_count -gt 0 ]; then
				/sbin/cap_push_backhaul_whitelist.sh
				(sleep 30; /sbin/cap_push_backhaul_whitelist.sh) &
				/usr/sbin/topomon_action.sh cap_init
				echo "success" > /tmp/$1-status
				iwpriv $ifname set DfsEnable=1
				exit 0
			fi

			#for ax9000 mesh2.0(here re_mesh_ver was 3)
			if [ "$re_mesh_ver" -gt "2" ]; then
				[ -n "$re_5g_obssid" -a "00:00:00:00:00:00" != "$re_5g_obssid" ] && {
					local re_obsta_mac1=$(calcbssid -i 1 -m $re_5g_obssid)
					local re_obsta_mac2=$(calcbssid -i 2 -m $re_5g_obssid)
					local assoc_count4=$(mtknetlink_cli $ifname stalist | grep -i -c $re_obsta_mac1)
					local assoc_count5=$(mtknetlink_cli $ifname stalist | grep -i -c $re_obsta_mac2)
					local assoc_count6=0

					if [ $(expr $i % 5) -eq 0 ]; then
						assoc_count6=$(ubus call trafficd hw | grep -iwc $re_5g_obssid)
					fi

					if [ $is_cable == "1" -o $assoc_count4 -gt 0 -o $assoc_count5 -gt 0 -o $assoc_count6 -gt 0 ]; then
						/sbin/cap_push_backhaul_whitelist.sh
						(sleep 30; /sbin/cap_push_backhaul_whitelist.sh) &
						/usr/sbin/topomon_action.sh cap_init
						echo "success" > /tmp/$1-status
						iwpriv $ifname set DfsEnable=1
						exit 0
					fi
				}
			fi
			sleep 2
		done
	fi

	#networking failed statpoints
	sp_log_info.sh -k mesh.re.conn.fail -m "UNSPEC_FAILED:1"

	echo "failed" > /tmp/$1-status
	iwpriv $ifname set DfsEnable=1
	exit 1
}

do_cap_init_bsd() {
	local name=$(echo $1 | sed s/[:]//g)
	local is_cable=$8
	[ -z "$is_cable" ] && is_cable=0

	local ifname_ap_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname='$ifname_ap_2g'" | awk -F"." '{print $2}')

	local whc_ssid=$(uci -q get wireless.$iface_2g.ssid)
	local whc_pswd=$(uci -q get wireless.$iface_2g.key)
	local whc_mgmt=$(uci -q get wireless.$iface_2g.encryption)

	local ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	local bh_ssid=$(printf "%s" "$6" | base64 -d)
	local bh_pswd=$(printf "%s" "$7" | base64 -d)
	local init_done=0

	local device_5g=$(uci -q get misc.wireless.if_5G)

	local channel=$(uci -q get wireless.$device_5g.channel)
	local bw=$(uci -q get wireless.$device_5g.bw)

	local re_bssid=$1
	local obssid_jsonbuf=
	local obssid=
	local re_mesh_ver=
	[ -f "/var/run/scanrelist" ] && {
		obssid_jsonbuf=$(cat /var/run/scanrelist | grep -i "$re_bssid")
		obssid=$(json_get_value "$obssid_jsonbuf" "obssid")
		re_mesh_ver=$(json_get_value "$obssid_jsonbuf" "mesh_ver")
	}
	[ -z "$re_mesh_ver" ] && re_mesh_ver=2

	echo "syncd" > /tmp/${name}-status

	set_network_id "$bh_ssid"

	cap_down_vap

	export support_mesh_ver4=$(mesh_cmd support_mesh_version 4)

	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
	
	if [ "whc_cap" != "$mode" ] && [ "$mode" != "lanapmode" -o "$cap_mode" != "ap" ]; then
		local bh_maclist_5g=
		local bh_macnum_5g=0

		if [ "$whc_mgmt" == "ccmp" ]; then
			whc_pswd=$(uci -q get wireless.$iface_2g.sae_password)
		fi

		whc_ssid=$(printf "%s" "$whc_ssid" | base64 | xargs)
		whc_pswd=$(printf "%s" "$whc_pswd" | base64 | xargs)

		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
				uci set wireless.$device_5g.channel='auto'
				uci commit wireless
				;;
			*) ;;
		esac

		#ignore CAC on first init
		iwpriv $ifname_5g set DfsEnable=0

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"whc_ssid\":\"${whc_ssid}\",\"whc_pswd\":\"${whc_pswd}\",\"whc_mgmt\":\"${whc_mgmt}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

		mimesh_init "$buff"
	fi

	check_cap_init_status_v2 $name $1 $3 $5 $is_cable $re_mesh_ver $obssid
}

do_cap_init() {
	local name=$(echo $1 | sed s/[:]//g)
	local is_cable=$8
	[ -z "$is_cable" ] && is_cable=0

	local ifname_ap_2g=$(uci -q get misc.wireless.ifname_2G)
	local iface_2g=$(uci show wireless | grep -w "ifname='$ifname_ap_2g'" | awk -F"." '{print $2}')
	local ifname_ap_5g=$(uci -q get misc.wireless.ifname_5G)
	local iface_5g=$(uci show wireless | grep -w "ifname='$ifname_ap_5g'" | awk -F"." '{print $2}')
	local device_5g=$(uci -q get misc.wireless.if_5G)

	local ssid_2g=$(uci -q get wireless.$iface_2g.ssid)
	local pswd_2g=$(uci -q get wireless.$iface_2g.key)
	local mgmt_2g=$(uci -q get wireless.$iface_2g.encryption)
	local ssid_5g=$(uci -q get wireless.$iface_5g.ssid)
	local pswd_5g=$(uci -q get wireless.$iface_5g.key)
	local mgmt_5g=$(uci -q get wireless.$iface_5g.encryption)

	local bh_ifname_5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	local bh_ssid=$(printf "%s" "$6" | base64 -d)
	local bh_pswd=$(printf "%s" "$7" | base64 -d)
	local init_done=0

	local channel=$(uci -q get wireless.$device_5g.channel)
	local bw=$(uci -q get wireless.$device_5g.bw)

	local re_bssid=$1
	local obssid_jsonbuf=
	local obssid=
	local re_mesh_ver=
	[ -f "/var/run/scanrelist" ] && {
		obssid_jsonbuf=$(cat /var/run/scanrelist | grep -i "$re_bssid")
		obssid=$(json_get_value "$obssid_jsonbuf" "obssid")
		re_mesh_ver=$(json_get_value "$obssid_jsonbuf" "mesh_ver")
	}
	[ -z "$re_mesh_ver" ] && re_mesh_ver=2

	echo "syncd" > /tmp/${name}-status

	set_network_id "$bh_ssid"

	cap_down_vap

	export support_mesh_ver4=$(mesh_cmd support_mesh_version 4)

	local mode=$(uci -q get xiaoqiang.common.NETMODE)
	local cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)

	if [ "whc_cap" != "$mode" ] && [ "$mode" != "lanapmode" -o "$cap_mode" != "ap" ]; then
		local bh_maclist_5g=
		local bh_macnum_5g=0

		if [ "$mgmt_2g" == "ccmp" ]; then
			pswd_2g=$(uci -q get wireless.$iface_2g.sae_password)
		fi

		if [ "$mgmt_5g" == "ccmp" ]; then
			pswd_5g=$(uci -q get wireless.$iface_5g.sae_password)
		fi

		ssid_2g=$(printf "%s" "$ssid_2g" | base64 | xargs)
		pswd_2g=$(printf "%s" "$pswd_2g" | base64 | xargs)
		ssid_5g=$(printf "%s" "$ssid_5g" | base64 | xargs)
		pswd_5g=$(printf "%s" "$pswd_5g" | base64 | xargs)

		#ignore CAC on first init
		iwpriv $bh_ifname_5g set DfsEnable=0

		local buff="{\"method\":\"init\",\"params\":{\"whc_role\":\"CAP\",\"bsd\":\"0\",\"ssid_2g\":\"${ssid_2g}\",\"pswd_2g\":\"${pswd_2g}\",\"mgmt_2g\":\"${mgmt_2g}\",\"ssid_5g\":\"${ssid_5g}\",\"pswd_5g\":\"${pswd_5g}\",\"mgmt_5g\":\"${mgmt_5g}\",\"bh_ssid\":\"${bh_ssid}\",\"bh_pswd\":\"${bh_pswd}\",\"bh_mgmt\":\"psk2\",\"bh_macnum_5g\":\"${bh_macnum_5g}\",\"bh_maclist_5g\":\"${bh_maclist_5g}\",\"bh_macnum_2g\":\"0\",\"bh_maclist_2g\":\"\"}}"

		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
				uci set wireless.$device_5g.channel='auto'
				uci commit wireless
				;;
			*) ;;
		esac

		mimesh_init "$buff"
	fi

	check_cap_init_status_v2 $name $1 $3 $5 $is_cable $re_mesh_ver $obssid
}

do_re_dhcp() {
	local bridge="br-lan"
	local ifname=$(uci -q get misc.wireless.apclient_5G)
	local model=$(uci -q get misc.hardware.model)
	[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)

	ubus call network.interface.lan add_device "{\"name\":\"$ifname\"}"

	ifconfig br-lan 0.0.0.0

	#udhcpc on br-lan, for re init time optimization
	udhcpc -q -p /var/run/udhcpc-${bridge}.pid -s /usr/share/udhcpc/mesh_dhcp.script -f -t 0 -i $bridge -x hostname:MiWiFi-${model}

	exit $?
}

re_start_wps() {
	local ifname=$(uci -q get misc.wireless.apclient_5G)
	local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
	local device=$(uci -q get misc.wireless.${ifname}_device)
	local ifname_bh5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)
	local macaddr="$1"
	local channel="$2"

	network_accel_hook "stop"
	eth_down

	iwpriv $ifname_5G set Channel=$channel
	sleep 2

	iwpriv $ifname_bh5g set DfsEnable=0
	ifconfig $ifname up
	iwpriv $ifname set ApCliMWDS=1
	iwpriv $ifname set ApCliEnable=0
	iwpriv $ifname set ApCliWscBssid="$macaddr"
	iwpriv $ifname set WscConfMode=1
	iwpriv $ifname set WscMode=2
	iwpriv $ifname set ApCliEnable=1
	iwpriv $ifname set WscGetConf=1

	for i in $(seq 1 60)
	do
		linkup=$(iwpriv $ifname Connstatus|grep Connected >/dev/null;echo $?)
		if [ $linkup -eq 0 ]; then
			exit 0
		fi

		sleep 2
	done

	eth_up

	iwpriv $ifname set WscConfMode=0
	ifconfig $ifname down
	iwpriv $ifname_bh5g set DfsEnable=1

	network_accel_hook "start"

	exit 1
}

cap_start_wps() {
	local ifname=$(uci -q get misc.wireless.mesh_ifname_5G)
	local status_file=$(echo $1 | sed s/[:]//g)
	local re_bssid=$1
	local obssid_jsonbuf=$(cat /var/run/scanrelist | grep -i "$re_bssid")
	local obssid=$(json_get_value "$obssid_jsonbuf" "obssid")
	local obsta_mac="00:00:00:00:00:00"
	[ -n "$obssid" -a "00:00:00:00:00:00" != "$obssid" ] && obsta_mac=$(calcbssid -i 1 -m $obssid)
	local ssid_rand=$(openssl rand -base64 8 2>/dev/null | md5sum | cut -c1-16)
	local key=$(openssl rand -base64 8 2>/dev/null| md5sum | cut -c1-32)
	local ifname_bh5g=$(uci -q get misc.backhauls.backhaul_5g_ap_iface)

	echo "init" > /tmp/${status_file}-status

	iwpriv $ifname_bh5g set ByPassCac=1
	iwpriv $ifname_bh5g set DfsEnable=0
	ifconfig $ifname up
	sleep 2

	ubus call network.interface.lan add_device "{\"name\":\"$ifname\"}"

	iwpriv $ifname set AuthMode=WPA2PSK
	iwpriv $ifname set EncrypType=AES
	iwpriv $ifname set SSID="wps-$ssid_rand"
	iwpriv $ifname set WPAPSK="$key"
	iwpriv $ifname set SSID="wps-$ssid_rand"
	iwpriv $ifname set ApMWDS=1

	iwpriv $ifname set miwifi_mesh=2
	iwpriv $ifname set miwifi_mesh_mac="$1"

	iwpriv $ifname set ACLClearAll=1
	iwpriv $ifname set AccessPolicy=0
	#iwpriv $ifname set ACLAddEntry="$2"
	#[ "00:00:00:00:00:00" != "$obsta_mac" ] && iwpriv $ifname set ACLAddEntry="$obsta_mac"

	iwpriv $ifname set WscConfMode=4;
	iwpriv $ifname set WscMode=2;
	iwpriv $ifname set WscConfStatus=2;
	iwpriv $ifname set WscGetConf=1;

	for i in $(seq 1 60)
	do
		local wps_status=$(iwpriv $ifname get WscStatus|cut -d ':' -f 2|tr '\n' ' ')
		if [ $wps_status -eq 2 ]; then
			echo "connected" > /tmp/${status_file}-status
			cap_disable_wps_trigger $ifname
			exit 0
		fi
		sleep 2
	done

	#networking failed statpoints
	sp_log_info.sh -k mesh.re.conn.fail -m "CONNECT_FAILED:1"

	iwpriv $ifname set WscConfMode=0
	cap_down_vap
	echo "failed" > /tmp/${status_file}-status

	iwpriv $ifname_bh5g set DfsEnable=1

	exit 1
}

# backup: wireless,network,dhcp
re_connect_backup_cfg() {
	mkdir -p /var/run/mesh_backup
	cp /etc/config/wireless /var/run/mesh_backup/
	cp /etc/config/network /var/run/mesh_backup/
	cp /etc/config/dhcp /var/run/mesh_backup/
}

# restore: wireless,network,dhcp
re_connect_restore_cfg() {
	[ -d "/var/run/mesh_backup" ] || return
	cp /var/run/mesh_backup/* /etc/config/
	rm /var/run/mesh_backup -rf >/dev/null
}

# called while init_sync failed
re_connect_clean() {
	local ifname=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)

	ifconfig $ifname down
	ubus call network.interface.lan remove_device "{\"name\":\"$ifname\"}"

	# restore config
	re_connect_restore_cfg
	wifi update &

	ubus call network restart
	/etc/init.d/dnsmasq restart

	/etc/init.d/meshd start
	/etc/init.d/cab_meshd start

	iwpriv $ifname_5g set DfsEnable=1
	network_accel_hook "start"
}

re_connect() {
	local ssid="$1"
	local passwd="$2"
	local mgmt="$3"
	local uplink_ip="$4"
	local ch_freq="$5"
	local ifname=$(uci -q get misc.backhauls.backhaul_5g_sta_iface)
	local ifname_5g=$(uci -q get misc.wireless.ifname_5G)

	MIMESH_LOGI "re to connect ssid:$ssid passwd:$passwd mgmt:$mgmt ch_freq:$ch_freq"

	network_accel_hook "stop"

	/etc/init.d/meshd stop
	/etc/init.d/cab_meshd stop

	let tmp=$ch_freq-5000
	let channel=$tmp/5

	iwpriv $ifname_5g set DfsEnable=0
	iwpriv $ifname_5g set Channel=$channel

	ifconfig $ifname up

	ubus call network.interface.lan add_device "{\"name\":\"$ifname\"}"

	iwpriv $ifname set ApCliEnable=0
	iwpriv $ifname set ApCliMWDS=1
	iwpriv $ifname set ApCliAuthMode=WPA2PSK
	iwpriv $ifname set ApCliEncrypType=AES
	iwpriv $ifname set ApCliSsid="$ssid"
	iwpriv $ifname set ApCliWPAPSK="$passwd"
	iwpriv $ifname set ApCliSsid="$ssid"
	iwpriv $ifname set ApCliEnable=1

	re_connect_backup_cfg

	# save backhaul sta wifi uci cfg
	uci -q set wireless.bh_sta.ssid="$ssid"
	uci -q set wireless.bh_sta.key="$passwd"
	uci -q set wireless.bh_sta.wds=1
	uci -q set wireless.bh_sta.disabled=0
	uci commit wireless

	__re_dhcp() {
		local bridge=$1
		local ifname=$2
		local model=$(uci -q get misc.hardware.model)
		[ -z "$model" ] && model=$(cat /proc/xiaoqiang/model)

		ubus call network.interface.lan add_device "{\"name\":\"$ifname\"}"
		ifconfig br-lan 0.0.0.0

		#udhcpc on br-lan, for re init time optimization
		udhcpc -q -p /var/run/udhcpc-${bridge}.pid -s /usr/share/udhcpc/mesh_dhcp.script -f -t 0 -i $bridge -x hostname:MiWiFi-${model}

		return $?
	}

	local connect_ok=0
	for i in $(seq 1 60)
	do
		local conn_status=$(iwpriv "$ifname" Connstatus|grep Connected > /dev/null;echo $?)
		if [ "$conn_status" == "0" ]; then
			connect_ok=1
			break
		fi
		sleep 1
	done

	local gw_ok=0
	if [ $connect_ok -eq 1 ]; then
		if __re_dhcp "br-lan" $ifname; then
			for i in $(seq 1 30)
			do
				if ping $uplink_ip -c 1 -w 4 > /dev/null 2>&1; then
					exit 0
				fi
				sleep 1
			done
		fi
	fi

	re_connect_clean
	exit 1
}

channel_modify()
{
	local ifname_5G=$(uci -q get misc.wireless.ifname_5G)
	local channel=$(iwlist $ifname_5G f |grep "Current Channel"|cut -d ':' -f 2)
	local mesh_support_dfs=$(uci -q get misc.mesh.support_dfs)

	if [ "$mesh_support_dfs" != "1" ]; then
		case "$channel" in
			52|56|60|64|100|104|108|112|116|120|124|128|132|136|140)
				iwpriv $ifname_5G set Channel=36
				exit 0
				;;
			*) ;;
		esac
	fi
	exit 1
}

do_init_mesh_hop()
{
	local hop="$1"
	local ifname_5G=$(uci -q get misc.wireless.ifname_5G)

	[ -z "$hop" ] && hop=0
	iwpriv $ifname_5G set mesh_hop=$hop_count
}

set_mesh_status()
{
	local re_mac="$1"
	local status="$2"
	echo "$status" > /tmp/${re_mac}-status
}

case "$1" in
	re_connect)
	shift 1
	re_connect "$@"
	;;
	cac_ctrl)
	shift 1
	cac_ctrl "$@"
	;;
	channel_modify)
	channel_modify
	;;
	re_connect_clean)
	re_connect_clean
	;;
	init_mesh_hop)
	shift 1
	do_init_mesh_hop "$@"
	;;
	re_start)
	re_start_wps "$2" "$3"
	;;
	cap_start)
	cap_start_wps "$2" "$3"
	;;
	cap_close)
	cap_close_wps
	;;
	init_cap)
	shift 1
	init_cap_mode "$@"
	;;
	cap_init)
	run_with_lock do_cap_init "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	cap_init_bsd)
	do_cap_init_bsd "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	re_init)
	run_with_lock do_re_init "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}"
	;;
	re_init_bsd)
	do_re_init_bsd "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
	;;
	re_dhcp)
	do_re_dhcp
	;;
	cap_clean)
	cap_clean_vap "$2" "$3"
	;;
	re_clean)
	re_clean_vap
	;;
	re_init_json)
	do_re_init_json "$2"
	;;
	meshed)
	set_meshed_flag
	;;
	mesh_status)
	set_mesh_status "$2" "$3"
	;;
	*)
	usage
	;;
esac
