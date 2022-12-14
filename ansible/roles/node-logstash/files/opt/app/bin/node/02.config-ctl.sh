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

# $1 confing string
# $2 key
getItemFromConf() {
    local res=$(echo "$1" | sed '/^'$2'=/!d;s/^'$2'=//')
    echo "$res"
}

refreshLogstashYml() {
    local settings=$(cat $STATIC_SETTINGS_PATH)
    local configReloadAutomatic=$(getItemFromConf "$settings" "static.lst.config.reload.automatic")
    local configReloadInterval=$(getItemFromConf "$settings" "static.lst.config.reload.interval")
    local cfg=$(cat<<LOGSTASH_YML
config.reload.automatic: $configReloadAutomatic
config.reload.interval: $configReloadInterval

http.host: "$MY_IP"

node.name: $MY_NODE_NAME

path.config: /data/logstash/config/logstash.conf
path.data: /data/logstash/data
path.logs: /data/logstash/logs
path.plugins: [ /data/logstash/plugins ]

pipeline.ecs_compatibility: disabled
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
JVM_CONF
    )
    echo "$cfg" > $JVM_OPTIONS_PATH
}

# store user/pass for logstash to login to opensearch
refreshKeystore() {
    rm -f $KEYSTORE_PATH
    runuser logstash -g svc -s "/bin/bash" -c "echo y | $KEYSTORE_TOOL_PATH --path.settings $LOGSTASH_CONF_PATH create"
    
    runuser logstash -g svc -s "/bin/bash" -c "echo $SYS_USER | $KEYSTORE_TOOL_PATH --path.settings $LOGSTASH_CONF_PATH add logstash_user"

    runuser logstash -g svc -s "/bin/bash" -c "echo $SYS_USER_PWD | $KEYSTORE_TOOL_PATH --path.settings $LOGSTASH_CONF_PATH add logstash_pass"
}

refreshDemoPipeline() {
    local settings=$(cat $DEPEND_SETTINGS_PATH)
    local osSslHttpEnabled=$(getItemFromConf "$settings" "depend.os.ssl.http.enabled")
    local proto=http
    if [ "$osSslHttpEnabled" = "true" ]; then
        proto=https
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
    http { port => 9700 }
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
        cacert => "/opt/app/current/conf/logstash/certs/qc/root-ca.pem"
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