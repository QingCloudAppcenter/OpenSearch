start() {
    if ! isNodeInitialized; then
        log "prepare folders"
        mkdir -p /data/caddy
        chown caddy:svc /data/caddy
        ln -s /opt/app/current/conf/caddy/templates/ /data/opensearch/templates -f
        log "prepare config files"
        refreshJvmOptions
        refreshLogstashYml
        refreshDemoPipeline
        refreshPipeline
        refreshKeystore
        log "appctl node init"
        _initNode
    fi
    log "start logstash.service"
    systemctl start logstash
    log "enable health check"
    enableHealthCheck
    log "refresh all dynamic service status"
    refreshAllDynamicServiceStatus
}

stop() {
    log "disable health check"
    disableHealthCheck
    log "stop service"
    systemctl stop logstash
}

restart() {
    log "normal restart"
    stop
    start
}