preparePathOnPersistentDisk() {
    mkdir -p /data/opensearch/dicts /data/logstash/{config,data,dump,logs,plugins}
    chown -R logstash.svc /data/{opensearch,logstash}
}

fakeInitCluster() {
    touch $APPCTL_CLUSTER_FILE
}

syncStaticSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
}

syncDynamicSettings() {
    cat $DYNAMIC_SETTINGS_PATH.new > $DYNAMIC_SETTINGS_PATH
}

syncDependSettings() {
    cat $DEPEND_SETTINGS_PATH.new > $DEPEND_SETTINGS_PATH
}

syncAllSettings() {
    syncStaticSettings
    syncDynamicSettings
    syncDependSettings
}

dispatch() {
    if ! isClusterInitialized; then
        log "new node created! prepare paths on persistent disk"
        preparePathOnPersistentDisk
        log "sync all settings"
        syncAllSettings
        log "fake init cluster"
        fakeInitCluster
        retrun
    fi

    log "normal dispatch"
}