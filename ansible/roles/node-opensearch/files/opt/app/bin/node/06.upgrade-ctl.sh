# path
OPENSEARCH_SEC_BACKUP_PATH=/data/appctl/data/sec_backup
OPENSEARCH_CONF_SYS_CERTS_PATH=/opt/app/current/conf/opensearch/certs/qc
CADDY_OLD_FILE=/data/opensearch/index.html

modifySecurityFile() {
    local syshash=$(calcSecretHash $SYS_USER_PWD)
    local osdhash=$(calcSecretHash $OSD_USER_PWD)
    local lsthash=$(calcSecretHash $LST_USER_PWD)
    local cfg=$(cat<<INTERNAL_USER
# managed by appctl, do not modify
$SYS_USER:
  hash: "$syshash"
  reserved: true
  hidden: true
  backend_roles:
  - "admin"
  description: "internal user: $SYS_USER"

logstash:
  hash: "$lsthash"
  reserved: false
  backend_roles:
  - "logstash"
  description: "Demo logstash user, using external role mapping"

kibanaserver:
  hash: "$osdhash"
  reserved: true
  description: "Demo OpenSearch Dashboards user"
INTERNAL_USER
)

    echo "$cfg" >> $OPENSEARCH_SEC_BACKUP_PATH/internal_users.yml
}

upgrade() {
    log "remove $CADDY_OLD_FILE"
    rm -f $CADDY_OLD_FILE

    log "sync all settings"
    syncAllSettings

    log "prepare config files"
    refreshAllCerts
    refreshOpenSearchConf
    refreshJvmOptions
    refreshLog4j2Properties
    refreshIKAnalyzerCfgXml

    log "appctl init"
    _init

    log "modify folder permission"
    chown -R opensearch:svc /data/opensearch/{data,logs}
    
    log "start opensearch.service"
    systemctl start opensearch

    if ! isFirstMaster; then return 0; fi

    log "prepare upgrade folder"
    mkdir -p $OPENSEARCH_SEC_BACKUP_PATH

    log "backup security settings"
    local admin_tool=$SECURITY_TOOL_PATH/securityadmin.sh
    chmod +x $admin_tool
    if ! JAVA_HOME=$JAVA_HOME $admin_tool -backup $OPENSEARCH_SEC_BACKUP_PATH -icl -nhnv -cacert $OPENSEARCH_CONF_SYS_CERTS_PATH/root-ca.pem -cert $OPENSEARCH_CONF_SYS_CERTS_PATH/admin.pem -key $OPENSEARCH_CONF_SYS_CERTS_PATH/admin-key.pem -h $MY_IP; then
        log "backup old security info failed!"
        return $EC_SEC_BACKUP_FAILED
    fi

    log "modify security file"
    modifySecurityFile

    log "update security settings"
    if ! JAVA_HOME=$JAVA_HOME $admin_tool -f $OPENSEARCH_SEC_BACKUP_PATH/internal_users.yml -t internalusers -icl -nhnv -cacert $OPENSEARCH_CONF_SYS_CERTS_PATH/root-ca.pem -cert $OPENSEARCH_CONF_SYS_CERTS_PATH/admin.pem -key $OPENSEARCH_CONF_SYS_CERTS_PATH/admin-key.pem -h $MY_IP >>$OPENSEARCH_SEC_BACKUP_PATH/debug.log 2>&1; then
        log "write back new password failed!"
        return $EC_SEC_WRITEBACK_FAILED
    fi

    log "apply all dynamic settings"
    applyAllDynamicSettings
}