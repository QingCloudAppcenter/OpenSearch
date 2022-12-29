preparePathOnPersistentDisk() {
    mkdir -p /data/opensearch/{data,logs,dump,analysis}
    chown -R opensearch:svc /data/opensearch
}

syncStaticSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
}

syncDynamicSettings() {
    cat $DYNAMIC_SETTINGS_PATH.new > $DYNAMIC_SETTINGS_PATH
}

syncKeystoreSettings() {
    cat $KEYSTORE_SETTINGS_PATH.new > $KEYSTORE_SETTINGS_PATH
}

syncCertSettings() {
    cat $CERT_OS_USER_CA_PATH.new > $CERT_OS_USER_CA_PATH
    cat $CERT_OS_USER_NODE_CERT_PATH.new > $CERT_OS_USER_NODE_CERT_PATH
    cat $CERT_OS_USER_NODE_KEY_PATH.new > $CERT_OS_USER_NODE_KEY_PATH
}

syncAllSettings() {
    syncStaticSettings
    syncDynamicSettings
    syncKeystoreSettings
    syncCertSettings
}

isSettingsChanged() {
    if diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new && diff $DYNAMIC_SETTINGS_PATH $DYNAMIC_SETTINGS_PATH.new && diff $KEYSTORE_SETTINGS_PATH $KEYSTORE_SETTINGS_PATH.new && diff $CERT_OS_USER_CA_PATH $CERT_OS_USER_CA_PATH.new && diff $CERT_OS_USER_NODE_CERT_PATH $CERT_OS_USER_NODE_CERT_PATH.new && diff $CERT_OS_USER_NODE_KEY_PATH $CERT_OS_USER_NODE_KEY_PATH.new; then
        return 1
    else
        return 0
    fi
}

isCertChanged() {
    if diff $CERT_OS_USER_CA_PATH $CERT_OS_USER_CA_PATH.new && diff $CERT_OS_USER_NODE_CERT_PATH $CERT_OS_USER_NODE_CERT_PATH.new && diff $CERT_OS_USER_NODE_KEY_PATH $CERT_OS_USER_NODE_KEY_PATH.new; then
        return 1
    else
        return 0
    fi
}

processWhenStaticSettingsChanged() {
    if isCertChanged; then
        log "sync user cert settings"
        syncCertSettings
        log "update user cert files"
        refreshAllCerts
    fi

    local info
    if info=$(diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new); then
        return
    fi

    # file changed flag
    # o: opensearch.yml
    # j: jvm.option
    # l: log4j2.properties
    local flag

    local tmpcnt
    tmpcnt=$(echo "$info" | sed -n '/static.os/p' | wc -l)
    if [ "$tmpcnt" -gt 0 ]; then
        flag="o"
    fi
    tmpcnt=$(echo "$info" | sed -n '/static.jvm/p' | wc -l)
    if [ "$tmpcnt" -gt 0 ]; then
        flag="j$flag"
    fi
    tmpcnt=$(echo "$info" | sed -n '/static.log4j/p' | wc -l)
    if [ "$tmpcnt" -gt 0 ]; then
        flag="l$flag"
    fi
    tmpcnt=$(echo "$info" | sed -n '/static.ik/p' | wc -l)
    if [ "$tmpcnt" -gt 0 ]; then
        flag="i$flag"
    fi

    log "sync static settings"
    syncStaticSettings

    # refresh config file
    local res
    res=$(echo "$flag" | sed -n '/o/p')
    if [ -n "$res" ]; then
        log "opensearch static config changed, refresh opensearch.yml"
        refreshOpenSearchConf
    fi

    res=$(echo "$flag" | sed -n '/j/p')
    if [ -n "$res" ]; then
        log "opensearch static config changed, refresh jvm.options"
        refreshJvmOptions
    fi

    res=$(echo "$flag" | sed -n '/l/p')
    if [ -n "$res" ]; then
        log "opensearch static config changed, refresh log4j2.properties"
        refreshLog4j2Properties
    fi

    res=$(echo "$flag" | sed -n '/i/p')
    if [ -n "$res" ]; then
        log "opensearch static config changed, refresh IKAnalyzer.cfg.xml"
        refreshIKAnalyzerCfgXml
    fi

    log "restart opensearch.service"
    systemctl restart opensearch
}

processWhenDynamicSettingsChanged() {
    local info
    if info=$(diff $DYNAMIC_SETTINGS_PATH $DYNAMIC_SETTINGS_PATH.new); then
        return
    fi

    log "sync dynamic settings"
    syncDynamicSettings

    log "refresh changed dynamic service"
    refreshChangedDynamicService "$info"

    if ! isFirstMaster; then
        return
    fi

    # wait 30s for cluster ready
    if ! retry 6 5 0 isLocalServiceAvailable; then
        log "timeout waiting for cluster available"
        return $EC_DYNAMIC_SETTINGS_TIMEOUT
    fi

    log "apply changed dynamic settings"
    applyChangedDynamicSettings "$info"
}

processWhenKeystoreSettingsChanged() {
    local info
    if info=$(diff $KEYSTORE_SETTINGS_PATH $KEYSTORE_SETTINGS_PATH.new); then
        return
    fi

    log "sync keystore settings"
    syncKeystoreSettings

    log "apply changed keystore settings"
    applyChangedKeystoreSettings "$info"
}

dispatch() {
    if ! isClusterInitialized; then
        log "new node created! prepare paths on persistent disk"
        preparePathOnPersistentDisk
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

    processWhenKeystoreSettingsChanged
    
    processWhenDynamicSettingsChanged

    processWhenStaticSettingsChanged
}