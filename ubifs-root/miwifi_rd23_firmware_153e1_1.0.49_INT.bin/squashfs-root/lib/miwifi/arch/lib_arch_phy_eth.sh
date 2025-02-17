#!/bin/sh


_set_port_giga() {
	local ori_value
	local set_value

	# read original value of register 9 1000BASE-T Control Register
	ori_value=$(switch phy cl22 r "$1" 9 | awk -F'=' '{print $3}')

	if [ "$2" = 'on' ]; then
		# bit 8 is 1000M HDX, bit 9 is 1000M FDX, both set to 1
		set_value=$((ori_value | 0x300))
	else
		# bit 8 is 1000M HDX, bit 9 is 1000M FDX, both set to 0
		set_value=$((ori_value & ~0x300))
	fi

	switch phy cl22 w "$1" 9 $set_value
}

_set_port_mega() {
	local ori_value
	local set_value

	ori_value=$(switch phy cl22 r "$1" 4 | awk -F'=' '{print $3}')

	# bit 7 is 100M HDX, bit 8 is 100M FDX
	# bit 5 is 10M HDX, bit 6 is 10M FDX
	case $2 in
	disable)
		# disable 100M, disable 10M
		set_value=$((ori_value & ~0x180))
		set_value=$((set_value & ~0x60))
		;;
	auto)
		# enable 100M, enable 10M
		set_value=$((ori_value | 0x180))
		set_value=$((set_value | 0x60))
		;;
	10)
		# disable 100M, enable 10M
		set_value=$((ori_value & ~0x180))
		set_value=$((set_value | 0x60))
		;;
	100)
		# enable 100M, disable 10M
		set_value=$((ori_value | 0x180))
		set_value=$((set_value & ~0x60))
		;;
	*)
		echo "unsupport speed!"
		return 1
		;;
	esac

	switch phy cl22 w "$1" 4 $set_value
}

arch_phy_eth_port_restart() {
    local port="$1"
    local ori_value set_value
    port=$((port - 1))

    ori_value=$(switch phy cl22 r $port 0 | awk -F'=' '{print $3}')
    set_value=$((ori_value | 0x200))
    switch phy cl22 w $port 0 $set_value
}

arch_phy_eth_port_mode_set() {
    local port="$1"
    local speed="$2"
    local ori_value set_value
    port=$((port - 1))

    ori_value=$(switch phy cl22 r $port 0 | awk -F'=' '{print $3}')
    set_value=$((ori_value & ~ 0x1000))
    set_value=$((ori_value & ~ 0x2040))

    case "$speed" in
    0)
        _set_port_mega "$port" auto
        _set_port_giga "$port" on
    ;;
    10)
        _set_port_mega "$port" 10
        _set_port_giga "$port" off
    ;;
    100)
        _set_port_mega "$port" 100
        _set_port_giga "$port" off
    ;;
    1000)
        _set_port_mega "$port" disable
        _set_port_giga "$port" on
    ;;
    *)
        return 1
        ;;
    esac

    arch_phy_eth_port_restart "$1"
    return 0
}

arch_phy_eth_port_mode_get() {
    local port="$1"
    local reg4 reg9
    port=$((port - 1))

    reg4=$(switch phy cl22 r $port 4 | awk -F'=' '{print $3}')
    reg9=$(switch phy cl22 r $port 9 | awk -F'=' '{print $3}')


    if [ $((reg9 & 0x200)) != 0 ]; then
        [ $((reg4 & 0x1e0)) != 0 ] && echo 0 || echo 1000
    else
        [ $((reg4 & 0x60)) != 0 ] && echo 10 || echo 100
    fi
    return 0
}

arch_phy_eth_port_link_speed() {
    local port="$1"
    local speed="0"
    local reg_addr reg_value

    port=$((port - 1))
    reg_addr=$((0x3008 + 0x100 * port))
    reg_addr=$(printf "0x%x" $reg_addr)
    reg_value=$(switch reg r "$reg_addr" | awk -F'=' '{print "0x"$3}')

    [ "$((reg_value & 0x1))" = "1" ] && speed="10"
    reg_value=$(((reg_value & 0xc) >> 2))
    speed=$((speed ** (reg_value + 1)))

    echo "$speed"
}

arch_phy_eth_port_power_on() {
    local port="$1"
    local ori_value set_value
    port=$((port - 1))

    ori_value=$(switch phy cl22 r $port 0 | awk -F'=' '{print $3}')
    set_value=$((ori_value & ~0x800))
    switch phy cl22 w $port 0 $set_value
}

arch_phy_eth_port_power_off() {
    local port="$1"
    local ori_value set_value
    port=$((port - 1))

    ori_value=$(switch phy cl22 r $port 0 | awk -F'=' '{print $3}')
    set_value=$((ori_value | 0x800))
    switch phy cl22 w $port 0 $set_value
}

arch_phy_eth_port_link_status() {
    local port="$1"
    local status="down"
    local reg_addr reg_value

    port=$((port - 1))
    reg_addr=$((0x3008 + 0x100 * port))
    reg_addr=$(printf "0x%x" $reg_addr)
    reg_value=$(switch reg r "$reg_addr" | awk -F'=' '{print "0x"$3}')
    [ "$((reg_value & 0x1))" = "1" ] && status="up"

    echo "$status"
}
