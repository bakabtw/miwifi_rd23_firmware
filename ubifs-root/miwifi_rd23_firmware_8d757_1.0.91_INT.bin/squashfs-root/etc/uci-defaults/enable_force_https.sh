#!/bin/sh
# for BSI certification, force https for all web access by default in UK region
if [ "$(bdata get CountryCode)" = "UK" ]; then
	uci set nginx.main.force_https=1
	uci commit nginx
fi
