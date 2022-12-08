fakeInitCluster() {
    touch $APPCTL_CLUSTER_FILE
}

start() {
    if ! isNodeInitialized; then
        log "prepare folders"
        prepareFolders
        log "refresh settings"
        refreshDashboardsConf
        log "pretend to init cluster"
        fakeInitCluster
        log "init node"
        _initNode
    fi
    log "start services"
    systemctl start haproxy
    systemctl start keepalived
    systemctl start opensearch-dashboards
    log "enable health check"
    enableHealthCheck
    log "refresh all dynamic service status"
    refreshAllDynamicServiceStatus
}

stop() {
    log "disable health check"
    disableHealthCheck
    log "stop services"
    systemctl stop opensearch-dashboards
    systemctl stop keepalived
    systemctl stop haproxy
}

restart() {
    log "normal restart"
    stop
    start
}

restartService() {
    log "restart service: $1"
    systemctl restart $1
}

upgrade() {
    log "just a message for debug"
}