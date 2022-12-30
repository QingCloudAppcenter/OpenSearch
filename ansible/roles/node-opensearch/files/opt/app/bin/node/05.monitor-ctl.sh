# paths
OPENSEARCH_NODE_HEALTH_CHECK_FLAG_PATH=/opt/app/current/conf/appctl/health_check.flag
CHECK_LOCK_PATH=/opt/app/current/conf/appctl/check.lock
REVIVE_LOCK_PATH=/opt/app/current/conf/appctl/revive.lock

enableHealthCheck() {
    touch $OPENSEARCH_NODE_HEALTH_CHECK_FLAG_PATH
}

disableHealthCheck() {
    rm -rf $OPENSEARCH_NODE_HEALTH_CHECK_FLAG_PATH
}

CHECK_SERVICE_LIST=(
    opensearch
)

checkServices() {
    local item
    for item in ${CHECK_SERVICE_LIST[@]}; do
        if ! systemctl is-active $item; then
            log "service: $item is inactive!"
            return $EC_CHECK_SERVICE_INACTIVE
        fi
    done
    return 0
}

CHECK_ENDPOINT_LIST=(
    $MY_IP:9200/opensearch
)

checkEndpoints() {
    local item
    local ip
    local port
    local tmpstr
    for item in ${CHECK_ENDPOINT_LIST[@]}; do
        tmpstr=${item%/*}
        ip=${tmpstr%:*}
        port=${tmpstr#*:}
        if ! nc -z -w5 $ip $port; then
            log "endpoint: $ip:$port can not be detected!"
            return $EC_CHECK_ENDPOINT_DOWN
        fi
    done
    return 0
}

checkClusterHealth() {
    local info=$(getClusterHealthInfo $MY_IP)
    local status=$(echo "$info" | jq -r '.status')
    if [ ! "$status" = "green" ]; then
        log "cluster health: $status"
        return $EC_CHECK_CLUSTER_HEALTH;
    fi
    return 0
}

healthCheck() {
    if [ -e $CHECK_LOCK_PATH ] && kill -0 $(cat $CHECK_LOCK_PATH); then
        log "health check is already running, skipping"
        return
    fi

    trap "rm -f $CHECK_LOCK_PATH; exit" INT TERM EXIT
    echo $$ > $CHECK_LOCK_PATH

    if [ ! -f $OPENSEARCH_NODE_HEALTH_CHECK_FLAG_PATH ]; then
        log "health check is disabled, skipping!"
        return
    fi

    checkServices

    checkEndpoints

    checkClusterHealth

    rm -f $CHECK_LOCK_PATH
}

getReviveList() {
    local res
    local item
    for item in ${CHECK_SERVICE_LIST[@]}; do
        if ! systemctl -q is-active $item; then
            res="$res\n$item"
        fi
    done
    local tmpstr
    local ip
    local port
    local svc
    for item in ${CHECK_ENDPOINT_LIST[@]}; do
        tmpstr=${item%/*}
        ip=${tmpstr%:*}
        port=${tmpstr#*:}
        svc=${item#*/}
        if ! nc -z -w5 $ip $port; then
            if [ -n "$svc" ]; then
                res="$res\n$svc"
            fi
        fi
    done
    # remove duplicated names
    res=$(echo -e "$res" | awk '!x[$0]++')
    echo $res
}

revive() {
    if [ -e $REVIVE_LOCK_PATH ] && kill -0 $(cat $REVIVE_LOCK_PATH); then
        log "revive is already running, skipping"
        return
    fi

    trap "rm -f $REVIVE_LOCK_PATH; exit" INT TERM EXIT
    echo $$ > $REVIVE_LOCK_PATH

    local lst=($(getReviveList))
    local item
    if [ ${#lst[@]} -eq 0 ]; then
        log "cluster health issue, do nothing"
    else
        for item in ${lst[@]}; do
            log "try to revive service: $item"
            systemctl restart $item || :
        done
    fi
    
    rm -f $REVIVE_LOCK_PATH
}