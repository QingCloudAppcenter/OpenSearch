
refreshkeyStore() {
    :
}

isLocalServiceAvailable() {
    local res=$(getClusterDesc)
    local clname=$(echo "$res" | jq -r '.cluster_name')
    test "$clname" = "$CLUSTER_ID"
}

start() {
    if ! isNodeInitialized; then
        log "prepair config files"
        refreshOpenSearchConf
        refreshJvmOptions
        refreshLog4j2Properties
        refreshIKAnalyzerCfgXml
        log "prepair keystore"
        refreshkeyStore
        log "appctl node init"
        _initNode
    fi
    log "start opensearch.service"
    systemctl start opensearch
    log "enable health check"
    enableHealthCheck
}

isFirstMaster() {
    test ! "$IS_MASTER" = "false"
    local tmplist=($STABLE_MASTER_NODES)
    test "${tmplist[0]}" = "$MY_IP"
}

# $1 option, <ip> or $MY_IP
applyAllDynamicSettings() {
    applyClusterNoMasterBlock $@ || :
    applyActionDestructiveRequiresName $@ || :
}

init() {
    if ! isClusterInitialized; then
        log "prepair config files"
        refreshOpenSearchConf
        refreshJvmOptions
        refreshLog4j2Properties
        refreshIKAnalyzerCfgXml
        log "prepair keystore"
        refreshkeyStore
        log "_init"
        _init
    fi

    if [ "$ADDING_HOSTS_FLAG" = "true" ]; then
        log "adding nodes, skipping!"
        return
    fi

    log "inject internal users"
    injectInternalUsers

    if isFirstMaster; then
        log "inject cluster init config in opensearch.yml"
        injectClusterInitConf
    fi

    log "start opensearch.service"
    systemctl start opensearch

    log "wait until local service is ok"
    while ! isLocalServiceAvailable; do
        sleep 5s
    done
    
    log "restore internal users"
    restoreInternalUsers

    if isFirstMaster; then
        log "restore opensearch.yml"
        restoreOpenSearchConf
        log "apply all dynamic settings"
        applyAllDynamicSettings
    fi
}

stop() {
    log "disable health check"
    disableHealthCheck
    log "stop opensearch.service"
    systemctl stop opensearch
}

isMasterExcluded() {
    local clusterco
    if ! clusterco=$(getClusterCoordination); then
        log "failed getting cluster coordination"
        return 1
    fi
    local wanted=$(getNodesIdFromNodesName $@)
    local commited=$(echo "$clusterco" | jq -r '.metadata.cluster_coordination.last_committed_config[]' | xargs)
    local item
    local cnt
    for item in $wanted; do
        cnt=$(echo "$commited" | sed -n "/$item/p" | wc -l)
        if [ "$cnt" -gt 0 ]; then return 1; fi
    done
}

getNodesIdFromNodesName() {
    local mixlist
    local res=""
    if ! mixlist=$(getAllNodesId | awk '{print $1"/"$3}'); then
        echo ""
        return
    fi
    local item
    local tmp
    for item in $@; do
        tmp=$(echo "$mixlist" | sed -n "/^$item/p")
        res="$res ${tmp#*/}"
    done
    echo $res
}

processBeforeScaleInMasterNodes() {
    if ! excludeMasterNodes "${LEAVING_MASTER_NODES_HOSTS// /,}"; then
        log "failed excluding master nodes"
        clearMasterExclude
        return $EC_SCALEIN_FAILED_EXCLUDE_MASTER
    fi

    if ! retry 120 5 0 isMasterExcluded "$LEAVING_MASTER_NODES_HOSTS"; then
        log "timeout waiting for excluding master nodes"
        clearMasterExclude
        return $EC_SCALEIN_WAITING_EXCLUDE_MASTER
    fi
}

hasUnusualIndices() {
    local info=$(getIndicesStatusDocsCount $@)
    local closedcnt=$(echo "$info" | sed -n '/close/p' | wc -l)
    if [ "$closedcnt" -gt 0 ]; then
        log "has closed indices"
        return
    fi
    local nodocscnt=$(echo "$info" | awk '/^open/{if($2==0) print "got it!";exit}' | wc -l)
    if [ "$nodocscnt" -gt 0 ]; then
        log "has indices with 0 docs"
        return
    fi
    return 1
}

isClusterStableWithShards() {
    local info=$(getClusterHealthInfo $@)
    local status=$(echo "$info" | jq -r '.status')
    local relocating=$(echo "$info" | jq '.relocating_shards')
    [ "$status" = "green" ] && [ "$relocating" -eq 0 ]
}

isDataExcluded() {
    local info=$(getNodesDocsCountInfo $@)
    local doccount=$(echo "$info" | jq '.nodes | to_entries | map(.value.indices.docs.count) | add')
    test "$doccount" -eq 0
}

