#!/bin/sh
# Copyright (C) 2016 Xiaomi
#

# for d01/r3600, called by trafficd handle whc_sync

USE_ENCODE=1

mesh_version=$(uci -q get xiaoqiang.common.MESH_VERSION)
cap_mode=$(uci -q get xiaoqiang.common.CAP_MODE)
if [ "$ap_mode" = "whc_cap" ] || [ "$mesh_version" -ge "2" -a "$ap_mode" = "lanapmode" -a "$cap_mode" = "ap" ]; then
    exit 0
fi

[ $mesh_version -gt 1 ] && {
    . /lib/mimesh/mimesh_public.sh
} || {
    . /lib/xqwhc/xqwhc_public.sh
}

xqwhc_sync_lock="/var/run/xqwhc_wifi.lock"
cfgf_origin="/var/run/xq_whc_sync"
pid=$$
cfgf="${cfgf_origin}_${pid}"
cfgf_fake="/var/run/xq_whc_sync_fake"
gst_disab_changed=0
son_changed=0   # wifi change, need wifi reset
sys_changed=0
miscan_changed=0
iot_switch_changed=0
B64_ENC=0

support_guest_on_re=$(uci -q get misc.mesh.support_guest_on_re)
[ -z "$support_guest_on_re" ] && support_guest_on_re=0

