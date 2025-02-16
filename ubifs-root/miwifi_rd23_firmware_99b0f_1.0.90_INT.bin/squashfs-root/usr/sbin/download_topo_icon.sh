#!/bin/sh

IP="$1"
NAME="$2"

EXT_ICONS_DIR="/tmp/ext_icons"

[ -z "$IP" -o -z "$NAME" ] && exit 0
[ -d "$EXT_ICONS_DIR" ] || mkdir "$EXT_ICONS_DIR"

download_icon_log() {
    logger -p warn "download_icon [$(date)]: $1"
}

download_icon () {
    local timeout=5
    local proto_list="https http"

    for proto in $proto_list; do
        local url="$proto://$IP/xiaoqiang/web/img/icons/$NAME"
        status=$(curl -k "$url" --connect-timeout $timeout -o "$EXT_ICONS_DIR/${NAME}_tmp" -w "%{http_code}")
        [ "$?" == "0" -a "$status" == "200" ] && {
            download_icon_log "download $url successful."
            mv "$EXT_ICONS_DIR/${NAME}_tmp" "$EXT_ICONS_DIR/$NAME"
            break
        }

        download_icon_log "download $url failed."
    done
}

run_with_lock() {
    {
        download_icon_log "$$, ====== TRY locking......"
        flock -x -w 10 1005
        [ $? -eq "1" ] && { bind_log "$$, ===== GET lock failed. exit 1" ; exit 1 ; }
        download_icon_log "$$, ====== GET lock to RUN."
        $@ 1005>&-
        download_icon_log "$$, ====== END lock to RUN."
    } 1005<>/var/run/download_icon.lock
}

run_with_lock download_icon








