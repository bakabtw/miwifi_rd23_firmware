#!/bin/sh

### activate wifi black/white maclist after sync from gateway router / whc_CAP

# this script warm process maclist on wifi ap iface
. /lib/functions.sh

LOGI()
{
    logger -s -p 1 -t "xqwhc_maclist" "$1"
}

__wifi_stalist()
{
    echo -n "`mtknetlink_cli $1 stalist 2>&1 | grep -Eo "..:..:..:..:..:.." | xargs`"
}

__maclist_flush()
{
    local ifa="$1"
    iwpriv $ifa set ACLClearAll=1
}

__maclist_disable()
{
    local ifa="$1"
    iwpriv $ifa set AccessPolicy=0
}

__maclist_active_deny()
{
    local ifa="$1"

    iwpriv $ifa set AccessPolicy=2

    # add all maclist and process mac DO in assoclist
    for mac in $maclist; do
        iwpriv $ifa set ACLAddEntry="$mac"

        # if mac in assoc list, kick it
        local assoclist="$(__wifi_stalist $ifa)"
        list_contains assoclist $mac && {
            LOGI " $mac in deny maclist, kick it from $ifa "
            mtknetlink_cli $ifa disassoc $mac
        }
    done
}

__maclist_active_allow()
{
    local ifa="$1"

    iwpriv $ifa set AccessPolicy=1

    # add all maclist and process mac NOT in assoclist
    for mac in $maclist; do
        iwpriv $ifa set ACLAddEntry=$mac
    done

    # if mac NOT in allow maclist, kick it
    local assoclist="$(__wifi_stalist $ifa)"
    for mac in $assoclist; do
        list_contains maclist $mac || {
            LOGI " $mac NOT in allow maclist, kick it from $ifa "
            mtknetlink_cli $ifa disassoc $mac
        }
    done
}

# wifi ap iface
iflist="wl0 wl1"
#nlal_get_wifi_apiface_bynet $NETWORK_PRIV iflist
LOGI " iflist=$iflist"

# fileter type deny / allow
macfilter="`uci -q get wireless.@wifi-iface[0].macfilter`"
maclist="`uci -q get wireless.@wifi-iface[0].maclist | sed 'y/abcdef/ABCDEF/' `"
LOGI " wifi macfilter [$macfilter]:[$maclist]"

for ifa in $iflist; do
    __maclist_flush $ifa
    __maclist_disable $ifa

    if [ "$macfilter" = "deny" ]; then
        __maclist_active_deny $ifa
    elif [ "$macfilter" = "allow" ]; then
        __maclist_active_allow $ifa
    fi
done
