preparePathOnPersistentDisk() {
    mkdir -p /data/opensearch/dicts /data/logstash/{config,data,dump,logs,plugins}
    chown -R logstash.svc /data/logstash
    chown -R caddy.svc /data/opensearch
    touch $PIPELINE_CONFIG_PATH
    chown ubuntu:svc $PIPELINE_CONFIG_PATH
}

fakeInitCluster() {
    touch $APPCTL_CLUSTER_FILE
}

syncStaticSettings() {
    cat $STATIC_SETTINGS_PATH.new > $STATIC_SETTINGS_PATH
}

syncDynamicSettings() {
    cat $DYNAMIC_SETTINGS_PATH.new > $DYNAMIC_SETTINGS_PATH
}

syncDependSettings() {
    cat $DEPEND_SETTINGS_PATH.new > $DEPEND_SETTINGS_PATH
}

syncCertSettings() {
    cat $CERT_OS_USER_CA_PATH.new > $CERT_OS_USER_CA_PATH
}

syncAllSettings() {
    syncStaticSettings
    syncDynamicSettings
    syncDependSettings
    syncCertSettings
}

isSettingsChanged() {
    if diff $STATIC_SETTINGS_PATH $STATIC_SETTINGS_PATH.new && diff $DYNAMIC_SETTINGS_PATH $DYNAMIC_SETTINGS_PATH.new && $DEPEND_SETTINGS_PATH $DEPEND_SETTINGS_PATH.new && diff $CERT_OS_USER_CA_PATH $CERT_OS_USER_CA_PATH.new; then
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

isDependSettingsChanged() {
    if diff $DEPEND_SETTINGS_PATH $DEPEND_SETTINGS_PATH.new; then
        return 1
    else
        return 0
    fi
}

processWhenStaticSettingsChanged() {
    if ! isStaticSettingsChanged && ! isCertChanged && ! isDependSettingsChanged; then
        return
    fi

    local certflag="false"
    if isCertChanged; then
        certflag="true"
        log "sync cert settings"
        syncCertSettings
        if isCertValid $CERT_OS_USER_CA_PATH; then
            log "update user's CA certification"
            cp -f $CERT_OS_USER_CA_PATH $OPENSEARCH_SSL_CA_USER_PATH
        else
            log "remove user's CA certification"
            rm -f $OPENSEARCH_SSL_CA_USER_PATH
        fi
    fi

    local dependflag="false"
    if isDependSettingsChanged || [ "$certflag" = "true" ]; then
        dependflag="true"
        log "sync depend settings"
        syncDependSettings
        log "refresh demo pipeline config"
        refreshDemoPipeline
        log "refresh pipeline config"
        refreshPipeline
    fi

    local staticflag="false"
    if isStaticSettingsChanged; then
        staticflag="true"
        log "sync static settings"
        syncStaticSettings
        log "refresh logstash.yml"
        refreshLogstashYml
    fi

    if [ "$staticflag" = "true" ]; then
        log "restart logstash.service, reason: static"
        systemctl restart logstash
        return
    fi

    if [ "$dependflag" = "true" ] && ! isReloadAutomatic; then
        log "restart logstash.service, reason: pipeline"
        systemctl restart logstash
        return
    fi
}

dispatch() {
    if [ "$UPGRADING_FLAG" = "true" ]; then
        log "upgrading cluster, skipping!"
        return
    fi
    if ! isClusterInitialized; then
        log "new node created! prepare paths on persistent disk"
        preparePathOnPersistentDisk
        log "sync all settings"
        syncAllSettings
        log "prepare certs"
        if isCertValid $CERT_OS_USER_CA_PATH; then
            log "update user's CA certification"
            cp -f $CERT_OS_USER_CA_PATH $OPENSEARCH_SSL_CA_USER_PATH
        else
            log "remove user's CA certification"
            rm -f $OPENSEARCH_SSL_CA_USER_PATH
        fi
        log "fake init cluster"
        fakeInitCluster
        retrun
    fi

    if ! isSettingsChanged; then
        log "settings are not changed, skipping!"
        return
    fi

    processWhenDynamicSettingsChanged

    processWhenStaticSettingsChanged
}