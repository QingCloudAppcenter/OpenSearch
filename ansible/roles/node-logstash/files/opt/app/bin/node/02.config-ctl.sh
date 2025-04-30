STATIC_SETTINGS_PATH=/data/appctl/data/settings.static
DYNAMIC_SETTINGS_PATH=/data/appctl/data/settings.dynamic
DEPEND_SETTINGS_PATH=/data/appctl/data/settings.depend
LOGSTASH_YML_PATH=/opt/app/current/conf/logstash/logstash.yml
LOGSTASH_CONF_PATH=/opt/app/current/conf/logstash
JVM_OPTIONS_PATH=/opt/app/current/conf/logstash/jvm.options
PIPELINE_CONFIG_PATH=/data/logstash/config/logstash.conf
PIPELINE_DEMO_CONFIG_PATH=/data/logstash/config/logstash-demo.conf
KEYSTORE_PATH=/opt/app/current/conf/logstash/logstash.keystore
KEYSTORE_TOOL_PATH=/opt/logstash/current/bin/logstash-keystore
CERT_OS_USER_CA_PATH=/data/appctl/data/cert.os.user_ca
OPENSEARCH_SSL_CA_SYS_PATH=/opt/app/current/conf/logstash/certs/qc/root-ca.pem
OPENSEARCH_SSL_CA_USER_PATH=/opt/app/current/conf/logstash/certs/user/root-ca.pem
# $1 confing string
# $2 key
getItemFromConf() {
    local res=$(echo "$1" | sed '/^'$2'=/!d;s/^'$2'=//')
    echo "$res"
}

isReloadAutomatic() {
    local settings=$(cat $STATIC_SETTINGS_PATH)
    local configReloadAutomatic=$(getItemFromConf "$settings" "static.lst.config.reload.automatic")
    if [ "$configReloadAutomatic" = "true" ]; then
        return 0
    else
        return 1
    fi
}

refreshLogstashYml() {
    local settings=$(cat $STATIC_SETTINGS_PATH)
    local configReloadAutomatic=$(getItemFromConf "$settings" "static.lst.config.reload.automatic")
    local configReloadInterval=$(getItemFromConf "$settings" "static.lst.config.reload.interval")
    local cfg=$(cat<<LOGSTASH_YML
config.reload.automatic: $configReloadAutomatic
config.reload.interval: $configReloadInterval

api.http.host: "$MY_IP"

node.name: $MY_NODE_NAME

path.config: /data/logstash/config/logstash.conf
path.data: /data/logstash/data
path.logs: /data/logstash/logs
path.plugins: [ /data/logstash/plugins ]

pipeline.ecs_compatibility: disabled
pipeline.buffer.type: direct
LOGSTASH_YML
    )
    echo "$cfg" > $LOGSTASH_YML_PATH
}

refreshJvmOptions() {
    local maxHeap=$((31*1024))
    local halfMem=$((MY_MEM/2))
    local realHeap
    if [ "$halfMem" -le $maxHeap ]; then
        realHeap=$halfMem
    else
        realHeap=$maxHeap
    fi

    local cfg=$(cat<<JVM_CONF
-Xms${realHeap}m
-Xmx${realHeap}m

11-13:-XX:+UseConcMarkSweepGC
11-13:-XX:CMSInitiatingOccupancyFraction=75
11-13:-XX:+UseCMSInitiatingOccupancyOnly

-Duser.language=zh
-Duser.country=CN
-Duser.variant=

#-Djava.io.tmpdir=$HOME

-Djava.awt.headless=true

-Dfile.encoding=UTF-8

#-Djna.nosys=true

-Djruby.compile.invokedynamic=true

-Djruby.jit.threshold=0

-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/data/logstash/dump/heapdump.hprof

-Xlog:gc*,gc+age=trace,safepoint:file=/data/logstash/logs/gc.log:utctime,pid,tags:filecount=32,filesize=64m

-Djava.security.egd=file:/dev/urandom

-Dlog4j2.isThreadContextMapInheritable=true

-Dlogstash.jackson.stream-read-constraints.max-string-length=200000000
-Dlogstash.jackson.stream-read-constraints.max-number-length=10000
#-Dlogstash.jackson.stream-read-constraints.max-nesting-depth=1000
JVM_CONF
    )
    echo "$cfg" > $JVM_OPTIONS_PATH
}

