syncStaticSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
}

syncDynamicSettings() {
    cat $DYNAMIC_SETTINGS_PATH.new > $DYNAMIC_SETTINGS_PATH
}

syncCertSettings() {
    cat $CERT_OS_USER_CA_PATH.new > $CERT_OS_USER_CA_PATH
}

syncAllSettings() {
    syncStaticSettings
    syncDynamicSettings
    syncCertSettings
}

isSettingsChanged() {
    if diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new && diff $DYNAMIC_SETTINGS_PATH $DYNAMIC_SETTINGS_PATH.new && diff $CERT_OS_USER_CA_PATH $CERT_OS_USER_CA_PATH.new; then
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

isCertChanged() {
    if diff $CERT_OS_USER_CA_PATH $CERT_OS_USER_CA_PATH.new; then
        return 1
    else
        return 0
    fi
}

isStaticSettingsChanged() {
    if diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new; then
        return 1
    else
        return 0
    fi
}

processWhenStaticSettingsChanged() {
    if ! isStaticSettingsChanged && ! isCertChanged; then
        return
    fi

    if isCertChanged; then
        syncCertSettings
        if isCertValid $CERT_OS_USER_CA_PATH; then
            log "update user's CA certification"
            cp -f $CERT_OS_USER_CA_PATH $OPENSEARCH_SSL_CA_USER_PATH
        else
            log "remove user's CA certification"
            rm -f $OPENSEARCH_SSL_CA_USER_PATH
        fi
    fi

    if isStaticSettingsChanged; then
        log "sync static settings"
        syncStaticSettings
    fi

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
        log "prepare certs"
        if isCertValid $CERT_OS_USER_CA_PATH; then
            log "update user's CA certification"
            cp -f $CERT_OS_USER_CA_PATH $OPENSEARCH_SSL_CA_USER_PATH
        else
            log "remove user's CA certification"
            rm -f $OPENSEARCH_SSL_CA_USER_PATH
        fi
        return
    fi

    if ! isSettingsChanged; then
        log "settings are not changed, skipping!"
        return
    fi

    processWhenDynamicSettingsChanged

    processWhenStaticSettingsChanged
}