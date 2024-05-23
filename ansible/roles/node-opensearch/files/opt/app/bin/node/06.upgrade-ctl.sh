# path
OPENSEARCH_SEC_BACKUP_PATH=/data/appctl/data/sec_backup
OPENSEARCH_CONF_SYS_CERTS_PATH=/opt/app/current/conf/opensearch/certs/qc
CADDY_OLD_FILE=/data/opensearch/index.html

modifySecurityFile() {
    fn=$OPENSEARCH_SEC_BACKUP_PATH/internal_users.yml
    adminLine=$(awk '/^admin/{print NR; exit}' $fn)
    reservedLine=$(awk -v n=$adminLine 'NR>n && /reserved/{print NR; exit}' $fn)
    sed -i "${reservedLine}s/.*/  reserved: false/" $fn
}

upgrade() {
    log "sync static settings"
    syncStaticSettings
    if ! isLastMaster; then
        log "not the last master, skipping"
        return 0
    fi
    log "repair amdin auth"
    repairAdminAuth
}

repairAdminAuth() {
    log "prepare backup folder"
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
}