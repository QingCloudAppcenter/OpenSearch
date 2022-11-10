prepairPathOnPersistentDisk() {
    mkdir -p /data/opensearch/data
    mkdir -p /data/opensearch/logs
    chown -R opensearch:svc /data/opensearch
}

dispatch() {
    if ! isClusterInitialized; then
        log "new node created! prepaire paths on persistent disk"
        prepairPathOnPersistentDisk
        return
    fi
    
    log "normal dispatch check"
}