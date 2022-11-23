prepairPathOnPersistentDisk() {
    mkdir -p /data/opensearch/{data,logs,dump}
    chown -R opensearch:svc /data/opensearch
}

syncStaticSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
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

processWhenStaticSettingsChanged() {
    local info
    if info=$(diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new); then
        return
    fi

    local tmpcnt
    tmpcnt=$(echo "$info" | grep static.os | wc -l)
    # file changed flag
    # o: opensearch.yml
    # j: jvm.option
    local flag
    if [ "$tmpcnt" -gt 0 ]; then
        flag="o" 
    fi
    tmpcnt=$(echo "$info" | grep static.jvm | wc -l)
    if [ "$tmpcnt" -gt 0 ]; then
        flag="j" 
    fi

    log "sync static settings"
    syncStaticSettings

    # refresh config file
    if echo "$flag" | grep o; then
        log "opensearch static config changed, refresh opensearch.yml"
        refreshOpenSearchConf
    fi

    if echo "$flag" | grep j; then
        log "opensearch static config changed, refresh jvm.options"
        refreshJvmOptions
    fi

    log "restart opensearch.service"
    systemctl restart opensearch
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
    
    processWhenStaticSettingsChanged
}