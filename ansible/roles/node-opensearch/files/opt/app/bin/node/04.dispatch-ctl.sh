prepairPathOnPersistentDisk() {
    mkdir -p /data/opensearch/{data,logs,dump}
    chown -R opensearch:svc /data/opensearch
}

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

processWhenStaticSettingsChanged() {
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
    log "do something"
}

dispatch() {
    if ! isClusterInitialized; then
        log "new node created! prepair paths on persistent disk"
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
    
    processWhenDynamicSettingsChanged

    processWhenStaticSettingsChanged
}