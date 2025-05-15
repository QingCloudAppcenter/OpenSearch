isLocalServiceAvailable() {
    local res=$(getClusterDesc)
    local clname=$(echo "$res" | jq -r '.cluster_name')
    test "$clname" = "$CLUSTER_ID"
}

start() {
    if ! isNodeInitialized; then
        log "prepare keystore"
        applyAllKeystoreSettings
        log "prepare config files"
        refreshAllCerts
        refreshOpenSearchConf
        refreshJvmOptions
        refreshLog4j2Properties
        refreshIKAnalyzerCfgXml
        log "appctl node init"
        _initNode
    fi
    if [ $VERTICAL_SCALING_FLAG = "true" ]; then
        log "refresh jvm.options when vertical scaling"
        refreshJvmOptions
    fi
    if [ $UPGRADING_FLAG = "true" ]; then
        log "detect upgrading!"
        log "prepare upload templates"
        ln -s /opt/app/current/conf/caddy/templates/ /data/opensearch/templates
        log "fix some folder issues"
        mkdir -p /data/caddy
        chown caddy:svc /data/caddy
        chown -R opensearch:svc /data/opensearch
    fi
    log "start opensearch.service"
    systemctl start opensearch
    log "enable health check"
    enableHealthCheck
    log "refresh all dynamic service status"
    refreshAllDynamicServiceStatus
    log "modify folder analysis permission"
    chmod 775 /data/opensearch/analysis
}

isFirstMaster() {
    test ! "$IS_MASTER" = "false"
    local tmplist=($STABLE_MASTER_NODES)
    test "${tmplist[0]}" = "$MY_IP"
}

isLastMaster() {
    test ! "$IS_MASTER" = "false"
    local tmplist=($STABLE_MASTER_NODES)
    test "${tmplist[@]: -1}" = "$MY_IP"
}

init() {
    if ! isClusterInitialized; then
        log "prepare upload templates"
        ln -s /opt/app/current/conf/caddy/templates/ /data/opensearch/templates
        log "prepare keystore"
        applyAllKeystoreSettings
        log "prepare caddy folder"
        mkdir -p /data/caddy
        chown caddy:svc /data/caddy
        log "prepare config files"
        refreshAllCerts
        refreshOpenSearchConf
        refreshJvmOptions
        refreshLog4j2Properties
        refreshIKAnalyzerCfgXml
        log "_init"
        _init
    fi

    if [ "$ADDING_HOSTS_FLAG" = "true" ]; then
        log "adding nodes, skipping!"
        return
    fi

    log "inject internal users"
    injectInternalUsers

    log "set admin pass"
    setAdminPass

    if isFirstMaster; then
        log "inject cluster init config in opensearch.yml"
        injectClusterInitConf
    fi

    log "start opensearch.service"
    systemctl start opensearch

    log "wait until local service is ok"
    while ! isLocalServiceAvailable; do
        sleep 5s
    done
    
    log "restore internal users"
    restoreInternalUsers

    if isFirstMaster; then
        log "restore opensearch.yml"
        restoreOpenSearchConf
        log "apply all dynamic settings"
        applyAllDynamicSettings
    fi
}

stop() {
    log "disable health check"
    disableHealthCheck
    log "stop opensearch.service"
    systemctl stop opensearch
}

isMasterExcluded() {
    local clusterco
    if ! clusterco=$(getClusterCoordination); then
        log "failed getting cluster coordination"
        return 1
    fi
    local wanted=$(getNodesIdFromNodesName $@)
    local commited=$(echo "$clusterco" | jq -r '.metadata.cluster_coordination.last_committed_config[]' | xargs)
    local item
    local cnt
    for item in $wanted; do
        cnt=$(echo "$commited" | sed -n "/$item/p" | wc -l)
        if [ "$cnt" -gt 0 ]; then return 1; fi
    done
}

getNodesIdFromNodesName() {
    local mixlist
    local res=""
    if ! mixlist=$(getAllNodesId | awk '{print $1"/"$3}'); then
        echo ""
        return
    fi
    local item
    local tmp
    for item in $@; do
        tmp=$(echo "$mixlist" | sed -n "/^$item/p")
        res="$res ${tmp#*/}"
    done
    echo $res
}

