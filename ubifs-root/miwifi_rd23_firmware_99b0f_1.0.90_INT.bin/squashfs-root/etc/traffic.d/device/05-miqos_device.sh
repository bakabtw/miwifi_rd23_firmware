#!/bin/sh

qosflag=$(uci -q get miqos.settings.enabled)
[ "$qosflag" != "1" ] && return 0
force_disabled=$(uci -q get miqos.settings.force_disabled)
[ "$force_disabled" = "1" ] && return 0

ifname_prefix=${IFNAME:0:2}
if [ "x$ifname_prefix" == "xwl" ]; then
    #EVENT 0-offline, 1-online
    if [ "x$EVENT" == "x1" ] || [ "x$EVENT" == "x3" ]; then
        /usr/sbin/miqosc device_in $MAC
    elif [ "x$EVENT" == "x0" ]; then
        /usr/sbin/miqosc device_out $MAC
    fi
    return 0
fi

if [ "x$ifname_prefix" == "x" ]; then
    #EVENT 0-offline, 1-online
    if [ "x$EVENT" == "x1" ] || [ "x$EVENT" == "x3" ]; then
        /usr/sbin/miqosc device_in 00
    elif [ "x$EVENT" == "x0" ]; then
        /usr/sbin/miqosc device_out 00
    fi
    return 0
fi
