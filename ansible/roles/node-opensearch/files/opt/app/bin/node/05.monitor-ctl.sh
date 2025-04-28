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
    if [ "$status" = "red" ]; then
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

    log "refresh all dynamic services"
    refreshAllDynamicServiceStatus
    
    rm -f $REVIVE_LOCK_PATH
}

measure() {
    local res1=$(getClusterMetrics)
    local res2=$(getNodeMetrics)
    echo "$res1 $res2" | jq -cs add
}

getNodesCnt() {
    local tmpstr1=($STABLE_DATA_NODES)
    local tmpstr2=($STABLE_MASTER_NODES)
    tmpstr1=${#tmpstr1[@]}
    tmpstr2=${#tmpstr2[@]}
    echo $((tmpstr1+tmpstr2))
}

getClusterMetrics() {
    local nodeCnt=$(getNodesCnt)
    local rawinfo=$(getClusterHealthInfo $MY_IP)
    if [ -z "$rawinfo" ]; then
        echo "{}"
        return 0
    fi
    local res=$(echo "$rawinfo" | jq --arg ncnt $nodeCnt -c '{
        "cluster_health_status": (if .status == "green" then 0 elif .status == "yellow" then 1 else 2 end),
        "nodes_avail_percent": (.number_of_nodes / ($ncnt | tonumber) * 100),
        "number_of_nodes": .number_of_nodes,
        "relocating_shards": .relocating_shards,
        "initializing_shards": .initializing_shards,
        "unassigned_shards": .unassigned_shards,
        "number_of_pending_tasks": .number_of_pending_tasks,
        "number_of_in_flight_fetch": .number_of_in_flight_fetch,
        "task_max_waiting_in_queue_millis": .task_max_waiting_in_queue_millis,
        "active_shards_percent": .active_shards_percent_as_number
    }')
    echo "$res"
}

getNodeMetrics() {
    local nodename=$(echo -n $(cat $OPENSEARCH_CONF_PATH | sed '/^'node.name':/!d;s/^'node.name'://'))
    local rawinfo=$(getNodeStats $nodename $MY_IP)
    if [ -z "$rawinfo" ]; then
        echo "{}"
        return 0
    fi
    rawinfo=$(echo $rawinfo | jq '.nodes | to_entries[] | .value')
    local res1=$(echo "$rawinfo" | jq -c '{
        "indices_indexing_index_ops": (.indices.indexing.index_total),
        "indices_search_query_ops": (.indices.search.query_total),
        "jvm_mem_heap_used_percent": .jvm.mem.heap_used_percent,
        "jvm_threads_count": .jvm.threads.count,
        "indices_docs_count": .indices.docs.count,
        "indices_docs_deleted": .indices.docs.deleted,
        "fs_total_avail_percent": (.fs.total.available_in_bytes / .fs.total.total_in_bytes * 100),
        "os_cpu_load_average_1m": (.os.cpu.load_average."1m" * 100),
        "os_cpu_load_average_5m": (.os.cpu.load_average."5m" * 100),
        "os_cpu_load_average_15m": (.os.cpu.load_average."15m" * 100),
    }')
    rawinfo=$(getClusterStats $MY_IP | jq '.indices')
    local res2=$(echo "$rawinfo" | jq -c '{
        "indices_count": .count,
        "shards_total": .shards.total,
        "shards_primaries": .shards.primaries
    }')
    echo "$res1 $res2" | jq -cs add
}