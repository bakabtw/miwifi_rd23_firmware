#!/bin/sh

arch_network_router_mode_init() { return; }
arch_network_re_mode_init() { return; }
arch_network_ap_mode_init() { return; }
arch_network_re_open() { return; }

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


    # MT7531AE switch specific settings
    if swconfig list | grep MT7531AE; then
        # spread HSGMII spectrum
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

        # fix Ethernet eye diagram
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
    else
        # for AN8855
        # 100M Taiching/Cenker shape adjust
        for i in 0 1 2 3 4; do
            switch an8855 phy cl45 w $i 0x1e 0x0 0x010A
            switch an8855 phy cl45 w $i 0x1e 0x1 0x01BC
            switch an8855 phy cl45 w $i 0x1e 0x2 0x01C3
            switch an8855 phy cl45 w $i 0x1e 0x3 0x0183
            switch an8855 phy cl45 w $i 0x1e 0x4 0x0200
            switch an8855 phy cl45 w $i 0x1e 0x5 0x0206
            switch an8855 phy cl45 w $i 0x1e 0x6 0x0380
            switch an8855 phy cl45 w $i 0x1e 0x7 0x03BA
            switch an8855 phy cl45 w $i 0x1e 0x8 0x03C6
            switch an8855 phy cl45 w $i 0x1e 0x9 0x0312
            switch an8855 phy cl45 w $i 0x1e 0xa 0x0203
            switch an8855 phy cl45 w $i 0x1e 0xb 0x0002
            switch an8855 phy cl45 w $i 0x1e 0x23 0x0882
            switch an8855 phy cl45 w $i 0x1e 0x24 0x0882
            switch an8855 phy cl45 w $i 0x1e 0x25 0x0882
            switch an8855 phy cl45 w $i 0x1e 0x26 0x0882
            switch an8855 phy cl45 w $i 0x1f 0x269 0x1414
            usleep 50000
        done

        # adjust flow control watermark
        switch an8855 reg w 0x10207e04 0xa08600e5
        switch an8855 reg w 0x10207e08 0x816727
    fi

    echo 1 >/sys/kernel/debug/hnat/qos_toggle

    return
}