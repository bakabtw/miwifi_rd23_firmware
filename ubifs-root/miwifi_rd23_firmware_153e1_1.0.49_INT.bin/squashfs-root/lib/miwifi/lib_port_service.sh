#!/bin/sh

SERVICE=""             # /usr/sbin/port_service.sh <cmd> <service>, save "service" to $SERVICE
LIST_SERVICES=""       # the service which port_service will restart
AP_SERVICES=""         # the service which only used in ap mode
ROUTER_SERVICES=""     # the service which only used in router mode
NET_MODE=""            # the router's network mode
PS_UCI="port_service"  # the uci name of port_service

arch_ps_init_service()             { return 0; }
arch_ps_pre_stop_service()         { return 0; }
arch_ps_post_stop_service()        { return 0; }
arch_ps_pre_start_service()        { return 0; }
arch_ps_post_start_service()       { return 0; }
arch_ps_setup_wan()                { return 0; }
arch_ps_reset_lan()                { return 0; }
arch_ps_rebuild_network()          { return 0; }
arch_ps_reload_firwall()           { return 0; }
arch_ps_transform_config()         { return 0; }
arch_ps_check_service()            { return 0; }
arch_ps_iptv_ctl()                 { return 0; }
. /lib/functions.sh
. /lib/miwifi/miwifi_functions.sh
. /lib/miwifi/arch/lib_arch_port_service.sh


ps_logger() {
    echo -e "[port_service] $*" > /dev/console
    return
}

ps_uci_set() {
    local section="$1"
    local key="$2"
    local value="$3"

    [ -z "$section" ] || [ -z "$key" ] && return

    uci batch <<-EOF
		set "$PS_UCI"."$section"."$key"="$value"
		commit "$PS_UCI"
	EOF
    return
}

ps_uci_get() {
    local section="$1"
    local key="$2"
    local value=""

    [ -z "$section" ] || [ -z "$key" ] && return

    value=$(uci -q get "$PS_UCI"."$section"."$key")
    [ -n "$value" ] && echo "$value"
    return
}

ps_init_service() {
    # when router reboot, must redetect
    [ "1" = "$(ps_uci_get wan wandt)" ] && ps_uci_set wan ports ""

    arch_ps_init_service
    return
}

ps_pre_start_service() {
    arch_ps_pre_start_service
    return
}

ps_post_start_service() {
    [ "whc_cap" != "$NET_MODE" ] && ps_wandt_ctl filter unload

    [ "whc_re" = "$NET_MODE" ] && {
        # in re mode, the topomon must restart when user change the lag's config
        /etc/init.d/topomon restart
    }

    [ "8021q" = "$(port_map config get settings vlan_type)" ] && util_portmap_update

    arch_ps_post_start_service
    return
}

ps_pre_stop_service() {
    # avoid lan device get uppper dhcp server's ip, when wan is in wandt mode
    [ "whc_cap" = "$NET_MODE" ] && ps_wandt_ctl filter load

    arch_ps_pre_stop_service
    return
}

ps_post_stop_service() {
    arch_ps_post_stop_service
    return
}

ps_check_service() {
    arch_ps_check_service "$@"
    return
}

ps_rebuild_network() {
    arch_ps_rebuild_network
    return
}

ps_reload_firewall() {
    arp_intercept() {
        local initted lan_ip lan_mac
        local rule_name="port_service_common"

        # clean all arptables rules
        arptables -F "$rule_name" > /dev/null 2>&1
        arptables -D FORWARD -j "$rule_name" > /dev/null 2>&1
        arptables -X "$rule_name" > /dev/null 2>&1

        # judge if need to add rules
        initted=$(uci -q get xiaoqiang.common.INITTED)
        [ -z "$initted" ] || return

        # if the router uninitted, force all lans only can get his br-lan's macaddr
        lan_ip=$(uci -q get network.lan.ipaddr)
        lan_mac=$(uci -q get network.lan.macaddr)
        [ -n "$lan_ip" ] && [ -n "$lan_mac" ] && {
            arptables -N "$rule_name"
            arptables -I FORWARD -j "$rule_name"
            arptables -I "$rule_name" --h-length 6 --h-type 1 --proto-type 0x800 --opcode 2 -s "$lan_ip" -j mangle --mangle-mac-s "$lan_mac"
        }
        return
    }

    arp_intercept
    arch_ps_reload_firwall
    return
}

ps_default_config() {
    local mode="$1" # "router" or "ap"

    for service in $ROUTER_SERVICES; do
        if [ "$service" = "wan" ] && [ "$mode" = "router" ]; then
            uci set "$PS_UCI"."$service".enable="1"
            uci set "$PS_UCI"."$service".ports=""
            uci set "$PS_UCI"."$service".wandt="1"
        else
            uci set "$PS_UCI"."$service".enable="0"
            uci set "$PS_UCI"."$service".ports=""
        fi
    done
    uci commit "$PS_UCI"
    return
}

ps_transform_config() {
    local mode="$1" # "router" or "ap"
    local service

    for service in $ROUTER_SERVICES; do
        list_contains AP_SERVICES "$service" && continue
        case "$mode" in
            "ap") # transform into ap modes
                    uci set "$PS_UCI"."$service".enable="0"
                ;;
            "router") # transform into router modes
                    [ "$service" = "wan" ] && {
                        uci batch <<-EOF
                            set "$PS_UCI".wan.enable=1
                            set "$PS_UCI".wan.wandt=1
                            set "$PS_UCI".wan.ports=""
                            commit "$PS_UCI"
						EOF
                    }
                ;;
        esac
    done
    uci commit "$PS_UCI"

    arch_ps_transform_config "$mode"
    return
}

