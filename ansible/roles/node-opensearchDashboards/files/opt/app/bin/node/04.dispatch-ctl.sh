syncStaticSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
}

syncDynamicSettings() {
    cat $DYNAMIC_SETTINGS_PATH.new > $DYNAMIC_SETTINGS_PATH
}

syncAllSettings() {
    syncStaticSettings
    syncDynamicSettings
}

isSettingsChanged() {
    if diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new && diff $DYNAMIC_SETTINGS_PATH $DYNAMIC_SETTINGS_PATH.new; then
        return 1
    else
        return 0
    fi
}

processWhenDynamicSettingsChanged() {
    local info
    if info=$(diff $DYNAMIC_SETTINGS_PATH $DYNAMIC_SETTINGS_PATH.new); then
        return
    fi

    log "sync dynamic settings"
    syncDynamicSettings

    log "apply changed dynamic settings"
    refreshAllDynamicServiceStatus
}

processWhenStaticSettingsChanged() {
    local info
    if info=$(diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new); then
        return
    fi

    log "sync static settings"
    syncStaticSettings

    # refresh config file
    log "refresh dashboards config"
    refreshDashboardsConf

    log "restart opensearch-dashboards.service"
    systemctl restart opensearch-dashboards
}

dispatch() {
    if ! isClusterInitialized; then
        log "first boot up, sync settings"
        syncAllSettings
        return
    fi

    if ! isSettingsChanged; then
        log "settings are not changed, skipping!"
        return
    fi

    processWhenDynamicSettingsChanged

    processWhenStaticSettingsChanged
}