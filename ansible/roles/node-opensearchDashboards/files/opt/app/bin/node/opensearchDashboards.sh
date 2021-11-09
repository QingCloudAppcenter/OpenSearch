prepareDirs() {
  local svc; for svc in $(getServices -a); do
    local svcName=${svc%%/*}
    mkdir -p /data/$svcName/{data,logs}
    local svcUser=$svcName
    if [[ "$svcName" =~ ^haproxy|keepalived$ ]]; then svcUser=syslog; fi
    chown -R $svcUser.svc /data/$svcName
  done
  mkdir -p /var/run/dashboards
  chown -R dashboards.svc /var/run/dashboards
}

initNode() {
  _initNode
  prepareDirs
  ln -sf /opt/app/conf/caddy/index.html /data/index.html
}

start() {
  [ "$MY_IP" = "${KIBANA_NODES%% *}" ] || retry 60 1 0 checkDashboardsIndexCreated || log "WARN: index still not created."
  _start
}

checkDashboardsIndexCreated() {
  test -n "$(curl -s -m3 "$ES_VIP:9200/_cat/indices/.opensearchDashboards-7_8?h=i -u ${MY_ADMIN_USER}:${MY_ADMIN_PASSWORD}")"
}

checkSvc() {
  _checkSvc $@ || return $?
  if [ "$1" == "opensearchDashboards" ]; then
    #checkEndpoint http:9200 $ES_VIP;
    code="$(curl -s -m5 -o /dev/null -w "%{http_code}" $ES_VIP:9200 -u ${MY_ADMIN_USER}:${MY_ADMIN_PASSWORD})" || {
      log "From opensearchDashboards ERROR: HTTP $code - failed to check http://$ES_VIP:9200 ($?)."
      return 204
    }
    [[ "$code" =~ ^(200|302|401|403|404)$ ]] || {
      log "From opensearchDashboards ERROR: unexpected HTTP code $code."
      return 205
    }
  fi
}
