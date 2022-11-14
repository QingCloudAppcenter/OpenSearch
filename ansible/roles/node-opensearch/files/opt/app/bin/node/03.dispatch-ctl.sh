prepairPathOnPersistentDisk() {
    mkdir -p /data/opensearch/{data,logs}
    chown -R opensearch:svc /data/opensearch
}

syncAllConfig() {
    cat $OPENSEARCH_STATIC_SETTINGS_PATH.new > $OPENSEARCH_STATIC_SETTINGS_PATH
}

dispatch() {
    if ! isClusterInitialized; then
        log "new node created! prepaire paths on persistent disk"
        prepairPathOnPersistentDisk
        syncAllConfig
        return
    fi
    if [ "${ADDING_HOSTS_FLAG}" = "true" ] || [ "DELETING_HOSTS_FLAG" = "true" ]; then
        log "adding or deleting nodes"
        return
    fi
    log "normal dispatch check"
}