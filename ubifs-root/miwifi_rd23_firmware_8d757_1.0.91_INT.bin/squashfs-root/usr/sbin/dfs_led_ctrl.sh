#!/bin/sh

support160m=$(uci -q get misc.wireless.support_160m)
if_5g=$(uci -q get misc.wireless.if_5G)
bw=`uci -q get wireless.${if_5g}.bw`
if [ "$bw" != "0" -o "$support160m" != "1" ]; then
    #echo "$$ do not match dfs return " >>/tmp/dfs_check
    return
fi

ifname=$(uci -q get misc.wireless.ifname_5G)

dfs_end="0"
#第一个循环用来检测驱动是否有在进行dfs cac,实测2s内必能准确检测到是否进行DFS，这里用5s可以保证不出问题
for i in $(seq 1 5)
do
    dfs_time=$(iwpriv $ifname get DfsCacTime | awk -F ':' {'print $2'})
    echo "$$ DFS time=$dfs_time...dfs_end=$dfs_end..." >>/tmp/dfs_check
    #如果dfs time不为0表示正在进行dfs，定时70s > 65秒检测 dfs是否结束，如果结束就break退出循环
    if [ "$dfs_time" != "0" ]; then
        #第二个循环用来检测dfs是否结束
        for i in $(seq 1 70)
        do
            #系统蓝灯在DFS之后，需要定期设置蓝灯闪烁在DFS期间
            #wifi 重启过程中偶现闪灯，经调查是偶现的命令返回'wl0       get:DfsCacTime'
            if [ "$dfs_time" != "DfsCacTime" ]; then
                xqled dfs_blink >/dev/null 2>&1
            fi
            dfs_time=$(iwpriv $ifname get DfsCacTime | awk -F ':' {'print $2'})
            if [ "$dfs_time" == "0" ]; then
                dfs_end="1"
                #DFS LED OFF
                #echo "$$ DFS LED OFF....." >>/tmp/dfs_check
                xqled sys_ok >/dev/null 2>&1
                break
            fi
            sleep 1
        done
    fi
    #dfs结束就break退出循环,无需再检测驱动是否进行dfs
    if [ "$dfs_end" == "1" ]; then
        break
    fi
    sleep 1
done
