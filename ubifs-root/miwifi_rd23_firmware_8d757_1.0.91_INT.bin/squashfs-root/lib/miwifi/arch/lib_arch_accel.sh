#!/bin/sh

readonly qos_mask=1
readonly vpn_mask=2

readonly nat_mask=1
readonly passthrough_mask=2

_config_hnat() {
    local enable="$1"
    local index

    echo "$enable" >/sys/kernel/debug/hnat/hook_toggle

    # config hnat queue
    for index in $(seq 0 63); do
      echo 1 1 0 0 2500000 4 4 > /sys/kernel/debug/hnat/qdma_txq"$index"
    done
    return
}

_save_flag() {
    local key="$1"
    local value="$2"
    uci set misc.quickpass."$key"="$value"
    uci commit misc
    return
}

_get_flag() {
    local key="$1"
    local value
    value=$(uci get misc.quickpass."$key")
    [ -z "$value" ] && value="0"
    echo "$value"
    return
}

_clear_flag() {
    uci set misc.quickpass.hook_toggle="0"
    uci set misc.quickpass.ipv6_toggle="0"
    uci commit misc
    return
}

_disable_hook_toggle() {
    local hook_toggle

    hook_toggle=$(_get_flag hook_toggle)
    _config_hnat 0

    case "$1" in
    "qos" | "QOS")
        hook_toggle=$((hook_toggle|qos_mask))
        ;;
    "vpn" | "VPN")
        hook_toggle=$((hook_toggle|vpn_mask))
        ;;
    *)
        echo "check hnat setting unsupport type: $1" >/dev/console
        ;;
    esac

    _save_flag "hook_toggle" "$hook_toggle"
}

_enable_hook_toggle() {
    local hook_toggle

    hook_toggle=$(_get_flag hook_toggle)

    case "$1" in
    "qos" | "QOS")
        hook_toggle=$((hook_toggle&(~qos_mask)))
        ;;
    "vpn" | "VPN")
        hook_toggle=$((hook_toggle&(~vpn_mask)))
        ;;
    *)
        echo "check hnat setting unsupport type: $1" >/dev/console
        ;;
    esac

    _save_flag "hook_toggle" "$hook_toggle"
    [ "$hook_toggle" = "0" ] && _config_hnat 1
}

_disable_ipv6_toggle() {
    local ipv6_toggle

    ipv6_toggle=$(_get_flag ipv6_toggle)
    echo 0 > /sys/kernel/debug/hnat/ipv6_toggle

    case "$1" in
    "nat")
        ipv6_toggle=$((ipv6_toggle|nat_mask))
        ;;
    "passthrough")
        ipv6_toggle=$((ipv6_toggle|passthrough_mask))
        ;;
    *)
        echo "check hnat setting unsupport type: $1" >/dev/console
        ;;
    esac

    _save_flag "ipv6_toggle" "$ipv6_toggle"
}

_enable_ipv6_toggle() {
    local ipv6_toggle

    ipv6_toggle=$(_get_flag ipv6_toggle)

    case "$1" in
    "nat")
        ipv6_toggle=$((ipv6_toggle&(~nat_mask)))
        ;;
    "passthrough")
        ipv6_toggle=$((ipv6_toggle&(~passthrough_mask)))
        ;;
    *)
        echo "check hnat setting unsupport type: $1" >/dev/console
        ;;
    esac

    _save_flag "ipv6_toggle" "$ipv6_toggle"
    [ "$ipv6_toggle" = "0" ] && echo 1 >/sys/kernel/debug/hnat/ipv6_toggle
}

arch_accel_control() {
    local action="$1"
    local hook_toggle

    hook_toggle=$(_get_flag hook_toggle)

    case "$action" in
    "stop")
        _config_hnat 0
        _save_flag "hook_toggle" $((hook_toggle&(~vpn_mask)))
        ;;
    "start")
        [ "$hook_toggle" = "0" ] && _config_hnat 1
        ;;
    "restart")
        _config_hnat 0
        hook_toggle=$((hook_toggle&(~vpn_mask)))
        _save_flag "hook_toggle" "$hook_toggle"
        [ "$hook_toggle" = "0" ] && _config_hnat 1
        ;;
    "flush")
        echo 3 -1 > /sys/kernel/debug/hnat/hnat_entry
        ;;
    esac
}

arch_accel_event_ipv6_nat_start() {
    _disable_ipv6_toggle nat
}

arch_accel_event_ipv6_nat_stop() {
   _enable_ipv6_toggle nat
}

arch_accel_event_ipv6_passthrough_load() {
    pconfig set_fast_fdb 1
}

arch_accel_event_ipv6_passthrough_start() {
    [ -n "$(pgrep mipctld)" ] && {
        # mipctl is running, must open ipv6 br-netfilter
        sysctl -w net.bridge.bridge-nf-call-ip6tables=1
    }
    _disable_ipv6_toggle passthrough
}

arch_accel_event_ipv6_passthrough_stop() {
    sysctl -w net.bridge.bridge-nf-call-ip6tables=0
    _enable_ipv6_toggle passthrough
}

arch_accel_event_vpn_start() {
    _disable_hook_toggle vpn
}

arch_accel_event_vpn_stop() {
    _enable_hook_toggle vpn
}

arch_accel_event_mipctl_start() {
    [ "passthrough" = "$(uci -q get ipv6.wan6.mode)" ] && {
        # in ipv6 passthrough mode, must open ipv6 br-netfilter
        sysctl -w net.bridge.bridge-nf-call-ip6tables=1
    }
}

arch_accel_event_mipctl_stop() {
    sysctl -w net.bridge.bridge-nf-call-ip6tables=0
}

arch_accel_event_qos_start() {
    _disable_hook_toggle qos
}

arch_accel_event_qos_stop() {
    _enable_hook_toggle qos
}

arch_accel_event_lanap_open() {
    _clear_flag
    _config_hnat 1
    echo 1 >/sys/kernel/debug/hnat/ipv6_toggle
}

arch_accel_event_lanap_close() {
    [ "$(uci -q get miqos.settings.enabled)" = "1" ] && _disable_hook_toggle qos
}

arch_accel_event_wifiap_open() {
    _clear_flag
    _config_hnat 1
    echo 1 >/sys/kernel/debug/hnat/ipv6_toggle
}

arch_accel_event_wifiap_close() {
    [ "$(uci -q get miqos.settings.enabled)" = "1" ] && _disable_hook_toggle qos
}

arch_accel_event_whc_re_setup() {
    _clear_flag
    _config_hnat 1
    echo 1 >/sys/kernel/debug/hnat/ipv6_toggle
}

arch_accel_event_whc_re_open() {
    _clear_flag
    _config_hnat 1
    echo 1 >/sys/kernel/debug/hnat/ipv6_toggle
}

arch_accel_event_whc_re_close() {
    return
}
