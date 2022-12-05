syncStaticSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
}

syncAllSettings() {
    syncStaticSettings
}

dispatch() {
    if ! isClusterInitialized; then
        log "first boot up, sync settings"
        syncAllSettings
        return
    fi
    log "normal dispatch"
}