processBeforeScaleInDataNodes() {
    if hasUnusualIndices; then
        log "cluster has closed indices or indices with 0 docs"
        return $EC_SCALEIN_UNUSUAL_INDICES
    fi
    if ! isClusterStableWithShards; then
        log "cluster is not stable with shards, can not scale in data nodes"
        return $EC_SCALEIN_UNSTABLE_SHARDS
    fi
    local res
    if ! res=$(excludeDataNodes "${LEAVING_DATA_NODES// /,}"); then
        log "failed excluding data nodes"
        clearDataExclude
        return $EC_SCALEIN_FAILED_EXCLUDE_DATA
    fi
    local modified=$(echo "$res" | jq -r '.persistent.cluster.routing.allocation.exclude._ip')
    if [ ! "$modified" = "${LEAVING_DATA_NODES// /,}" ]; then
        log "failed excluding data nodes"
        clearDataExclude
        return $EC_SCALEIN_FAILED_EXCLUDE_DATA
    fi
    # wait 2 hour (720*10=7200)
    if ! retry 720 10 0 isDataExcluded "$LEAVING_DATA_NODES"; then
        log "timeout waiting for excluding data nodes"
        clearDataExclude
        return $EC_SCALEIN_WAITING_EXCLUDE_DATA
    fi
}

preScaleInCheck() {
    if [ ! "$IS_MASTER"  = "true" ]; then
        log "only first stable master node does pre-scale-in check"
        return
    fi
    local tmplist=($STABLE_MASTER_NODES)
    if [ ! "${tmplist[0]}" = "$MY_IP" ]; then
        log "only first stable master node does pre-scale-in check"
        return
    fi
    if [ -z "$LEAVING_DATA_NODES" ] && [ -z "$LEAVING_MASTER_NODES" ]; then
        log "remove logstash or dashboards, do nothing"
        return
    fi
    if [ -n "$LEAVING_DATA_NODES" ] && [ -n "$LEAVING_MASTER_NODES" ]; then
        log "can not remove master nodes and data nodes together"
        return $EC_SCALEIN_BOTH_NOT_ALLOWED
    fi
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "process before scale in master nodes"
        processBeforeScaleInMasterNodes
    else
        log "process before scale in data nodes"
        processBeforeScaleInDataNodes
    fi
}

scaleIn() {
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "scale in master nodes, refresh opensearch.yml"
        refreshOpenSearchConf
        return
    fi

    if [ -n "$LEAVING_DATA_NODES" ]; then
        log "scale in data nodes, do nothing"
        return
    fi

    log "scale in logstash or dashboard, do nothing"
}

processAfterScaleInMasterNodes() {
    local tmplist=($LEAVING_MASTER_NODES)
    if [ ! "$MY_IP" = "${tmplist[0]}" ]; then
        log "only first leaving master node runs post-scale-in procession"
        return
    fi
    local mlist=($STABLE_MASTER_NODES)
    local dlist=($STABLE_DATA_NODES)
    local wantlen=$((${#mlist[@]}+${#dlist[@]}))
    local reallen=$(getClusterHealthInfo ${mlist[0]} | jq '.number_of_nodes')
    retry 120 5 0 test $wantlen -eq $reallen
    clearMasterExclude ${mlist[0]}
}

processAfterScaleInDataNodes() {
    local tmplist=($LEAVING_DATA_NODES)
    if [ ! "$MY_IP" = "${tmplist[0]}" ]; then
        log "only first leaving data node runs post-scale-in procession"
        return
    fi
    local mlist=($STABLE_MASTER_NODES)
    local dlist=($STABLE_DATA_NODES)
    local wantlen=$((${#mlist[@]}+${#dlist[@]}))
    local reallen=$(getClusterHealthInfo ${mlist[0]} | jq '.number_of_nodes')
    retry 120 5 0 test $wantlen -eq $reallen
    clearDataExclude ${mlist[0]}
}

destroy() {
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "process after scale in master nodes"
        processAfterScaleInMasterNodes
        return
    fi
    if [ -n "$LEAVING_DATA_NODES" ]; then
        log "process after scale in data nodes"
        processAfterScaleInDataNodes
        return
    fi

    log "normal destory"
}

scaleOut() {
    if [ -n "$JOINING_MASTER_NODES" ]; then
        log "adding master nodes, refresh opensearch.yml"
        refreshOpenSearchConf
        return
    fi

    if [ -n "$JOINING_DATA_NODES" ]; then
        log "adding data nodes, do nothing!"
        return
    fi

    log "scale out logstash or dashboard, do nothing"
}

restart() {
    log "normal restart"
    stop
    start
}