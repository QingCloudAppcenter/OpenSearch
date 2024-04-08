prepareDirs() {
  mkdir -p /data/opensearch/dicts /data/logstash/{config,data,dump,logs,plugins,queue}
  local lsTmplFile=/data/opensearch/dicts/logstash.json

  # https://github.com/logstash-plugins/logstash-output-elasticsearch/blob/v10.3.1/lib/logstash/outputs/elasticsearch
  [ -e "$lsTmplFile" ] || cp /opt/app/conf/logstash/template.json $lsTmplFile

  chown -R logstash.svc /data/{opensearch,logstash}
  find /data/opensearch/dicts -type f -exec chmod +r {} \;
  chown -R ubuntu.svc /data/logstash/{config,plugins}
}

initNode() {
  _initNode
  prepareDirs
  local htmlPath=/data/opensearch/index.html
  [ -e $htmlPath ] || ln -s /opt/app/conf/caddy/index.html $htmlPath
}

testConf() {
  . /opt/app/conf/logstash/.env
  $LS_HOME/bin/logstash --path.settings $LS_SETTINGS_DIR -t
}

upgrade() {
  timeout 6h appctl retry 1000 30 0 testConf || log "WARN: detected configuration failures and no human involved."
}

# $1 service name
refreshDynamicService() {
    if [ ! -e $DYNAMIC_SETTINGS_PATH ]; then
        log "cluster is booting up, do nothing!"
        return
    fi
    local settings=$(cat $DYNAMIC_SETTINGS_PATH)
    local curstatus
    case "$1" in
        "caddy")
        curstatus=$(getItemFromConf "$settings" "dynamic.other.enable_caddy")
        ;;
        "cerebro")
        curstatus=$(getItemFromConf "$settings" "dynamic.other.enable_cerebro")
        ;;
        *)
        curstatus=""
        ;;
    esac
    if [ -z "$curstatus" ]; then
        log "unknown service, skipping!"
        return
    fi
    if [ "$curstatus" = "true" ]; then
        log "restart service: $1"
        systemctl restart $1 || :
    else
        log "the $1 service is disabled, do nothing!"
    fi
}
