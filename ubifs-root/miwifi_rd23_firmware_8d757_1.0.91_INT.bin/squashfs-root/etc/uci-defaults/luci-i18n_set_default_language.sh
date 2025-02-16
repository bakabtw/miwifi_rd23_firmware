#!/bin/sh
# keep this file after all luci-i18n-* files

if [ "$(bdata get CountryCode)" = "JP" ]; then
	# set default language to ja for JP SKU
	uci set luci.main.lang=ja
	# remove all language
	uci delete luci.languages
	# set ja, ko_kr, en as available language
	uci set luci.languages=internal
	uci set luci.languages.en=English
	uci set luci.languages.ja=日本語
	uci set luci.languages.ko_kr=한국

	uci commit luci
elif [ "$(bdata get CountryCode)" = "KR" ]; then
	uci set luci.main.lang=ko_kr
	# remove all language
	uci delete luci.languages
	# set ja, ko_kr, en as available language
	uci set luci.languages=internal
	uci set luci.languages.en=English
	uci set luci.languages.ja=日本語
	uci set luci.languages.ko_kr=한국

	uci commit luci
elif [ "$(bdata get CountryCode)" != "CN" ]; then
	# others not CN SKU, use en as default language
	uci set luci.main.lang=en
	uci commit luci
fi
