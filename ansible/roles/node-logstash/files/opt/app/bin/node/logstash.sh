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
