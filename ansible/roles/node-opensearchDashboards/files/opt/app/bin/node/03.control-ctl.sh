fakeInitCluster() {
    touch $APPCTL_CLUSTER_FILE
}

# $1 - service name
# $2, option - pid path
startService() {
    if [ -n "$2" ] && [ -e "$2" ]; then
        log "skipping! pid file: $2 exists"
        return
    fi
    systemctl start $1
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
    startService haproxy
    startService keepalived
    startService opensearch-dashboards $OSD_PID_PATH
}

stop() {
    :
}

reloadService() {
    systemctl restart $1
}