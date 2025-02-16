#!/bin/sh


arch_ps_init_service() {
    local dev cpu_port

    # for MT7531AE, cpu_port = 6
    # for AN8855, cpu_port = 5
    cpu_port="6"
    dev=$(switch devs | cut -d ' ' -f 4 | cut -d ',' -f 1 | xargs)
    [ "AN8855" = "$dev" ] && cpu_port="5"

    uci batch <<-EOF
        set port_map.1.cpu_port='$cpu_port'
        set port_map.2.cpu_port='$cpu_port'
        set port_map.3.cpu_port='$cpu_port'
        set port_map.4.cpu_port='$cpu_port'
        set port_map.vlan_type='8021q'
        commit port_map
	EOF
    return
}

arch_ps_setup_wan() {
    local service="$1"
    local wan_port="$2"
    local wan_internet_vid wan_ifname dial_ifname wan6_ifname pass_ifname wan_vid wan_mac

    # reconfig network ifname
    wan_vid=$(port_map config get "$wan_port" vid)
    wan_mac=$(uci -q get network."$service".macaddr)
    wan_ifname=$(port_map config get "$wan_port" ifname)
    wan_internet_vid=$(uci -q get port_service.wantag_attr.vid)
    dial_ifname="$wan_ifname"
    [ "$wan_internet_vid" -gt 0 ] && dial_ifname="${dial_ifname}.${wan_internet_vid}"
    wan6_ifname="$dial_ifname"
    [ "$(uci -q get network."${service/n/n6}".passthrough)" = "1" ] && {
        wan6_ifname="br-lan"
        pass_ifname="$dial_ifname"
    }
    list_lan_ifname=$(port_map iface service lan)

    uci -q batch <<-EOF
        set network."$service".ifname="$dial_ifname"
        set network."${service/n/n6}".ifname="$dial_ifname"
        set network."macv_${service/n/n6}".ifname="$dial_ifname"
        set network."${service/n/n6}".ifname="$wan6_ifname"
        set network."${service/n/n6}".pass_ifname="$pass_ifname"
        set network.lan.ifname="$list_lan_ifname"
        commit network
	EOF

    # reload network
    ip link set dev "$wan_ifname" address "$wan_mac"
    port_map config set "$wan_port" dial_ifname "$dial_ifname"
    echo "$wan_vid" > /sys/kernel/debug/hnat/wan_vid
    [ "$wan_internet_vid" -gt 0 ] && echo "$wan_internet_vid" > /sys/kernel/debug/hnat/wan_internet_vid
    ubus call network reload
    ubus call network.interface."$service" up
}

arch_ps_reset_lan() {
    local service="$1"
    local old_wan_port="$2"
    local wan_vid wan_ifname list_lan_ifname lan_mac

    [ -z "$old_wan_port" ] && return

    wan_vid=$(port_map config get "$old_wan_port" vid)
    wan_ifname=$(port_map iface port "$old_wan_port")
    list_lan_ifname=$(port_map iface service lan)
    append list_lan_ifname "$wan_ifname"
    lan_mac=$(uci -q get network.lan.macaddr)
    dial_ifname=$(port_map config get "$old_wan_port" dial_ifname)

    # reconfig network
    uci -q batch <<-EOF
        delete network."$service".ifname
        delete network."${service/n/n6}".ifname
        delete network."${service/n/n6}".pass_ifname
        delete network."macv_${service/n/n6}".ifname
        set network.lan.ifname="$list_lan_ifname"
        commit network
	EOF

    echo -1 > /sys/kernel/debug/hnat/wan_vid
    echo -1  > /sys/kernel/debug/hnat/wan_internet_vid
    echo -1 > /sys/kernel/debug/hnat/iptv_vid

    # reload network
    port_map config set "$old_wan_port" dial_ifname ""
    pconfig del "${wan_ifname}_6" > /dev/null 2>&1
    ip addr flush dev "$wan_ifname"
    ip link set dev "$wan_ifname" address "$lan_mac"
    ubus call network.interface."$service" down
    ubus call network reload
    util_portmap_update
    return
}
