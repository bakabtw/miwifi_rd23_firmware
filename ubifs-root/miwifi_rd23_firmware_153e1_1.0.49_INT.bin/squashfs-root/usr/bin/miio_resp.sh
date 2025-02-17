#!/bin/ash

readonly BOUND_CB="/etc/miio/bound.d"
readonly UNBOUND_CB="/etc/miio/unbound.d"

gMethod=
gResult=

bind_cb() {
	local code=

	code=$(echo "$1" | jsonfilter -e "$.code")

	if [ "$code" = "0" ]; then
		uci set miio_ot.ot.bound=1
		uci commit miio_ot

		if [ -d "$BOUND_CB" ]; then
			find "$BOUND_CB" -type f -exec sh -c 'sh $1 &' _ {} \;
		fi
	fi
}

unbind_cb() {
	local code=

	code=$(echo "$1" | jsonfilter -e "$.code")

	if [ "$code" = "0" ]; then
		uci set miio_ot.ot.bound=0
		uci set miio_ot.ot.unbind=1
		uci commit miio_ot

		if [ -d "$UNBOUND_CB" ]; then
			find "$UNBOUND_CB" -type f -exec sh -c 'sh $1 &' _ {} \;
		fi

	fi
}

usage() {
	cat <<-EOF
		Usage: $0 OPTION...
		MIIO Response callback entry

		  -m      Callback method
		  -r      Respose result
	EOF
}

while getopts "m:r:h" opt; do
	case "${opt}" in
	m)
		gMethod=${OPTARG}
		;;
	r)
		gResult=${OPTARG}
		;;
	h)
		usage
		exit
		;;
	\?)
		usage >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

if [ -z "$gMethod" ]; then
	printf "Method not specified!\n" >&2
	exit 2
fi

case "$gMethod" in
"_sync.device_bind")
	bind_cb "$gResult"
	;;
"_sync.device_unbind")
	unbind_cb "$gResult"
	;;
\?)
	printf "Method not supported!\n" >&2
	exit 3
	;;
esac
