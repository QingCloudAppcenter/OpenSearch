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