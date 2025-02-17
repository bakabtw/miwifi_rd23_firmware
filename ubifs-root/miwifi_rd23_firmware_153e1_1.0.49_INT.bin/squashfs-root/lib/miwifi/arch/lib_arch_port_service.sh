#!/bin/sh

arch_ps_setup_wan() {
    local service="$1"
    local wan_port="$2"
    local wan_internet_vid="$4"
    local wan_ifname dial_ifname wan_vid wan_phy
    local wan6_ifname pass_ifname
    local portmap="00000100" # bit5

    # reconfig network ifname
    wan_vid=$(port_map config get "$wan_port" vid)
    wan_phy=$((wan_port - 1))
    wan_ifname="eth1.$wan_vid"

    dial_ifname="$wan_ifname"
    [ -n "$wan_internet_vid" ] && dial_ifname="${dial_ifname}.${wan_internet_vid}"

    wan6_ifname="$dial_ifname"
    [ "$(uci -q get network."${service/n/n6}".passthrough)" = "1" ] && {
        wan6_ifname="br-lan"
        pass_ifname="$dial_ifname"
    }

    uci -q batch <<-EOF
        set network."${dial_ifname//./_}"=interface
        set network."${dial_ifname//./_}".ifname="$dial_ifname"
        set network."${wan_ifname//./_}"=interface
        set network."${wan_ifname//./_}".ifname="$wan_ifname"
        set network."$service".ifname="$dial_ifname"
        set network."${service/n/n6}".ifname="$dial_ifname"
        set network."macv_${service/n/n6}".ifname="$dial_ifname"
        set network."${service/n/n6}".ifname="$wan6_ifname"
        set network."${service/n/n6}".pass_ifname="$pass_ifname"
        set network."vlan$wan_vid".ports="$wan_phy 5t"
        commit network
	EOF

    # reload network
    util_portmap_set "$wan_phy" "$wan_ifname"
    util_iface_status_set "eth0.$wan_vid" "down" # necessary! for ipv6 passthrough mode
    port_map config set "$wan_port" ifname "$wan_ifname"
    port_map config set "$wan_port" dial_ifname "$dial_ifname"

    echo "$wan_vid" > /sys/kernel/debug/hnat/wan_vid
    [ -n "$wan_internet_vid" ] && echo "$wan_internet_vid" > /sys/kernel/debug/hnat/wan_internet_vid

    portmap=$(echo "$portmap" | sed "s/./1/$wan_port")
    switch vlan set 0 "$wan_vid" "$portmap" 0 0 00000200
    ubus call network reload
    ubus call network.interface."$service" up
}

arch_ps_reset_lan() {
    local service="$1"
    local old_wan_port="$2"
    local wan_phy lan_ifname wan_ifname dial_ifname
    local portmap="00000010" # bit6

    [ -z "$old_wan_port" ] && return
    wan_vid=$(port_map config get "$old_wan_port" vid)
    wan_phy=$((old_wan_port - 1))
    lan_ifname="eth0.$wan_vid"
    wan_ifname="eth1.$wan_vid"
    dial_ifname=$(port_map config get "$old_wan_port" dial_ifname)

    # reconfig network
    uci -q batch <<-EOF
        delete network."${dial_ifname//./_}"
        delete network."${wan_ifname//./_}"
        delete network."$service".ifname
        delete network."${service/n/n6}".ifname
        delete network."${service/n/n6}".pass_ifname
        delete network."macv_${service/n/n6}".ifname
        set network."vlan$wan_vid".ports="$wan_phy 6t"
        commit network
	EOF

    # reload network
    util_portmap_set "$wan_phy" "$lan_ifname"
    port_map config set "$old_wan_port" ifname "$lan_ifname"
    port_map config set "$old_wan_port" dial_ifname ""
    pconfig del "eth1.${wan_vid}_6" > /dev/null 2>&1

    echo -1 > /sys/kernel/debug/hnat/wan_vid
    echo -1  > /sys/kernel/debug/hnat/wan_internet_vid
    echo -1 > /sys/kernel/debug/hnat/iptv_vid

    portmap=$(echo "$portmap" | sed "s/./1/$old_wan_port")
    switch vlan set 0 "$wan_vid" "$portmap" 0 0 00000020
    ubus call network.interface."$service" down
    ubus call network reload
    util_portmap_update
    return
}