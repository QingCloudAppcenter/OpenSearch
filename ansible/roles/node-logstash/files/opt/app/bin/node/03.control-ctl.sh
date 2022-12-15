start() {
    if ! isNodeInitialized; then
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

upgrade() {
    log "just a message for debug"
}