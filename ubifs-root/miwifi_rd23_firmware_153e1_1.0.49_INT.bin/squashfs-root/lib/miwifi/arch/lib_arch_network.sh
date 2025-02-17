#!/bin/sh

arch_network_router_mode_init() { return; }
arch_network_re_mode_init()     { return; }
arch_network_ap_mode_init()     { return; }
arch_network_re_open()          { return; }


arch_network_extra_init() {
    local lan_mac wan_mac

    if [ -z "$(uci -q get network.eth0.macaddr)" ] || [ -z "$(uci -q get network.eth1.macaddr)" ]; then
        lan_mac=$(getmac lan)
        wan_mac=$(getmac wan)
        uci -q batch <<-EOF
            set network.eth0.macaddr="$lan_mac"
            set network.eth1.macaddr="$wan_mac"
            commit network
		EOF
    fi

    [ -f "/tmp/boot_check_done" ] && [ "boot_done" = "$(cat /tmp/boot_check_done)" ] && return

    switch reg w 6110 40000000
    switch reg w 6100 120044f

    switch reg w 5110 40000000
    switch reg w 5100 120044f

    regs w 0x10060110 0x40002000
    regs w 0x10060100 0x12B484F

    regs w 0x10070110 0x40002000
    regs w 0x10070100 0x12B484F

    regs w 0x10060114 0x00000018
    regs w 0x10060120 0x112a1908

    regs w 0x10070114 0x00000018
    regs w 0x10070120 0x112a1908

    switch phy cl45 w 0 0x1e 0x1 0x01b7
    switch phy cl45 w 0 0x1e 0x7 0x03ba
    switch phy cl45 w 0 0x1e 0x4 0x200
    switch phy cl45 w 0 0x1e 0xa 0x0

    switch phy cl45 w 1 0x1e 0x1 0x01b7
    switch phy cl45 w 1 0x1e 0x7 0x03ba
    switch phy cl45 w 1 0x1e 0x4 0x200
    switch phy cl45 w 1 0x1e 0xa 0x0

    switch phy cl45 w 2 0x1e 0x1 0x01b7
    switch phy cl45 w 2 0x1e 0x7 0x03ba
    switch phy cl45 w 2 0x1e 0x4 0x200
    switch phy cl45 w 2 0x1e 0xa 0x0

    switch phy cl45 w 3 0x1e 0x1 0x01b7
    switch phy cl45 w 3 0x1e 0x7 0x03ba
    switch phy cl45 w 3 0x1e 0x4 0x200
    switch phy cl45 w 3 0x1e 0xa 0x0

	echo 1 > /sys/kernel/debug/hnat/qos_toggle

    return
}