ps_wandt_ctl() {
    local action="$1"
    local script="/usr/sbin/wan_detect.sh"

    [ ! -f "$script" ] || [ -z "$action" ] && return

    "$script" "$@"
    return
}

ps_iptv_ctl() {
    local action="$1"
    local script="/usr/sbin/media.sh"

    [ -z "$(port_map port service iptv)" ] && return
    [ ! -x "$script" ] || [ -z "$action" ] && return

    "$script" iptv "$@"
    arch_ps_iptv_ctl "$@"
    ps_logger "iptv $action finish"

    return
}

ps_lag_ctl() {
    local action="$1"
    local script="/usr/sbin/lag.sh"

    [ -z "$(port_map port service lag)" ] && return
    [ ! -f "$script" ] || [ -z "$action" ] && return

    "$script" "$@"
    ps_logger "lag $action finish"
    return
}

ps_game_ctl() {
    local action="$1"
    local script="/usr/sbin/game.sh"

    [ -z "$(port_map port service game)" ] && return
    [ ! -x "$script" ] || [ -z "$action" ] && return

    "$script" "$@"
    ps_logger "game $action finish"
    return
}

ps_wan_ctl() {
    local action="$1"
    local service="$2"
    local wandt ports wandt_ports

    wan_start() {
        local service="$1"

        [ "eth" != "$(ps_uci_get "$service" type)" ] && return
        [ "1" != "$(ps_uci_get "$service" enable)" ] && return

        ports=$(ps_uci_get "$service" ports)
        wandt=$(ps_uci_get "$service" wandt)

        # wan detect only used for wan
        [ "wan" != "$service" ] && wandt="0"

        if [ "$wandt" = "1" ]; then
            # in wandt mode, wan's link_mode must set to auto
            ps_uci_set wan link_mode 0

            # config wandt
            wandt_ports=$(port_map port service lan)
            wandt_ports="${wandt_ports} ${ports}"

            ps_uci_set wandt_attr ports "$(echo "$wandt_ports"|xargs)"
            ps_uci_set wandt_attr enable "1"
            [ -z "$(ps_uci_get wandt_attr mac)" ] && {
                ps_uci_set wandt_attr mac "$(getmac wan)"
            }
            if [ "1" = "$(ps_uci_get wan wantag)" ]; then
                ps_uci_set wandt_attr vid "$(ps_uci_get wantag_attr vid)"
            else
                ps_uci_set wandt_attr vid ""
            fi

            # start wandt program
            ps_wandt_ctl start
            ps_logger "$service start wandt mode finish"
        else
            [ -n "$ports" ] && {
                ps_setup_wan "$service" "$ports"
                ps_logger "$service start fixed mode finish"
            }
            ps_wandt_ctl filter unload
        fi
        return
    }

    wan_stop() {
        local service="$1"

        [ "eth" != "$(ps_uci_get "$service" type)" ] && return

        [ "wan" = "$service" ] && {
            ps_wandt_ctl stop

            # redetect wan port
            [ "1" = "$(ps_uci_get wan wandt)" ] && ps_uci_set wan ports ""
        }

        [ -z "$(port_map port service "$service")" ] && return

        ps_reset_lan "$service"
        ps_logger "$service stop finish"
        return
    }

    list_contains ROUTER_SERVICES "$service" && wan_"$action" "$service"
    return
}

ps_setup_wan() {
    local service="$1"
    local wan_port="$2"
    local proto="$3"
    local wan_dial_vid

    ps_logger "setup $* start"

    # config wan port link mode
    [ "$(port_map config get "$wan_port" type)" = "eth" ] && {
        phyhelper mode set "$wan_port" "$(ps_uci_get "$service" link_mode)"
    }

    # config wan port service
    port_map config set "$wan_port" service "$service"

    # config wan proto
    [ "wan" = "$service" ] && [ -z "$(uci -q get network."$service".proto)" ] && [ -n "$proto" ] && {
        uci batch <<-EOF
            set network."$service".proto="$proto"
            commit network
		EOF
    }

    # get wan tag
    [ "1" = "$(ps_uci_get "$service" wantag)" ] && {
        wan_dial_vid=$(ps_uci_get "${service}tag_attr" vid)
    }

    # config wan network
    arch_ps_setup_wan "$service" "$wan_port" "$proto" "$wan_dial_vid"

    # reload services
    [ "wan" = "$service" ] && ps_iptv_ctl add_wan "$wan_port"
    [ -x /etc/init.d/wan_check ] && /etc/init.d/wan_check restart > /dev/null 2>&1
    [ -x /etc/init.d/miqos ] && /etc/init.d/miqos restart  > /dev/null 2>&1
    [ -x /etc/init.d/dnsmasq ] && /etc/init.d/dnsmasq restart > /dev/null 2>&1
    [ -x /etc/init.d/messagingagent.sh ] && /etc/init.d/messagingagent.sh restart > /dev/null 2>&1

    ps_logger "setup $* finish"
    return
}

ps_reset_lan() {
    local service="$1"
    local old_wan_port

    old_wan_port=$(port_map port service "$service")
    [ -z "$old_wan_port" ] && return

    ps_logger "reset $service $old_wan_port start"

    # reload services
    [ "wan" = "$service" ] && ps_iptv_ctl del_wan "$old_wan_port"

    # revert wan network
    arch_ps_reset_lan "$service" "$old_wan_port"

    # revert port service
    port_map config set "$old_wan_port" service lan

    # revert port link mode
    [ "$(port_map config get "$old_wan_port" type)" = "eth" ] && {
        phyhelper mode set "$old_wan_port" 0
    }

    ps_logger "reset $service $old_wan_port finish"
    return
}