processBeforeScaleInMasterNodes() {
    if ! excludeMasterNodes "${LEAVING_MASTER_NODES_HOSTS// /,}"; then
        log "failed excluding master nodes"
        clearMasterExclude
        return $EC_SCALEIN_FAILED_EXCLUDE_MASTER
    fi

    if ! retry 120 5 0 isMasterExcluded "$LEAVING_MASTER_NODES_HOSTS"; then
        log "timeout waiting for excluding master nodes"
        clearMasterExclude
        return $EC_SCALEIN_WAITING_EXCLUDE_MASTER
    fi
}

hasUnusualIndices() {
    local info=$(getIndicesStatusDocsCount $@)
    local closedcnt=$(echo "$info" | sed -n '/close/p' | wc -l)
    if [ "$closedcnt" -gt 0 ]; then
        log "has closed indices"
        return
    fi
    # local nodocscnt=$(echo "$info" | awk '/^open/{if($2==0) {print "got it!";exit}}' | wc -l)
    # if [ "$nodocscnt" -gt 0 ]; then
    #     log "has indices with 0 docs"
    #     return
    # fi
    return 1
}

isClusterStableWithShards() {
    local info=$(getClusterHealthInfo $@)
    local status=$(echo "$info" | jq -r '.status')
    local relocating=$(echo "$info" | jq '.relocating_shards')
    [ "$status" = "green" ] && [ "$relocating" -eq 0 ]
}

isDataExcluded() {
    local info=$(getNodesDocsCountInfo $@)
    local doccount=$(echo "$info" | jq '.nodes | to_entries | map(.value.indices.docs.count) | add')
    test "$doccount" -eq 0
}

processBeforeScaleInDataNodes() {
    if hasUnusualIndices; then
        log "cluster has closed indices or indices with 0 docs"
        return $EC_SCALEIN_UNUSUAL_INDICES
    fi
    if ! isClusterStableWithShards; then
        log "cluster is not stable with shards, can not scale in data nodes"
        return $EC_SCALEIN_UNSTABLE_SHARDS
    fi
    local res
    if ! res=$(excludeDataNodes "${LEAVING_DATA_NODES// /,}"); then
        log "failed excluding data nodes"
        clearDataExclude
        return $EC_SCALEIN_FAILED_EXCLUDE_DATA
    fi
    local modified=$(echo "$res" | jq -r '.persistent.cluster.routing.allocation.exclude._ip')
    if [ ! "$modified" = "${LEAVING_DATA_NODES// /,}" ]; then
        log "failed excluding data nodes"
        clearDataExclude
        return $EC_SCALEIN_FAILED_EXCLUDE_DATA
    fi
    # wait 2 hour (720*10=7200)
    if ! retry 720 10 0 isDataExcluded "$LEAVING_DATA_NODES"; then
        log "timeout waiting for excluding data nodes"
        clearDataExclude
        return $EC_SCALEIN_WAITING_EXCLUDE_DATA
    fi
}

preScaleInCheck() {
    if [ ! "$IS_MASTER"  = "true" ]; then
        log "only first stable master node does pre-scale-in check"
        return
    fi
    local tmplist=($STABLE_MASTER_NODES)
    if [ ! "${tmplist[0]}" = "$MY_IP" ]; then
        log "only first stable master node does pre-scale-in check"
        return
    fi
    if [ -z "$LEAVING_DATA_NODES" ] && [ -z "$LEAVING_MASTER_NODES" ]; then
        log "remove logstash or dashboards, do nothing"
        return
    fi
    if [ -n "$LEAVING_DATA_NODES" ] && [ -n "$LEAVING_MASTER_NODES" ]; then
        log "can not remove master nodes and data nodes together"
        return $EC_SCALEIN_BOTH_NOT_ALLOWED
    fi
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "process before scale in master nodes"
        processBeforeScaleInMasterNodes
    else
        log "process before scale in data nodes"
        processBeforeScaleInDataNodes
    fi
}

scaleIn() {
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "scale in master nodes, refresh opensearch.yml"
        refreshOpenSearchConf
        return
    fi

    if [ -n "$LEAVING_DATA_NODES" ]; then
        log "scale in data nodes, do nothing"
        return
    fi

    log "scale in logstash or dashboard, do nothing"
}

