#!/bin/sh

if [ -n "$(uci -q show misc.mld)" ]; then
	uci -q set misc.mld.ap_mlo=
	uci -q set misc.mld.hostap_mlo="5g 5gh"
	uci -q set misc.mld.bh_ap_mlo="5g 5gh"
	uci commit misc
fi