# store user/pass for logstash to login to opensearch
refreshKeystore() {
    rm -f $KEYSTORE_PATH
    runuser logstash -g svc -s "/bin/bash" -c "echo y | $KEYSTORE_TOOL_PATH --path.settings $LOGSTASH_CONF_PATH create"
    
    runuser logstash -g svc -s "/bin/bash" -c "echo logstash | $KEYSTORE_TOOL_PATH --path.settings $LOGSTASH_CONF_PATH add logstash_user"

    runuser logstash -g svc -s "/bin/bash" -c "echo $LST_USER_PWD | $KEYSTORE_TOOL_PATH --path.settings $LOGSTASH_CONF_PATH add logstash_pass"
}

refreshDemoPipeline() {
    local settings=$(cat $DEPEND_SETTINGS_PATH)
    local osSslHttpEnabled=$(getItemFromConf "$settings" "depend.os.ssl.http.enabled")
    local osUserCaEnabled=$(getItemFromConf "$settings" "depend.os.user_ca_enabled")
    local certstring=""
    if [ "$osUserCaEnabled" = "false" ]; then
        certstring="cacert => \"$OPENSEARCH_SSL_CA_SYS_PATH\""
    elif [ -e $OPENSEARCH_SSL_CA_USER_PATH ]; then
        certstring="cacert => \"$OPENSEARCH_SSL_CA_USER_PATH\""
    fi
    local lstOslist=($(getItemFromConf "$settings" "depend.lst.oslist"))
    local hostlist
    local item
    for item in ${lstOslist[@]}; do
        hostlist="$hostlist\"$item:9200\","
    done
    hostlist=${hostlist:0:-1}

    local cfg=$(cat<<DEMO_PIPELIEN_YML
input {
    http { port => 9090 }
}
filter {

}
output {
    opensearch {
        hosts => [ $hostlist ]
        user => "\${logstash_user}"
        password => "\${logstash_pass}"
        ssl_certificate_verification => false
        ssl => $osSslHttpEnabled
        $certstring
    }
}
DEMO_PIPELIEN_YML
    )
    echo "$cfg" > $PIPELINE_DEMO_CONFIG_PATH
}

refreshPipeline() {
    local settings=$(cat $DEPEND_SETTINGS_PATH)
    local lstPipeline=$(echo $(getItemFromConf "$settings" "depend.lst.pipeline"))
    local realconfig
    if [ -z "$lstPipeline" ]; then
        realconfig=$(cat $PIPELINE_DEMO_CONFIG_PATH)
    else
        realconfig="$lstPipeline"
    fi

    local cfg=$(cat<<PIPELIEN_YML
$realconfig
PIPELIEN_YML
    )
    echo "$cfg" > $PIPELINE_CONFIG_PATH
}

# $1 - cert path
isCertValid() {
    openssl x509 -in $1 -text -noout
}

refreshAllDynamicServiceStatus() {
    local settings=$(cat $DYNAMIC_SETTINGS_PATH)
    local enable_caddy=$(getItemFromConf "$settings" "dynamic.other.enable_caddy")
    if [ "$enable_caddy" = "true" ]; then
        systemctl start caddy
    else
        systemctl stop caddy
    fi
}

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

showTabForDemoPipelineConfig() {
    local cfg=$(cat<<TAB_INFO
{
    "labels": ["$PIPELINE_DEMO_CONFIG_PATH"],
    "data":[
        [$(jq -Rs . $PIPELINE_DEMO_CONFIG_PATH)]
    ]
}
TAB_INFO
)
    echo "$cfg"
}