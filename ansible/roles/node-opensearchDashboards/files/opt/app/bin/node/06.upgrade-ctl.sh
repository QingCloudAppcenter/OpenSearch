upgrade() {
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
}