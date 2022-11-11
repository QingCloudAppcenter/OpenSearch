prepairPathOnPersistentDisk() {
    mkdir -p /data/opensearch/{data,logs}
    chown -R opensearch:svc /data/opensearch
}

dispatch() {
    if ! isClusterInitialized; then
        log "new node created! prepaire paths on persistent disk"
        prepairPathOnPersistentDisk
        return
    fi
    if [ "${ADDING_HOSTS_FLAG}" = "true" ] || [ "DELETING_HOSTS_FLAG" = "true" ]; then
        log "adding or deleting nodes"
        return
    fi
    log "normal dispatch check"
}