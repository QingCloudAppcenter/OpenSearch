
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
    log "start opensearch"
    systemctl start opensearch
    log "start done"
}

needInitProcess() {
    test ! "$ADDING_HOSTS_FLAG" = "true"
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

    log "inject internal users"
    injectInternalUsers

    if needInitProcess; then
        log "inject cluster init config in opensearch.yml"
        injectClusterInitConf
    fi

    log "start opensearch.service"
    systemctl start opensearch

    log "wait until cluster is ok"
    while :; do
        echo "wait for debug"
        sleep 5s;
    done
    
    log "restore internal users"
    restoreInternalUsers

    if needInitProcess; then
        log "restore opensearch.yml"
        restoreOpenSearchConf
    fi
}