# max time for REST API
MAX_TIME_GET_COMMON=10
MAX_TIME_SET_COMMON=30

# wrap the invoke of opensearch rest api
# $1 method: GET/PUT/POST/DELETE
# $2 max-time
# $3 <your url>
# $4 optional, unset - this node's ip, or <ip address>
# $5 optional, <your data>
# http/https is controlled by env variable
invokeRestAPI() {
    local ip
    if [ $# -ge "4" ]; then
        ip="$4"
    else
        ip="$MY_IP"
    fi
    if [ $# -eq "5" ]; then
        curl -s -k -m $2 -u "$SYS_USER":"$SYS_USER_PWD" -X$1 "$HTTP_PROTOCOL://$ip:9200""$3" -H 'Content-Type: application/json' -d"$5"
    else
        curl -s -k -m $2 -u "$SYS_USER":"$SYS_USER_PWD" -X$1 "$HTTP_PROTOCOL://$ip:9200""$3"
    fi
}

getClusterDesc() {
    local params
    if [ $# -eq 1 ]; then
        params="/ $1"
    else
        params="/"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

# $1 node list, like node1,node2,node3
# $2 option, <ip address>
excludeMasterNodes() {
    local url="/_cluster/voting_config_exclusions/$1"
    local params
    if [ $# -eq 2 ]; then
        params="$url $2"
    else
        params="$url"
    fi
    invokeRestAPI POST $MAX_TIME_SET_COMMON $params
}

clearMasterExclude() {
    local url="/_cluster/voting_config_exclusions?wait_for_removal=false"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI DELETE $MAX_TIME_SET_COMMON $params
}

getClusterCoordination() {
    local url="/_cluster/state/metadata/cluster_coordination"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

# $1 node-ip list, like ip1,ip2,ip3
# $2 option, <ip address>
excludeDataNodes() {
    local url="/_cluster/settings"
    if [ $# -eq 2 ]; then
        params="$url $2"
    else
        params="$url $MY_IP"
    fi 
    local data=$(cat<<JSON_DATA
{
    "persistent": {
        "cluster.routing.allocation.exclude._ip": "$1"
    }
}
JSON_DATA
    )
    invokeRestAPI PUT $MAX_TIME_SET_COMMON $params "$data"
}

clearDataExclude() {
    local url="/_cluster/settings"
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url $MY_IP"
    fi 
    local data=$(cat<<JSON_DATA
{
    "persistent": {
        "cluster.routing.allocation.exclude._ip": null
    }
}
JSON_DATA
    )
    invokeRestAPI PUT $MAX_TIME_SET_COMMON $params "$data"
}

# $1 option, node-ip list, like ip1,ip2,ip3
# $2 option, <ip address>
getNodesDocsCountInfo() {
    local url
    if [ $# -eq 0 ]; then
        url="/_nodes/stats/indices/docs"
    else
        url="/_nodes/$1/stats/indices/docs"
    fi
    local params
    if [ $# -eq 2 ]; then
        params="$url $2"
    else
        params="$url"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

getClusterHealthInfo() {
    local url="/_cluster/health"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

getAllNodesId() {
    local url="/_cat/nodes?h=n,ip,id&full_id=true"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

getAllIndices() {
    local url="/_cat/indices?v"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

getIndicesStatusDocsCount() {
    local url="/_cat/indices?h=status,docs.count"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

getAllShards() {
    local url="/_cat/shards?v"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET $MAX_TIME_GET_COMMON $params
}

# $1 /<index-name>
# $2 <number_of_shards>
# $3 option: <ip> or <$MY_IP>
createIndex() {
    local data=$(cat<<MY_DATA
{
  "settings": {
    "number_of_shards": $2
  },
  "mappings": {
    "properties": {
      "field1": { "type": "text" }
    }
  }
}
MY_DATA
    )
    local params
    if [ $# -eq 3 ]; then
        params="$1 $3"
    else
        params="$1 $MY_IP"
    fi
    invokeRestAPI PUT $MAX_TIME_SET_COMMON $params "$data"
}

deleteIndex() {
    local params
    if [ $# -eq 2 ]; then
        params="$1 $2"
    else
        params="$1 $MY_IP"
    fi
    invokeRestAPI DELETE $MAX_TIME_SET_COMMON $params
}

# $1 key
# $2 value, the value is used as it is
# eg. abc -> abc, \"abc\" -> "abc"
# $3 option: <ip> or $MY_IP
updateClusterSettings() {
    local url="/_cluster/settings"
    if [ $# -eq 3 ]; then
        params="$url $3"
    else
        params="$url $MY_IP"
    fi 
    local data=$(cat<<JSON_DATA
{
    "persistent": {
        "$1": $2
    }
}
JSON_DATA
    )
    invokeRestAPI PUT $MAX_TIME_SET_COMMON $params "$data"
}

# $1 key
# $2 option: <ip> or $MY_IP
resetClusterSettings() {
    local url="/_cluster/settings"
    if [ $# -eq 2 ]; then
        params="$url $2"
    else
        params="$url $MY_IP"
    fi 
    local data=$(cat<<JSON_DATA
{
    "persistent": {
        "$1": null
    }
}
JSON_DATA
    )
    invokeRestAPI PUT $MAX_TIME_SET_COMMON $params "$data"
}