#!/bin/sh

readonly SPEC_SIID=2
readonly SPEC_DEV_PIID=20

# Check enable
if [ "$(uci -q get "miio_spec.$SPEC_SIID.$SPEC_DEV_PIID")" != "1" ]; then
	return 0
fi

. /usr/share/libubox/jshn.sh

did=$(bdata get miot_did)
eiid=1
if [ "$EVENT" != "1" ]; then
	eiid=2
fi

if ! miio_spec_dev_update_safe.sh "${SPEC_SIID}e${eiid}" "$MAC"; then
	return 0
fi

json_init
json_add_string "method" "event_occured"
json_add_int "id" "1234"

json_add_object "params"
json_add_string "did" "$did"
json_add_int "eiid" "$eiid"
json_add_int "siid" "$SPEC_SIID"

json_add_array "arguments"
json_add_object
json_add_int "piid" "$SPEC_DEV_PIID"
json_add_string "value" "$MAC"
json_close_object
json_close_array
json_close_object

reply=$(json_dump)
json_cleanup

json_init
json_add_string "msg" "$reply"
reply=$(json_dump)
json_cleanup

ubus send miio_proxy "$reply"
