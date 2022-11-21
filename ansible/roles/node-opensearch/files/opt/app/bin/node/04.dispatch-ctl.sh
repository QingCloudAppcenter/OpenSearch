prepairPathOnPersistentDisk() {
    mkdir -p /data/opensearch/{data,logs}
    chown -R opensearch:svc /data/opensearch
}

syncAllSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
}

isSettingsChanged() {
    # static settings and dynamic settings
    if diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new; then
        return 1
    else
        return 0
    fi
}

dispatch() {
    if ! isClusterInitialized; then
        log "new node created! prepaire paths on persistent disk"
        prepairPathOnPersistentDisk
        log "sync all settings"
        syncAllSettings
        return
    fi
    if [ "$ADDING_HOSTS_FLAG" = "true" ] || [ "$DELETING_HOSTS_FLAG" = "true" ]; then
        log "adding or deleting nodes"
        return
    fi
    # during adding or deleting, some changes will come here
    # if other setting files were not changed, it's still in adding or deleting state
    if ! isSettingsChanged; then
        log "settings are not changed, skipping!"
        return
    fi
    
    log "normal dispatch"
}