wifi_parse()
{
    #2g wifi-iface options
    local ssid_2_enc="`cat $cfgf | grep -w "ssid_2g" | awk -F ":=" '{print $2}'`"
    local pswd_2_enc="`cat $cfgf | grep -w "pswd_2g" | awk -F ":=" '{print $2}'`"
    local ssid_2="$ssid_2_enc"
    local pswd_2="$pswd_2_enc"

    if [ "$USE_ENCODE" -gt 0 ]; then
        ssid_2="$(base64_dec "$ssid_2_enc")"
        pswd_2="$(base64_dec "$pswd_2_enc")"
    fi

    local mgmt_2="`cat $cfgf | grep -w "mgmt_2g" | awk -F ":=" '{print $2}'`"
    local hidden_2="`cat $cfgf | grep -w "hidden_2g" | awk -F ":=" '{print $2}'`"
    local disabled_2="`cat $cfgf | grep -w "disabled_2g" | awk -F ":=" '{print $2}'`"
    local bsd_2="`cat $cfgf | grep -w "bsd_2g" | awk -F ":=" '{print $2}'`"
    local sae_2="`cat $cfgf | grep -w "sae_2g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_2_enc="`cat $cfgf | grep -w "sae_passwd_2g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_2="$sae_pswd_2_enc"
    local twt="`cat $cfgf | grep -w "twt" | awk -F ":=" '{print $2}'`"

    if [ "$USE_ENCODE" -gt 0 ]; then
        sae_pswd_2="$(base64_dec "$sae_pswd_2")"
    fi

    local ieee80211w_2="`cat $cfgf | grep -w "ieee80211w_2g" | awk -F ":=" '{print $2}'`"

    [ -z "$ssid_2" ] && {
        WHC_LOGE " xq_whc_sync, wifi options 2g ssid invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    local ifname_2g=$(uci -q get misc.wireless.ifname_2G)
    local iface_2g=$(uci show wireless | grep "ifname='$ifname_2g'" | awk -F"." '{print $2}')
    local ifname_5g=$(uci -q get misc.wireless.ifname_5G)
    local iface_5g=$(uci show wireless | grep "ifname='$ifname_5g'" | awk -F"." '{print $2}')
    local device_2g=$(uci -q get misc.wireless.if_2G)
    local device_5g=$(uci -q get misc.wireless.if_5G)
    
    ssid_2_cur="`uci -q get wireless.$iface_2g.ssid`"
    pswd_2_cur="`uci -q get wireless.$iface_2g.key`"
    [ -z "$pswd_2_cur" ] && pswd_2_cur=""
    mgmt_2_cur="`uci -q get wireless.$iface_2g.encryption`"
    hidden_2_cur="`uci -q get wireless.$iface_2g.hidden`"
    [ -z "$hidden_2_cur" ] && hidden_2_cur=0
    disabled_2_cur="`uci -q get wireless.$iface_2g.disabled`"
    [ -z "$disabled_2_cur" ] && disabled_2_cur=0
    local bsd_2_cur="`uci -q get wireless.$iface_2g.bsd`"
    [ -z "$bsd_2_cur" ] && bsd_2_cur=0
    local sae_2_cur="`uci -q get wireless.$iface_2g.sae`"
    [ -z "$sae_2_cur" ] && sae_2_cur=""
    local sae_pswd_2_cur="`uci -q get wireless.$iface_2g.sae_password`"
    [ -z "$sae_pswd_2_cur" ] && sae_pswd_2_cur=""
    local ieee80211w_2_cur="`uci -q get wireless.$iface_2g.ieee80211w`"
    [ -z "$ieee80211w_2_cur" ] && ieee80211w_2_cur=""
    local twt_cur="`uci -q get wireless.$iface_2g.twt_responder`"
    [ -z "$twt_cur" ] && twt_cur=""

    [ "$ssid_2_cur" != "$ssid_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g ssid change $ssid_2_cur -> $ssid_2"
        uci set wireless.$iface_2g.ssid="$ssid_2"
    }

    if [ "$mgmt_2" == "ccmp" -o "$mgmt_2" == "psk2+ccmp" ]; then
        pswd_2="$sae_pswd_2"
        pswd_2_cur="$sae_pswd_2_cur"
    fi

    [ "$pswd_2_cur" != "$pswd_2" ] && {
        if [ "$mgmt_2" != "none" ]; then
            son_changed=1
            WHC_LOGI " xq_whc_sync, 2g pswd change $pswd_2_cur -> $pswd_2"
        fi
        if [ -n "$pswd_2" ]; then
            uci set wireless.$iface_2g.key="$pswd_2"
        else
            uci -q delete wireless.$iface_2g.key
        fi
    }
    [ "$mgmt_2_cur" != "$mgmt_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g mgmt change $mgmt_2_cur -> $mgmt_2"
        uci set wireless.$iface_2g.encryption="$mgmt_2"
    }
    [ "$hidden_2_cur" != "$hidden_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g hidden change $hidden_2_cur -> $hidden_2"
        uci set wireless.$iface_2g.hidden="$hidden_2"
    }
    [ "$disabled_2_cur" != "$disabled_2" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 2g disabled change $disabled_2_cur -> $disabled_2"
        uci set wireless.$iface_2g.disabled="$disabled_2"
    }
    [ "$bsd_2" != "$bsd_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g bsd change $bsd_2_cur -> $bsd_2"
         uci set wireless.$iface_2g.bsd="$bsd_2"
         uci set lbd.config.PHYBasedPrioritization="$bsd_2"
         uci commit lbd
    }
    [ "$sae_2" != "$sae_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g sae change $sae_2_cur -> $sae_2"
         if [ -n "$sae_2" ];then
            uci set wireless.$iface_2g.sae="$sae_2"
         else
            uci -q delete wireless.$iface_2g.sae
         fi
    }
    [ "$sae_pswd_2" != "$sae_pswd_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g sae password change $sae_pswd_2_cur -> $sae_pswd_2"
         if [ -n "$sae_pswd_2" ];then
            uci set wireless.$iface_2g.sae_password="$sae_pswd_2"
         else
            uci -q delete wireless.$iface_2g.sae_password
         fi
    }
    [ "$ieee80211w_2" != "$ieee80211w_2_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 2g ieee80211w change $ieee80211w_2_cur -> $ieee80211w_2"
         if [ -n "$ieee80211w_2" ];then
            uci set wireless.$iface_2g.ieee80211w="$ieee80211w_2"
         else
            uci -q delete wireless.$iface_2g.ieee80211w
         fi
    }

    [ "$twt_cur" != "$twt" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, twt change $twt_cur -> $twt"
        uci set wireless.$iface_2g.twt_responder="$twt"
        uci set wireless.$iface_5g.twt_responder="$twt"
    }

    #5g wifi-iface options
    local ssid_5_enc="`cat $cfgf | grep -w "ssid_5g" | awk -F ":=" '{print $2}'`"
    local pswd_5_enc="`cat $cfgf | grep -w "pswd_5g" | awk -F ":=" '{print $2}'`"
    local ssid_5="$ssid_5_enc"
    local pswd_5="$pswd_5_enc"

    if [ "$USE_ENCODE" -gt 0 ]; then
        ssid_5="$(base64_dec "$ssid_5_enc")"
        pswd_5="$(base64_dec "$pswd_5_enc")"
    fi

    local mgmt_5="`cat $cfgf | grep -w "mgmt_5g" | awk -F ":=" '{print $2}'`"
    local hidden_5="`cat $cfgf | grep -w "hidden_5g" | awk -F ":=" '{print $2}'`"
    local disabled_5="`cat $cfgf | grep -w "disabled_5g" | awk -F ":=" '{print $2}'`"
    local bsd_5="`cat $cfgf | grep -w "bsd_5g" | awk -F ":=" '{print $2}'`"
    local sae_5="`cat $cfgf | grep -w "sae_5g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_5_enc="`cat $cfgf | grep -w "sae_passwd_5g" | awk -F ":=" '{print $2}'`"
    local sae_pswd_5="$sae_pswd_5_enc"

    if [ "$USE_ENCODE" -gt 0 ]; then
        sae_pswd_5="$(base64_dec "$sae_pswd_5")"
    fi

    local ieee80211w_5="`cat $cfgf | grep -w "ieee80211w_5g" | awk -F ":=" '{print $2}'`"

    [ -z "$ssid_5" ] && {
        WHC_LOGE " xq_whc_sync, wifi options 5g ssid invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    ssid_5_cur="`uci -q get wireless.$iface_5g.ssid`"
    pswd_5_cur="`uci -q get wireless.$iface_5g.key`"
    [ -z "pswd_5_cur" ] && pswd_5_cur=""
    mgmt_5_cur="`uci -q get wireless.$iface_5g.encryption`"
    hidden_5_cur="`uci -q get wireless.$iface_5g.hidden`"
    [ -z "$hidden_5_cur" ] && hidden_5_cur=0
    disabled_5_cur="`uci -q get wireless.$iface_5g.disabled`"
    [ -z "$disabled_5_cur" ] && disabled_5_cur=0
    local bsd_5_cur="`uci -q get wireless.$iface_5g.bsd`"
    [ -z "$bsd_5_cur" ] && bsd_5_cur=0
    local sae_5_cur="`uci -q get wireless.$iface_5g.sae`"
    [ -z "$sae_5_cur" ] && sae_5_cur=""
    local sae_pswd_5_cur="`uci -q get wireless.$iface_5g.sae_password`"
    [ -z "$sae_pswd_5_cur" ] && sae_pswd_5_cur=""
    local ieee80211w_5_cur="`uci -q get wireless.$iface_5g.ieee80211w`"
    [ -z "$ieee80211w_5_cur" ] && ieee80211w_5_cur=""

    [ "$ssid_5_cur" != "$ssid_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g ssid change $ssid_5_cur -> $ssid_5"
        uci set wireless.$iface_5g.ssid="$ssid_5"
    }

    if [ "$mgmt_5" == "ccmp" -o "$mgmt_5" == "psk2+ccmp" ]; then
        pswd_5="$sae_pswd_5"
        pswd_5_cur="$sae_pswd_5_cur"
    fi

    [ "$pswd_5_cur" != "$pswd_5" ] && {
        if [ "$mgmt_5" != "none" ]; then
            son_changed=1
            WHC_LOGI " xq_whc_sync, 5g pswd change $pswd_5_cur -> $pswd_5"
        fi
        if [ -n "$pswd_5" ]; then
           uci set wireless.$iface_5g.key="$pswd_5"
        else
           uci -q delete wireless.$iface_5g.key
        fi
    }
    [ "$mgmt_5_cur" != "$mgmt_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g mgmt change $mgmt_5_cur -> $mgmt_5"
        uci set wireless.$iface_5g.encryption="$mgmt_5"
    }
    [ "$hidden_5_cur" != "$hidden_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g hidden change $hidden_5_cur -> $hidden_5"
        uci set wireless.$iface_5g.hidden="$hidden_5"
    }
    [ "$disabled_5_cur" != "$disabled_5" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, 5g disabled change $disabled_5_cur -> $disabled_5"
        uci set wireless.$iface_5g.disabled="$disabled_5"
    }
    [ "$bsd_5" != "$bsd_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g bsd change $bsd_5_cur -> $bsd_5"
         uci set wireless.$iface_5g.bsd="$bsd_5"
         uci set lbd.config.PHYBasedPrioritization="$bsd_5"
         uci commit lbd
    }
    [ "$sae_5" != "$sae_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g sae change $sae_5_cur -> $sae_5"
         if [ -n "$sae_5" ];then
            uci set wireless.$iface_5g.sae="$sae_5"
         else
            uci -q delete wireless.$iface_5g.sae
         fi
    }
    [ "$sae_pswd_5" != "$sae_pswd_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g sae password change $sae_pswd_5_cur -> $sae_pswd_5"
         if [ -n "$sae_pswd_5" ];then
            uci set wireless.$iface_5g.sae_password="$sae_pswd_5"
         else
            uci -q delete wireless.$iface_5g.sae_password
         fi
    }
    [ "$ieee80211w_5" != "$ieee80211w_5_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, 5g ieee80211w change $ieee80211w_5_cur -> $ieee80211w_5"
         if [ -n "$ieee80211w_5" ];then
            uci set wireless.$iface_5g.ieee80211w="$ieee80211w_5"
         else
            uci -q delete wireless.$iface_5g.ieee80211w
         fi
    }
    
    #2g backhaul wifi-iface
    backhauls="`uci show misc.backhauls.backhaul`"
    flag="`echo $backhauls | grep 2g`"
    uplink_backhaul_2g="`uci show misc.backhauls.backhaul_2g_ap_iface|awk -F "'" '{print $2}'`"
    if [ "x$flag" != "x" -a "$uplink_backhaul_2g" == "wl1" ];then
        backhaul_2g="`uci show misc.backhauls.backhaul_2g_sta_iface|awk -F "'" '{print $2}'`"
        index="`uci show wireless|grep ifname|grep $backhaul_2g|awk -F "." '{print $2}'`"

        sta_ssid_2_cur="`uci -q get wireless.$index.ssid`"
        sta_pswd_2_cur="`uci -q get wireless.$index.key`"
        [ -z "$sta_pswd_2_cur" ] && sta_pswd_2_cur=0
        sta_mgmt_2_cur="`uci -q get wireless.$index.encryption`"
        sta_hidden_2_cur="`uci -q get wireless.$index.hidden`"
        [ -z "$sta_hidden_2_cur" ] && sta_hidden_2_cur=0
        sta_sae_2_cur="`uci -q get wireless.$index.sae`"
        [ -z "$sta_sae_2_cur" ] && sta_sae_2_cur=""
        sta_sae_pswd_2_cur="`uci -q get wireless.$index.sae_password`"
        [ -z "$sta_sae_pswd_2_cur" ] && sta_sae_pswd_2_cur=""
        sta_ieee80211w_2_cur="`uci -q get wireless.$index.ieee80211w`"
        [ -z "$sta_ieee80211w_2_cur" ] && sta_ieee80211w_2_cur=""

        [ "$sta_ssid_2_cur" != "$ssid_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g ssid change $sta_ssid_2_cur -> $ssid_2"
            uci set wireless.$index.ssid="$ssid_2"
        }
        [ "$sta_pswd_2_cur" != "$pswd_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g pswd change $sta_pswd_2_cur -> $pswd_2"
            if [ -n "$pswd_2" ]; then
                uci set wireless.$index.key="$pswd_2"
            else
                uci delete wireless.$index.key
            fi
        }
        [ "$sta_mgmt_2_cur" != "$mgmt_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g mgmt change $sta_mgmt_2_cur -> $mgmt_2"
            uci set wireless.$index.encryption="$mgmt_2"
        }
        [ "$sta_hidden_2_cur" != "$hidden_2" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g hidden change $sta_hidden_2_cur -> $hidden_2"
            uci set wireless.$index.hidden="$hidden_2"
        }
        [ "$sae_2" != "$sta_sae_2_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g sae change $sta_sae_2_cur -> $sae_2"
            if [ -n "$sae_2" ];then
                uci set wireless.$index.sae="$sae_2"
            else
                uci -q delete wireless.$index.sae
            fi
        }
        [ "$sae_pswd_2" != "$sta_sae_pswd_2_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g sae password change $sta_sae_pswd_2_cur -> $sae_pswd_2"
            if [ -n "$sae_pswd_2" ];then
                uci set wireless.$index.sae_password="$sae_pswd_2"
            else
                uci -q delete wireless.$index.sae_password
            fi
        }
        [ "$ieee80211w_2" != "$sta_ieee80211w_2_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 2g ieee80211w change $sta_ieee80211w_2_cur -> $ieee80211w_2"
            if [ -n "$ieee80211w_2" ];then
                uci set wireless.$index.ieee80211w="$ieee80211w_2"
            else
                uci -q delete wireless.$index.ieee80211w
            fi
        }
    fi

    #5g backhaul wifi-iface
    backhauls="`uci show misc.backhauls.backhaul`"
    flag="`echo $backhauls | grep  5g`"
    uplink_backhaul_5g="`uci show misc.backhauls.backhaul_5g_ap_iface|awk -F "'" '{print $2}'`"
    if [ "x$flag" != "x" -a "$uplink_backhaul_5g" == "wl0" ];then
        backhaul_5g="`uci show misc.backhauls.backhaul_5g_sta_iface|awk -F "'" '{print $2}'`"
        index="`uci show wireless|grep ifname|grep $backhaul_5g|awk -F "." '{print $2}'`"

        sta_ssid_5_cur="`uci -q get wireless.$index.ssid`"
        sta_pswd_5_cur="`uci -q get wireless.$index.key`"
        [ -z "$sta_pswd_5_cur" ] && sta_pswd_5_cur=0
        sta_mgmt_5_cur="`uci -q get wireless.$index.encryption`"
        sta_hidden_5_cur="`uci -q get wireless.$index.hidden`"
        [ -z "$sta_hidden_5_cur" ] && sta_hidden_5_cur=0
        sta_sae_5_cur="`uci -q get wireless.$index.sae`"
        [ -z "$sta_sae_5_cur" ] && sta_sae_5_cur=""
        sta_sae_pswd_5_cur="`uci -q get wireless.$index.sae_password`"
        [ -z "$sta_sae_pswd_5_cur" ] && sta_sae_pswd_5_cur=""
        sta_ieee80211w_5_cur="`uci -q get wireless.$index.ieee80211w`"
        [ -z "$sta_ieee80211w_5_cur" ] && sta_ieee80211w_5_cur=""

        [ "$sta_ssid_5_cur" != "$ssid_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g ssid change $sta_ssid_5_cur -> $ssid_5"
            uci set wireless.$index.ssid="$ssid_5"
        }
        [ "$sta_pswd_5_cur" != "$pswd_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g pswd change $sta_pswd_5_cur -> $pswd_5"
            if [ -n "$pswd_5" ]; then
                uci set wireless.$index.key="$pswd_5"
            else
                uci -q delete wireless.$index.key
            fi
        }
        [ "$sta_mgmt_5_cur" != "$mgmt_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g mgmt change $sta_mgmt_5_cur -> $mgmt_5"
            uci set wireless.$index.encryption="$mgmt_5"
        }
        [ "$sta_hidden_5_cur" != "$hidden_5" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g hidden change $sta_hidden_5_cur -> $hidden_5"
            uci set wireless.$index.hidden="$hidden_5"
        }
        [ "$sae_5" != "$sta_sae_5_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g sae change $sta_sae_5_cur -> $sae_5"
            if [ -n "$sae_5" ];then
                uci set wireless.$index.sae="$sae_5"
            else
                uci -q delete wireless.$index.sae
            fi
        }
        [ "$sae_pswd_5" != "$sta_sae_pswd_5_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g sae password change $sta_sae_pswd_5_cur -> $sae_pswd_5"
            if [ -n "$sae_pswd_5" ];then
                uci set wireless.$index.sae_password="$sae_pswd_5"
            else
                uci -q delete wireless.$index.sae_password
            fi
        }
        [ "$ieee80211w_5" != "$sta_ieee80211w_5_cur" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, backhaul 5g ieee80211w change $sta_ieee80211w_5_cur -> $ieee80211w_5"
            if [ -n "$ieee80211w_5" ];then
                uci set wireless.$index.ieee80211w="$ieee80211w_5"
            else
                uci -q delete wireless.$index.ieee80211w
            fi
        }
    fi

    # wifi-device options
    local txp_2="`cat $cfgf | grep -w "txpwr_2g" | awk -F ":=" '{print $2}'`"
    local ch_2="`cat $cfgf | grep -w "ch_2g" | awk -F ":=" '{print $2}'`"
    [ -z "$ch_2" -o "0" = "$ch_2" ] && ch_2="auto"
    local bw_2="`cat $cfgf | grep -w "bw_2g" | awk -F ":=" '{print $2}'`"
    local txbf_2="`cat $cfgf | grep -w "txbf_2g" | awk -F ":=" '{print $2}'`"
    local ax_2="`cat $cfgf | grep -w "ax_2g" | awk -F ":=" '{print $2}'`"
    local txp_2_cur="`uci -q get wireless.$device_2g.txpwr`"
    [ -z "$txp_2_cur" ] && txp_2_cur="max"
    local ch_2_cur="`uci -q get wireless.$device_2g.channel`"
    [ -z "$ch_2_cur" -o "0" = "$ch_2_cur" ] && ch_2_cur="auto"
    local bw_2_cur="`uci -q get wireless.$device_2g.bw`"
    [ -z "$bw_2_cur" ] && bw_2_cur=0
    local txbf_2_cur="`uci -q get wireless.$device_2g.txbf`"
    [ -z "$txbf_2_cur" ] && txbf_2_cur=3
    local ax_2_cur="`uci -q get wireless.$device_2g.ax`"
    [ -z "$ax_2_cur" ] && ax_2_cur=1

    [ "$ch_2" != "$ch_2_cur" ] && {
        uci set wireless.$device_2g.channel="$ch_2"
        # check real channel, if SAME then should save one wifi reset
        local ch_2_act="`iwlist wl1 channel | grep "Current Channel" | grep -Eo "[0-9]+"`"
        [ "$ch_2" != "$ch_2_act" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, $device_2g dev change channel $ch_2_act -> $ch_2 "
        }
    }

    [ "$txp_2" != "$txp_2_cur" -o "$bw_2" != "$bw_2_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device_2g dev change $txp_2_cur:$bw_2_cur -> $txp_2:$bw_2 "
        uci set wireless.$device_2g.txpwr="$txp_2"
        uci set wireless.$device_2g.bw="$bw_2"
    }

    [ -n "$txbf_2" -a "$txbf_2" -ne "$txbf_2_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device_2g dev change txbf [$txbf_2_cur] -> [$txbf_2]"
        uci set wireless.$device_2g.txbf="$txbf_2"
    }
    [ -n "$ax_2" -a "$ax_2" -ne "$ax_2_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device_2g dev change ax [$ax_2_cur] -> [$ax_2]"
        uci set wireless.$device_2g.ax="$ax_2"
    }

    local txp_5="`cat $cfgf | grep -w "txpwr_5g" | awk -F ":=" '{print $2}'`"
    local ch_5="`cat $cfgf | grep -w "ch_5g" | awk -F ":=" '{print $2}'`"
    [ -z "$ch_5" -o "0" = "$ch_5" ] && ch_5="auto"
    local bw_5="`cat $cfgf | grep -w "bw_5g" | awk -F ":=" '{print $2}'`"
    local txbf_5="`cat $cfgf | grep -w "txbf_5g" | awk -F ":=" '{print $2}'`"
    local ax_5="`cat $cfgf | grep -w "ax_5g" | awk -F ":=" '{print $2}'`"
    local txp_5_cur="`uci -q get wireless.$device_5g.txpwr`"
    [ -z "$txp_5_cur" ] && txp_5_cur="max"
    local ch_5_cur="`uci -q get wireless.$device_5g.channel`"
    [ -z "$ch_5_cur" -o "0" = "$ch_5_cur" ] && ch_5_cur="auto"
    local bw_5_cur="`uci -q get wireless.$device_5g.bw`"
    [ -z "$bw_5_cur" ] && bw_5_cur=0
    local txbf_5_cur="`uci -q get wireless.$device_5g.txbf`"
    [ -z "$txbf_5_cur" ] && txbf_5_cur=3
    local ax_5_cur="`uci -q get wireless.$device_5g.ax`"
    [ -z "$ax_5_cur" ] && ax_5_cur=1
    local support160="`cat $cfgf | grep -w "support160" | awk -F ":=" '{print $2}'`"

    [ "$ch_5" != "$ch_5_cur" ] && {
        uci set wireless.$device_5g.channel="$ch_5"
        # check real channel, if SAME then should save one wifi reset
        local ch_5_act="`iwlist wl0 channel | grep "Current Channel" | grep -Eo "[0-9]+"`"
        [ "$ch_5" != "$ch_5_act" ] && {
            son_changed=1
            WHC_LOGI " xq_whc_sync, $device_5g dev change channel $ch_5_act -> $ch_5 "
        }
    }
    [ "$txp_5" != "$txp_5_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device_5g dev change $txp_5_cur -> $txp_5"
        uci set wireless.$device_5g.txpwr="$txp_5"
    }

    [ "$bw_5" != "$bw_5_cur" ] && {
        local support160_cur=$(uci -q get misc.features.support160Mhz)
        if [ "$support160_cur" == "0" -a "$bw_5" == "160" ]; then
            if [ "$bw_5_cur" != "80" ]; then
                son_changed=1
                WHC_LOGI " xq_whc_sync, $device_5g dev change $bw_5_cur -> 80"
                uci set wireless.$device_5g.bw="80"
            fi
        else
            son_changed=1
            WHC_LOGI " xq_whc_sync, $device_5g dev change $bw_5_cur -> $bw_5"
            uci set wireless.$device_5g.bw="$bw_5"
        fi
    }

    [ -n "$txbf_5" -a "$txbf_5" -ne "$txbf_5_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device_5g dev change txbf [$txbf_5_cur] -> [$txbf_5]"
        uci set wireless.$device_5g.txbf="$txbf_5"
    }

    [ -n "$ax_5" -a "$ax_5" -ne "$ax_5_cur" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, $device_5g dev change ax [$ax_5_cur] -> [$ax_5]"
        uci set wireless.$device_5g.ax="$ax_5"
    }

    #iot switch
    local iot_switch_cur="`uci -q get wireless.miot_2G.userswitch`"
    [ -z "$iot_switch_cur" ] && iot_switch_cur=1
    local iot_switch="`cat $cfgf | grep -w "iot_switch" | awk -F ":=" '{print $2}'`"
    [ -n "$iot_switch" -a "$iot_switch" -ne "$iot_switch_cur" ] && {
        iot_switch_changed=1
        WHC_LOGI " xq_whc_sync, iot user switch changed [$iot_switch_cur] -> [$iot_switch]"
        uci set wireless.miot_2G.userswitch="$iot_switch"
    }

    uci commit wireless && sync
    return 0;
}

guest_parse()
{
    local disab="`cat $cfgf | grep -w "gst_disab" | awk -F ":=" '{print $2}'`"
    [ -z "$disab" ] && disab=0
    local mgmt="`cat $cfgf | grep -w "gst_mgmt" | awk -F ":=" '{print $2}'`"
    local sae="`cat $cfgf | grep -w "gst_sae" | awk -F ":=" '{print $2}'`"
    local sae_pswd="`cat $cfgf | grep -w "gst_sae_pswd" | awk -F ":=" '{print $2}'`"
    local ieee80211w="`cat $cfgf | grep -w "gst_ieee80211w" | awk -F ":=" '{print $2}'`"
    local ssid_enc="`cat $cfgf | grep -w "gst_ssid" | awk -F ":=" '{print $2}'`"
    local pswd_enc="`cat $cfgf | grep -w "gst_pswd" | awk -F ":=" '{print $2}'`"
    local ssid="$ssid_enc"
    local pswd="$pswd_enc"
    if [ "$USE_ENCODE" -gt 0 ]; then
        [ -n "$ssid" ] && ssid="$(base64_dec "$ssid_enc")"
        [ -n "$pswd" ] && pswd="$(base64_dec "$pswd_enc")"
        [ -n "$sae_pswd" ] && sae_pswd="$(base64_dec "$sae_pswd")"
    fi

    # if guest section no exist, create first
    local disab_cur=""
    local ssid_cur=""
    local pswd_cur=""
    local mgmt_cur=""
    local sae_cur=""
    local sae_pswd_cur=""
    local ieee80211w_cur=""

    local gst_sect="guest_2G"
    if uci -q get wireless.$gst_sect >/dev/null 2>&1; then
        disab_cur="`uci -q get wireless.$gst_sect.disabled`"
        [ -z "$disab_cur" ] && disab_cur=0;
        if [ "$disab" != "$disab_cur" -a "$disab" = "1" ]; then
            WHC_LOGI " xq_whc_sync, guest section delete"
            /usr/sbin/guestwifi.sh cleanup
            son_changed=1
            gst_disab_changed=1
            return
        fi

        ssid_cur="`uci -q get wireless.$gst_sect.ssid`"
        pswd_cur="`uci -q get wireless.$gst_sect.key`"
        mgmt_cur="`uci -q get wireless.$gst_sect.encryption`"
        if [ "$mgmt_cur" = "ccmp" ] || [ "$mgmt_cur" = "psk2+ccmp" ]; then
            sae_cur="`uci -q get wireless.$gst_sect.sae`"
            sae_pswd_cur="`uci -q get wireless.$gst_sect.sae_password`"
            ieee80211w_cur="`uci -q get wireless.$gst_sect.ieee80211w`"
        fi
    else
        if [ "$disab" != "1" ]; then
            [ "$mgmt" = "ccmp" -o "$mgmt" = "psk2+ccmp" ] && pswd=$sae_pswd
            WHC_LOGI " xq_whc_sync, guest section newly add[ssid:$ssid, mgmt:$mgmt, pswd:$pswd, disab:$disab], TODO son options"
            /usr/sbin/guestwifi.sh setup "$ssid" "$mgmt" "$pswd" "$disab"
            son_changed=1
            gst_disab_changed=1
        fi
        return
    fi

    [ -z "$ssid" ] && {
        WHC_LOGE " xq_whc_sync, guest options invalid ignore!"
        cp "$cfgf" "$cfgf_fake"
        return 1
    }

    local device=$(uci -q get misc.wireless.if_5G)
    local ifname=$(uci -q get misc.wireless.ifname_guest_5G)
    [ -z "$device" -o -z "$ifname" ] && {
        gst_support_5g=1
        guest_sect_5g="guest_5G"
    }

    [ "$ssid_cur" != "$ssid" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest ssid change $ssid_cur -> $ssid"
        uci set wireless..ssid="$ssid"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.ssid="$ssid"
    }
    [ "$pswd_cur" != "$pswd" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest pswd change $pswd_cur -> $pswd"
        uci set wireless.$gst_sect.key="$pswd"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.key="$pswd"
    }
    [ "$mgmt_cur" != "$mgmt" ] && {
        son_changed=1
        WHC_LOGI " xq_whc_sync, guest mgmt change $mgmt_cur -> $mgmt"
        uci set wireless.$gst_sect.encryption="$mgmt"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.encryption="$mgmt"
    }

    [ "$sae" != "$sae_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, guest sae change $sae_cur -> $sae"
         if [ -n "$sae" ];then
            uci set wireless.$gst_sect.sae="$sae"
            [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.sae="$sae"
         else
            uci -q delete wireless.$gst_sect.sae
            uci -q delete wireless.$gst_sect_5g.sae
         fi
    }
    [ "$sae_pswd" != "$sae_pswd_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, guest sae password change $sae_pswd_cur -> $sae_pswd"
         if [ -n "$sae_pswd" ];then
            uci set wireless.$gst_sect.sae_password="$sae_pswd"
            [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.sae="$sae"
         else
            uci -q delete wireless.$gst_sect.sae_password
            uci -q delete wireless.$gst_sect_5g.sae_password
         fi
    }
    [ "$ieee80211w" != "$ieee80211w_cur" ] && {
         son_changed=1
         WHC_LOGI " xq_whc_sync, guest ieee80211w change $ieee80211w_cur -> $ieee80211w"
         if [ -n "$ieee80211w" ];then
            uci set wireless.$gst_sect.ieee80211w="$ieee80211w"
            [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.ieee80211w="$ieee80211w"
         else
            uci -q delete wireless.$gst_sect.ieee80211w
            uci -q delete wireless.$gst_sect_5g.ieee80211w
         fi
    }

    if [ "$disab_cur" != "$disab" ]; then
        son_changed=1
        gst_disab_changed=1
        WHC_LOGI " xq_whc_sync, guest disab change $disab_cur -> $disab"
        uci set wireless.$gst_sect.disabled="$disab"
        [ "$gst_support_5g" == "1" ] && uci set wireless.$gst_sect_5g.disabled="$disab"
    else
        [ "$disab" = 1 -a "$son_changed" -gt 0 ] && {
            WHC_LOGI " xq_whc_sync, guest disab, with option change, ignore reset"
            son_changed=0
        }
    fi

    uci commit wireless && sync

    return 0
}

system_parse()
{
    local tz_index="$(cat $cfgf | grep -w "tz_index" | awk -F ":=" '{print $2}')"
    local timezone="`cat $cfgf | grep -w "timezone" | awk -F ":=" '{print $2}'`"
    local timezone_cur="`uci -q get system.@system[0].timezone`"
    [ "$timezone_cur" != "$timezone" ] && {
        sys_changed=1
        WHC_LOGI " xq_whc_sync, system timezone change $timezone_cur -> $timezone"
        uci set system.@system[0].timezone="$timezone"
        [ -n "$tz_index" ] && uci set system.@system[0].timezoneindex="$tz_index"
        uci commit system
        /etc/init.d/timezone restart
    }

    local ota_auto="`cat $cfgf | grep -w "ota_auto" | awk -F ":=" '{print $2}'`"
    [ -z "$ota_auto" ] && ota_auto=0
    local ota_auto_cur="`uci -q get otapred.settings.auto`"
    [ -z "$ota_auto_cur" ] && ota_auto_cur=0
    local ota_time="`cat $cfgf | grep -w "ota_time" | awk -F ":=" '{print $2}'`"
    local ota_time_cur="`uci -q get otapred.settings.time`"
    [ -z "$ota_time_cur" ] && ota_time_cur=4
    [ "$ota_auto" != "$ota_auto_cur" -o "$ota_time" != "$ota_time_cur" ] && {
        sys_changed=1
        WHC_LOGI " xq_whc_sync, system ota change $ota_auto_cur,$ota_time_cur -> $ota_auto,$ota_time"
        uci set otapred.settings.auto="$ota_auto"
        uci set otapred.settings.time="$ota_time"
        uci commit otapred
    }

    # 最近一次设置生效原则：
    # 首次Mesh组网CAP同步后，如果用户单独在RE界面设置，则覆盖原CAP同步的情况；
    # 用户最新在CAP设置了以后，RE按最新设置同步
    local led_mesh_sync_disabled="$(uci -q get xiaoqiang.common.led_mesh_sync_disabled)"
    local led_blue_cur="`uci -q get xiaoqiang.common.BLUE_LED`"
    local led_blue="`cat $cfgf | grep -w "led_blue" | awk -F ":=" '{print $2}'`"
    local led_blue_sum="`cat $cfgf | grep -w "led_blue_sum" | awk -F ":=" '{print $2}'`"
    local led_blue_sum_cur="`uci -q get xiaoqiang.common.BLUE_LED_SUM`"
    
    local ethled_cur="`uci -q get xiaoqiang.common.ETHLED`"
    local ethled="`cat $cfgf | grep -w "ethled" | awk -F ":=" '{print $2}'`"
    local ethled_sum="`cat $cfgf | grep -w "ethled_sum" | awk -F ":=" '{print $2}'`"
    local ethled_sum_cur="`uci -q get xiaoqiang.common.ETHLED_SUM`"

    # 兼容旧版，RE修改过配置后，led_mesh_sync_disabled置位，不再同步
    # 如果CAP是新版，带led_blue_sum，则当sum不相等时，说明CAP修改了配置，RE需要同步最新的配置
    if [ -z "$led_blue_sum" -a "$led_mesh_sync_disabled" != "1" ] || [ "$led_blue_sum" != "$led_blue_sum_cur" ] ; then
        uci -q set xiaoqiang.common.led_mesh_sync_disabled=0
        uci -q set xiaoqiang.common.BLUE_LED_SUM="$led_blue_sum"
        uci commit xiaoqiang
        [ -z "$led_blue" ] && led_blue=1
        [ -z "$led_blue_cur" ] && led_blue_cur=1
        if [ "$led_blue" != "$led_blue_cur" ]; then
            WHC_LOGI " xq_whc_sync, system led change $led_blue_cur -> $led_blue"

            if [ "$led_blue" -eq 0 ]; then
                led_ctl led_off
            else
                led_ctl led_on
            fi
        fi
    fi

    # 不相等，说明CAP新修改了配置，RE按最新配置同步
    [ "$ethled_sum" != "$ethled_sum_cur" ] && {
        uci -q set xiaoqiang.common.ETHLED_SUM="$ethled_sum"
        uci commit xiaoqiang
        [ -z "$ethled" ] && ethled=1
        [ -z "$ethled_cur" ] && ethled_cur=1
        [ "$ethled" != "$ethled_cur" ] && {
        WHC_LOGI " xq_whc_sync, ethernet led change $ethled_cur -> $ethled"
            # save ethled
            [ "$ethled" == "0" ] && {
                led_ctl led_off ethled
            } || {
                [ "$ethled" == "1" ] && {
                    led_ctl led_on ethled
                }
            }
        }
    }

    local fan_mode="`cat $cfgf | grep -w "fan_mode" | awk -F ":=" '{print $2}'`"
    local temp_config_sum="`cat $cfgf | grep -w "temp_config_sum" | awk -F ":=" '{print $2}'`"
    local temp_config_sum_cur="`uci -q get mitempctrl.settings.config_sum`"
    [ "$temp_config_sum" != "$temp_config_sum_cur" ] && {
        uci -q set mitempctrl.settings.config_sum="$temp_config_sum"
        uci commit mitempctrl
        [ -z "$fan_mode" ] && fan_mode=0
        local fan_mode_cur="`uci -q get mitempctrl.settings.mode`"
        [ -z "$fan_mode_cur" ] && fan_mode_cur=0
        [ "$fan_mode" != "$fan_mode_cur" ] && {
            WHC_LOGI " xq_whc_sync, fan mode change $fan_mode_cur -> $fan_mode"
            # save fan mode
            uci set mitempctrl.settings.mode="$fan_mode"
            uci commit mitempctrl
            ubus call mitempctrl reload
            /etc/init.d/powerctl restart
        }
    }

    return 0
}

miscan_parse()
{
    local miscan_enable="`cat $cfgf | grep -w "miscan_enable" | awk -F ":=" '{print $2}'`"
    local miscan_enable_cur="`uci -q get miscan.config.enabled`"
    [ "$miscan_enable_cur" != "$miscan_enable" ] && {
        miscan_changed=1
        WHC_LOGI " xq_whc_sync, miscan status change $miscan_enable_cur -> $miscan_enable"
        uci set miscan.config.enabled="$miscan_enable"
        uci commit miscan
    }

    return 0
}

bak_config()
{
    cp "$cfgf_origin" "$cfgf"
}

clean_config()
{
    rm "$cfgf"
}

bak_config

# must call guest_parse first
[ "$support_guest_on_re" -gt 0 ] && {
    guest_parse
    local guest_ret=$?
    if [ "$guest_ret" -gt 0 ]; then
        clean_config
        return $guest_ret
    fi

    if [ "$gst_disab_changed" = "1" ]; then
        WHC_LOGI " xq_whc_sync, gst_disab_changed, reload guestwifi_separation module!"
        local gst_disabled=$(uci -q get wireless.guest_2G.disabled)
        if [ "$gst_disabled" = "1" ]; then
            /etc/init.d/guestwifi_separation stop
        else
            /etc/init.d/guestwifi_separation restart
        fi
    fi
}
wifi_parse
wifi_ret=$?
if [ "$wifi_ret" -gt 0 ]; then
    clean_config
    return $wifi_ret
fi
system_parse
miscan_parse

if [ "$miscan_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, miscan_changed, restart miscan!"
    (/etc/init.d/scan restart) &
fi

if [ "$iot_switch_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, iot user switch changed!"
    userswitch=$(uci -q get wireless.miot_2G.userswitch)
    miot_2g_ifname=$(uci -q get misc.wireless.iface_miot_2g_ifname)
    bindstatus=$(uci -q get wireless.miot_2G.bindstatus)
    miot_2g_device=$(uci -q get wireless.miot_2G.device)
    miot_2g_network=$(uci -q get wireless.miot_2G.network)
    if [ "$bindstatus" = "1" ]; then
        if [ "$userswitch" != "0" ]; then
            ifconfig $miot_2g_ifname up
            brctl addif br-$miot_2g_network $miot_2g_ifname

        else
            ifconfig $miot_2g_ifname down
            brctl delif br-$miot_2g_network $miot_2g_ifname
        fi
    fi
fi

if [ "$sys_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, sys_changed, restart ntp!"
    # wait son update and reconnect
    if [ "$son_changed" -gt 0 ]; then
        (sleep 60; ntpsetclock now) &
    else
        (ntpsetclock now) &
    fi
fi

if [ "$son_changed" -gt 0 ]; then
    WHC_LOGI " xq_whc_sync, son_changed, update wifi!"
    ( lock "$xqwhc_sync_lock";
    /sbin/wifi update;
    lock -u "$xqwhc_sync_lock" ) &
else
    WHC_LOGD " xq_whc_sync, son NO change!"
fi

clean_config
