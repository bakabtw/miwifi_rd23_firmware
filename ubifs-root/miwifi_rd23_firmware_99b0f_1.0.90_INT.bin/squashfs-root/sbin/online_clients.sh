#!/bin/sh

wifi_onlines()
{
    local count_2g=0
    local count_5g=0
    local count_5gh=0
    local count_guest_2g=0
    local count_guest_5g=0
    local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
    local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
    local ifname_5gh=$(uci -q get misc.wireless.ifname_5GH)
    local ifname_guest_2g=$(uci -q get misc.wireless.ifname_guest_2G)
    local ifname_guest_5g=$(uci -q get misc.wireless.ifname_guest_5G)

    count_2g=$(iwinfo $ifname_2g assoc 2>>/dev/null | grep stacount | awk '{print $2}')
    count_5g=$(iwinfo $ifname_5g assoc 2>>/dev/null | grep stacount | awk '{print $2}')
    count_5gh=$(iwinfo $ifname_5gh assoc 2>>/dev/null | grep stacount | awk '{print $2}')
    count_guest_5g=$(iwinfo $ifname_guest_5g assoc 2>>/dev/null | grep stacount | awk '{print $2}')

    local guest_2G_disabled=$(uci -q get wireless.guest_2G.disabled)
    if [ "${guest_2G_disabled}" = "0" ]
    then
        count_guest_2g=$(iwinfo $ifname_guest_2g assoc 2>>/dev/null | grep stacount | awk '{print $2}')
    fi

    [ -z "$count_2g" ] && count_2g=0
    [ -z "$count_5g" ] && count_5g=0
    [ -z "$count_5gh" ] && count_5gh=0
    [ -z "$count_guest_2g" ] && count_guest_2g=0
    [ -z "$count_guest_5g" ] && count_guest_5g=0

    echo $((count_2g + count_5g + count_5gh + count_guest_2g + count_guest_5g))
}

# TODO: 有线下挂设备存在多种特殊情况，目前未包含，具体方案待定
# 可以通过brctl showmacs获取设备总数，需要过滤掉无线设备、re子节点（有线组网）
# 但无法处理re和sta同时通过交换机接入cap/re的情况
eth_onlines()
{
    local count=$(/sbin/online_clients_wired.lua 2>>/dev/null)
    [ -z "$count" ] && count=0
    echo "$count"
}

all_onlines()
{
    local wifi_stations=$(wifi_onlines)
    local eth_stations=$(eth_onlines)
    local onlines=$((wifi_stations + eth_stations))

    echo $onlines
}

case $1 in
    all_onlines)
        all_onlines
        return 0
        ;;
    wifi_onlines)
        wifi_onlines
        return 0
        ;;
    *) # default return all_onlines
        all_onlines
        return 0
        ;;
esac
