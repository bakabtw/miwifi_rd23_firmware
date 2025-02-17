#!/bin/sh
###
# @Copyright (C), 2020-2022, Xiaomi CO., Ltd.:
# @Description: Used to configure ACL rules for the specified port
# @Author: Lin Hongqing
# @Date: 2022-09-28 10:00:07
# @Email: linhongqing@xiaomi.com
# @LastEditTime: 2022-09-28 14:22:02
# @LastEditors: Lin Hongqing
# @History: first version
###
readonly PSUCI="port_service"
readonly LOCK_FILE="/var/lock/game_port.lock"

log() {
	logger -t "game_port" -p $1 "$2"
}

# set port as game port
# game port will has the highest priority
port_set_highest_pri() {
	local port=$1
	[ -z "${port}" ] && {
		log err "port_set_highest_pri: port is empty"
	}

	log info "set port $port as game port"

	ssdk_sh qm ucastpriclass set 0 0 0
	ssdk_sh qm ucastpriclass set 0 1 0
	ssdk_sh qm ucastpriclass set 0 2 0
	ssdk_sh qm ucastpriclass set 0 3 0
	ssdk_sh qm ucastpriclass set 0 4 0
	ssdk_sh qm ucastpriclass set 0 5 0
	ssdk_sh qm ucastpriclass set 0 6 0
	ssdk_sh qm ucastpriclass set 0 7 0
	ssdk_sh qm ucastpriclass set 0 8 0
	ssdk_sh qm ucastpriclass set 0 9 0
	ssdk_sh qm ucastpriclass set 0 10 0
	ssdk_sh qm ucastpriclass set 0 11 0
	ssdk_sh qm ucastpriclass set 0 12 0
	ssdk_sh qm ucastpriclass set 0 13 0
	ssdk_sh qm ucastpriclass set 0 14 0
	ssdk_sh qm ucastpriclass set 0 15 0
	ssdk_sh qos ptpriprece set "${port}" 2 3 1 5 6 6 no no 4 4
	ssdk_sh acl list create 0 0
	ssdk_sh acl rule add 0 0 1 no 0x0 0x0 mac no no no no no no no no no no no no no no no no no no no no no no no no no no no no no no yes no no no no no no no no no no 0 0 no no no no no no no no no no no no no no yes 7 no no no no no 0
	ssdk_sh acl list bind 0 0 0 "${port}"

	log info "set port $port as game port finish"
}

# set port as normal port
# flush acl rule
port_flush_acl() {
	log info "flush acl rule"

	ssdk_sh acl rule del 0 0 1
	ssdk_sh acl list destroy 0
}

start() {
	local game_port
	local flag_enable=$(uci -q get "${PSUCI}".game.enable)

	log info "start game port, en:${flag_enable}"

	[ "${flag_enable}" = "1" ] && {
		game_port=$(uci -q get "${PSUCI}".game.ports)
		port_set_highest_pri "${game_port}"
	} || {
		# cleanup game port
		uci batch <<-EOF
			set "$PSUCI".game.ports=""
			commit "$PSUCI"
		EOF
		port_flush_acl
	}
}

stop() {
	port_flush_acl
}

# use lock to block concurrent access
trap "lock -u $LOCK_FILE" EXIT
lock $LOCK_FILE

# main
case "$1" in
start)
	# start game service
	start
	;;
stop)
	# stop game service
	stop
	;;
restart)
	# restart game service
	stop
	start
	;;
*)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
	;;
esac
