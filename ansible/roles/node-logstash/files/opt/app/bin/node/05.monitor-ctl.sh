# paths
LOGSTASH_NODE_HEALTH_CHECK_FLAG_PATH=/opt/app/current/conf/appctl/health_check.flag

enableHealthCheck() {
    touch $LOGSTASH_NODE_HEALTH_CHECK_FLAG_PATH
}

disableHealthCheck() {
    rm -rf $LOGSTASH_NODE_HEALTH_CHECK_FLAG_PATH
}

healthCheck() {
    if [ ! -f $LOGSTASH_NODE_HEALTH_CHECK_FLAG_PATH ]; then
        log "health check is disabled, skipping!"
        return
    fi

    log "normal health check"
}