processAfterScaleInMasterNodes() {
    local tmplist=($LEAVING_MASTER_NODES)
    if [ ! "$MY_IP" = "${tmplist[0]}" ]; then
        log "only first leaving master node runs post-scale-in procession"
        return
    fi
    local mlist=($STABLE_MASTER_NODES)
    local dlist=($STABLE_DATA_NODES)
    local wantlen=$((${#mlist[@]}+${#dlist[@]}))
    local reallen=$(getClusterHealthInfo ${mlist[0]} | jq '.number_of_nodes')
    retry 120 5 0 test $wantlen -eq $reallen
    clearMasterExclude ${mlist[0]}
}

processAfterScaleInDataNodes() {
    local tmplist=($LEAVING_DATA_NODES)
    if [ ! "$MY_IP" = "${tmplist[0]}" ]; then
        log "only first leaving data node runs post-scale-in procession"
        return
    fi
    local mlist=($STABLE_MASTER_NODES)
    local dlist=($STABLE_DATA_NODES)
    local wantlen=$((${#mlist[@]}+${#dlist[@]}))
    local reallen=$(getClusterHealthInfo ${mlist[0]} | jq '.number_of_nodes')
    retry 120 5 0 test $wantlen -eq $reallen
    clearDataExclude ${mlist[0]}
}

destroy() {
    if [ -n "$LEAVING_MASTER_NODES" ]; then
        log "process after scale in master nodes"
        processAfterScaleInMasterNodes
        return
    fi
    if [ -n "$LEAVING_DATA_NODES" ]; then
        log "process after scale in data nodes"
        processAfterScaleInDataNodes
        return
    fi

    log "normal destory"
}

scaleOut() {
    if [ -n "$JOINING_MASTER_NODES" ]; then
        log "adding master nodes, refresh opensearch.yml"
        refreshOpenSearchConf
        return
    fi

    if [ -n "$JOINING_DATA_NODES" ]; then
        log "adding data nodes, do nothing!"
        return
    fi

    log "scale out logstash or dashboard, do nothing"
}

restart() {
    log "normal restart"
    stop
    start
}

#path
JAVA_HOME=/opt/opensearch/current/jdk
JVM_DUMP_PATH=/data/opensearch/dump

dump() {
    local ip=$(echo "$1" | jq -r '."node.ip"')
    local timeout=$(echo "$1" | jq -r '.timeout')
    
    if [ ! "$ip" = "$MY_IP" ]; then return 0; fi

    local path=$JVM_DUMP_PATH/dump.$(date '+%F_%H%M').hprof

    timeout ${timeout:-1800}s $JAVA_HOME/bin/jhsdb jmap --pid $(cat /var/run/opensearch/opensearch.pid) --binaryheap --dumpfile $path || return 0
}

clearDump() {
  local ip=$(echo "$1" | jq -r '."node.ip"')

  if [ -n "$ip" ] && [ ! "$ip" = "$MY_IP" ]; then return 0; fi

  find $JVM_DUMP_PATH -name '*.hprof' -delete || return 0
}

rollingRestart() {
    local earliest="$(($(date +%s%3N) - 5000))"
    local nodes; nodes=$(echo "$1" | jq -r '."node.ip"')
    if [ -z "$nodes" ]; then nodes=${ROLE_NODES// /,}; fi
    local tmp=$(echo "$nodes" | sed -n "/$MY_IP/p")
    if [ -z "$tmp" ]; then return 0; fi

    local opTimeout; opTimeout=$(echo "$1" | jq -r '.timeout')
    timeout --preserve-status ${opTimeout:-600} appctl restartInOrder $nodes $earliest $IS_MASTER || {
        log "WARN: failed to restart nodes '$nodes' in order ($?)"
        return 0
    }
}

restartInOrder() {
  local nodes="$1" earliest=$2 isMaster=${3:-false}
  local node; for node in ${nodes//,/ }; do
    if [ "$node" = "$MY_IP" ]; then restart; fi

    retry 600 1 0 isLocalServiceAvailable && retry 60 2 0 checkNodeRestarted $earliest $node || log "WARN: Node '$node' seems not restarted."
    # retry 21600 2 0 isClusterStableWithShards $node || log "WARN: Node '$node' seems not loaded within 12 hours."

    if [ "$node" = "$MY_IP" ]; then return 0; fi
  done
}

checkNodeRestarted() {
  local earliest=$1 node=${2:-$MY_IP} startTime
  local jvminfo=$(getNodeJvm $node)
  startTime="$(echo "$jvminfo" | jq -r '.nodes | to_entries[] | .value | .jvm | .start_time_in_millis')"
  log "start:$startTime, earliest:$earliest"
  [ -n "$startTime" ] && [ $startTime -ge $earliest ]
}