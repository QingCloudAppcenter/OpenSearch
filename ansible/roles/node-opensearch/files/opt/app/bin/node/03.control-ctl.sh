
refreshkeyStore() {
    :
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

preScaleInCheck() {
    if [ ! "$IS_MASTER"  = "true" ]; then
        log "only first master node does pre-scale-in check"
        return
    fi
    local tmplist=($ROLE_NODES)
    if [ "${tmplist[0]}" = "$MY_IP" ]; then
        log "only first master node does pre-scale-in check"
        return
    fi
    if [ -n "$LEAVING_DATA_NODES" ] && [ -n "$LEAVING_MASTER_NODES" ]; then
        log "can not remove master nodes and data nodes together"
        return $EC_SCALEIN_BOTH_NOT_ALLOWED
    fi
    # to do some work
}

scaleIn() {
    log "scale in"
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