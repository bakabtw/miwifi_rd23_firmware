#!/bin/ash

ver=$(uci -q get ipv6.globals.ver)
[ -z "$ver" -a -e "/usr/sbin/ipv6.sh" ] && {
    /usr/sbin/ipv6.sh cfg_to_v2
}

