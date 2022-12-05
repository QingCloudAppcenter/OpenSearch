DASHBOARDS_CONF_PATH=/opt/app/current/conf/opensearch-dashboards/opensearch_dashboards.yml
STATIC_SETTINGS_PATH=/data/appctl/data/settings.static
OSD_PID_PATH=/data/opensearch-dashboards/data/opensearchDashboards.pid
OPENSEARCH_SSL_CA_SYS_PATH=/opt/app/current/conf/opensearch-dashboards/certs/qc/root-ca.pem
OPENSEARCH_SSL_CA_USER_PATH=/opt/app/current/conf/opensearch-dashboards/certs/user/root-ca.pem

prepareFolders() {
  local svc; for svc in $(getServices -a); do
    local svcName=${svc%%/*}
    mkdir -p /data/$svcName/{data,logs}
    local svcUser=$svcName
    if [[ "$svcName" =~ ^haproxy|keepalived$ ]]; then svcUser=syslog; fi
    chown -R $svcUser.svc /data/$svcName

    if [ "$svcName" = "caddy" ] || [ "$svcName" = "cerebro" ]; then continue; fi
    if [ ! -f /data/$svcName/index.html ]; then touch /data/$svcName/index.html; fi
    cat > /data/$svcName/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
<title>redirect</title>
<meta http-equiv="Refresh" content="0; url=/$svcName/logs">
</head>
<body>
</body>
</html>
EOF
  done
}

# $1 confing string
# $2 key
getItemFromConf() {
    local res=$(echo "$1" | sed '/^'$2'=/!d;s/^'$2'=//')
    echo "$res"
}

refreshDashboardsConf() {
    local settings=$(cat $STATIC_SETTINGS_PATH)
    local sslHttpEnabled=$(getItemFromConf "$settings" "static.os.ssl.http.enabled")
    local proto=http
    local sslver=none
    if [ "$sslHttpEnabled" = "true" ]; then
        proto=https
        sslver=certificate
    fi

    local cas="\"$OPENSEARCH_SSL_CA_SYS_PATH\""
    if [ -e "$OPENSEARCH_SSL_CA_USER_PATH" ]; then
        cas="\"$OPENSEARCH_SSL_CA_SYS_PATH\", \"$OPENSEARCH_SSL_CA_USER_PATH\""
    fi

    local cfg=$(cat <<OSD_CONF
server.host: $MY_IP
opensearch.hosts: [$proto://$OS_VIP:9200]
opensearch.ssl.verificationMode: $sslver
opensearch.ssl.certificateAuthorities: [ $cas ]
opensearch.username: $SYS_USER
opensearch.password: $SYS_USER_PWD
opensearch.requestHeadersWhitelist: [authorization, securitytenant]

opensearch_security.multitenancy.enabled: true
opensearch_security.multitenancy.tenants.preferred: [Private, Global]
opensearch_security.readonly_mode.roles: [kibana_read_only]
# Use this setting if you are running opensearch-dashboards without https
opensearch_security.cookie.secure: $sslHttpEnabled

path.data: /data/opensearch-dashboards/data
pid.file: $OSD_PID_PATH
OSD_CONF
)
    echo "$cfg" > $DASHBOARDS_CONF_PATH
}