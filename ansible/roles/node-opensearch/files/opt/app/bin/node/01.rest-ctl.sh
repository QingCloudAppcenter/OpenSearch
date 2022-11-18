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
    invokeRestAPI GET 10 $params
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
    invokeRestAPI POST 30 $params
}

clearMasterExclude() {
    local url="/_cluster/voting_config_exclusions?wait_for_removal=false"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI DELETE 30 $params
}

getClusterCoordination() {
    local url="/_cluster/state/metadata/cluster_coordination"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET 10 $params
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
    invokeRestAPI PUT 30 $params "$data"
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
    invokeRestAPI PUT 30 $params "$data"
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
    invokeRestAPI GET 10 $params
}

getClusterHealthInfo() {
    local url="/_cluster/health"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET 10 $params
}

getAllNodesId() {
    local url="/_cat/nodes?h=n,ip,id&full_id=true"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET 10 $params
}

getAllIndices() {
    local url="/_cat/indices?v"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET 10 $params
}

getIndicesStatusDocsCount() {
    local url="/_cat/indices?h=status,docs.count"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET 10 $params
}

getAllShards() {
    local url="/_cat/shards?v"
    local params
    if [ $# -eq 1 ]; then
        params="$url $1"
    else
        params="$url"
    fi
    invokeRestAPI GET 10 $params
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
    invokeRestAPI PUT 30 $params "$data"
}

deleteIndex() {
    local params
    if [ $# -eq 2 ]; then
        params="$1 $2"
    else
        params="$1 $MY_IP"
    fi
    invokeRestAPI DELETE 30 $params
}