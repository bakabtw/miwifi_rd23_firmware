#!/bin/sh

_set_scan() {
    local _ifname="$1"
    local _ssid="$2"
    [ -z "$_ifname" ] && exit 1

    if [ -z "$_ssid" ]; then
        iwpriv "$_ifname" set PartialScan=1
    else
        iwpriv "$_ifname" set SiteSurvey="$_ssid"
    fi
    sleep 1
}

_get_connect() {
    local _ifname="$1"
    [ -z "$_ifname" ] && exit 1
    local _connection=$(iwpriv "$_ifname" Connstatus)
    echo "$_connection"
}

_set_inactive() {
    local _ifname="$1"
    [ -z "$_ifname" ] && exit 1
    iwpriv "$_ifname" set ApCliEnable=0
    iwpriv "$_ifname" set ApCliAutoConnect=0
    ifconfig "$_ifname" down
}

_update_apcli() {
    local _val="$1"
    [ -z "$_val" ] && exit 1
    iwpriv apcli0 set ApCliAutoConnect="$_val"
    iwpriv apclix0 set ApCliAutoConnect="$_val"
}

_get_scan_result() {
    local _ifname="$1"
    [ -z "$_ifname" ] && exit 1
    local result=$(iwpriv "$_ifname" ScanResult)
    echo "$result"
}

_set_ch_quality() {
    sleep 2
    iwpriv wl1 set PartialScan=1
}

_set_channel() {
    local _ifname="$1"
    local _channel="$2"
    [ -z "$_ifname" ] || [ -z "$_channel" ] && exit 1
    sleep 4
    iwpriv "$_ifname" set Channel="$_channel"
}

_get_real_signal() {
    echo 0
}

_set_connect() {
    local _ifname="$1"
    local _cmd_enctype="$2"
    local _cmd_encryption="$3"
    local _base_passwd="$4"
    local _base_ssid="$5"
    local _bh_ifname="${11}"

    [ -z "$_ifname" ] ||
        [ -z "$_cmd_enctype" ] ||
        [ -z "$_cmd_encryption" ] ||
        [ -z "$_base_ssid" ] && exit 1

    if [ "$_cmd_encryption" != "NONE" -a  -z "$_base_passwd" ]; then
        echo "$_cmd_encryption need passwd!" > /dev/console
        exit 1
    fi

    /etc/init.d/meshd stop &

    ifconfig "$_ifname" up
    sleep 2

    [ -n "$_bh_ifname" ] && iwpriv "$_bh_ifname" set miwifi_backhual=0

    iwpriv "$_ifname" set ApCliEnable=0
    case "$_cmd_enctype" in
    *AES*)
        iwpriv "$_ifname" set ApCliAuthMode="$_cmd_encryption"
        iwpriv "$_ifname" set ApCliEncrypType=AES
        iwpriv "$_ifname" set bs64_ApCliSsid="$_base_ssid"
        iwpriv "$_ifname" set bs64_ApCliWPAPSK="$_base_passwd"
        ;;
    *TKIP*)
        iwpriv "$_ifname" set ApCliAuthMode="$_cmd_encryption"
        iwpriv "$_ifname" set ApCliEncrypType=TKIP
        iwpriv "$_ifname" set bs64_ApCliSsid="$_base_ssid"
        iwpriv "$_ifname" set bs64_ApCliWPAPSK="$_base_passwd"
        ;;
    *WEP*)
        iwpriv "$_ifname" set ApCliAuthMode=OPEN
        iwpriv "$_ifname" set ApCliEncrypType=WEP
        iwpriv "$_ifname" set ApCliDefaultKeyID=1
        iwpriv "$_ifname" set bs64_ApCliKey1="$_base_passwd"
        iwpriv "$_ifname" set bs64_ApCliSsid="$_base_ssid"
        ;;
    *NONE*)
        iwpriv "$_ifname" set ApCliAuthMode=OPEN
        iwpriv "$_ifname" set ApCliEncrypType=NONE
        iwpriv "$_ifname" set bs64_ApCliSsid="$_base_ssid"
        ;;
    esac
    iwpriv "$_ifname" set ApCliEnable=1

    for i in $(seq 1 3)
    do
        local _scan_state=`iwpriv $_ifname get mimeshScan|cut -d ":" -f 2`
        if [ "$_scan_state" == "1" ]; then
            echo "[_set_connect] in mimeshScan.." > /dev/console
            sleep 3
        else
            break;
        fi
    done
    iwpriv "$_ifname" set ApCliAutoConnect=3
    iwpriv "$_ifname" set ByPassCac=1

    local _if_apcli_5G=$(uci -q get misc.wireless.apclient_5G)
    [ "$_ifname" == "$_if_apcli_5G" ] && {
        iwpriv "$_ifname" set DfsEnable=0
    }
}

_get_work_ch() {
    local _ifname="$1"
    [ -z "$_ifname" ] && exit 1
    local res=$(iwinfo "$_ifname" info | awk -F '[ :]+' '/Channel/{print $5}')
    echo "$res"
}

_app_acl_mode() {
    local _ifname="$1"
    local _mode="$2"
    [ -z "$_ifname" ] || [ -z "$_mode" ] && exit 1
    if [ "$_mode" = "3" ] ; then
        iwpriv "$_ifname" set ACLClearAll=1
    else
        iwpriv "$_ifname" set AccessPolicy="$_mode"
    fi
}

_add_acl_mac() {
    local _ifname="$1"
    local _mac="$2"
    [ -z "$_ifname" ] || [ -z "$_mac" ] && exit 1
    iwpriv "$_ifname" set ACLAddEntry="$_mac"
}

_kick_wl_mac() {
    local _ifname="$1"
    local _mac="$2"
    [ -z "$_ifname" ] || [ -z "$_mac" ] && exit 1
    iwpriv "$_ifname" set DisConnectSta="$_mac"
}

_skip_scan_channel() {
    local _ifname5G=$(uci -q get misc.wireless.ifname_5G)
    local _scan_skip_list=$(uci -q get misc.wireless.scan_skip_list)
    local _mode="$1"
    [ -z "$_ifname5G" ] || [ -z "$_mode" ] || [ -z "$_scan_skip_list" ] && exit 1

    if [ "$_mode" = "0" ] ; then
        iwpriv "$_ifname5G" set ScanSkipList=0
    else
        iwpriv "$_ifname5G" set ScanSkipList="$_scan_skip_list"
    fi
}

case "$1" in
set_scan)
    _set_scan "$2" "$3"
    ;;
get_connect)
    _get_connect "$2"
    ;;
set_inactive)
    _set_inactive "$2"
    ;;
update_apcli)
    _update_apcli "$2"
    ;;
get_scan_result)
    _get_scan_result "$2"
    ;;
set_ch_quality)
    _set_ch_quality
    ;;
set_channel)
    _set_channel "$2" "$3"
    ;;
get_signal)
    _get_real_signal "$2"
    ;;
set_connect)
    shift
    _set_connect "$@"
    ;;
get_work_ch)
    _get_work_ch "$2"
    ;;
app_acl_mode)
    _app_acl_mode "$2" "$3"
    ;;
add_acl_mac)
    _add_acl_mac "$2" "$3"
    ;;
kick_wl_mac)
    _kick_wl_mac "$2" "$3"
    ;;
skip_scan_channel)
    _skip_scan_channel "$2"
    ;;
esac
