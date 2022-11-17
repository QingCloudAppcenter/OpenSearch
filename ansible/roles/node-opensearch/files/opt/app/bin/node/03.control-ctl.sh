
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

needInitProcess() {
    test ! "$IS_MASTER" = "false"
    local tmplist=($STABLE_MASTER_NODES)
    test "${STABLE_MASTER_NODES[0]}" = "$MY_IP"
}

init() {
    if ! isClusterInitialized; then
        log "prepair config files"
        refreshOpenSearchConf
        refreshJvmOptions
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

    if needInitProcess; then
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

    if needInitProcess; then
        log "restore opensearch.yml"
        restoreOpenSearchConf
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
    for item in $wanted; do
        if echo "$commited" | grep $item; then return 1; fi
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

processBeforeScaleInDataNodes() {
    :
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
    if [ -n "$LEAVING_DATA_NODES" ] && [ -n "$LEAVING_MASTER_NODES" ]; then
        log "can not remove master nodes and data nodes together"
        return $EC_SCALEIN_BOTH_NOT_ALLOWED
    fi
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "process before scale in master nodes"
        processBeforeScaleInMasterNodes
    else
        processBeforeScaleInDataNodes
    fi
}

scaleIn() {
    if [ -z "$LEAVING_MASTER_NODES" ]; then
        log "scale in data nodes, do nothing"
        return
    fi
    
    log "scale in master nodes, refresh opensearch.yml"
    refreshOpenSearchConf
}

processAfterScaleInMasterNodes() {
    local tmplist=($LEAVING_MASTER_NODES_HOSTS)
    if [ ! "$NODE_NAME" = "${tmplist[0]}" ]; then
        log "only first leaving master node runs post-scale-in procession"
        return
    fi
    local mlist=($STABLE_MASTER_NODES)
    local dlist=($STABLE_DATA_NODES)
    local wantlen=$((${#mlist[@]}+${#dlist[@]}))
    local reallen=$(getAllNodesId ${mlist[0]} | wc -l)
    retry 120 5 0 test $wantlen -eq $reallen
    clearMasterExclude ${mlist[0]}
}

destroy() {
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "process after scale in master nodes"
        processAfterScaleInMasterNodes
    else
        :
    fi
}

scaleOut() {
    if [ -z "$JOINING_MASTER_NODES" ]; then
        log "adding data nodes, do nothing!"
        return
    fi
    log "adding master nodes, refresh opensearch.yml"
    refreshOpenSearchConf
}

restart() {
    log "restart"
}