
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