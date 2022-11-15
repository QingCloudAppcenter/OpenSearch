# wrap the invoke of opensearch rest api
# $1 max-time
# $2 https://<ip>:9200/<your url>
# $3 optional, unset - this node's ip, or <ip address>
# http/https is controlled by env variable
invokeRestAPIGet() {
    local ip
    if [ $# -eq "3" ]; then
        ip="$3"
    else
        ip="$MY_IP"
    fi
    curl -s -k -m $1 -u "$SYS_USER":"$SYS_USER_PWD" -XGET "$HTTP_PROTOCOL://$ip:9200""$2"
}

# $1 max-time
# $2 https://<ip>:9200/<your url>
# $3 <your data>
# $4 optional, unset - this node's ip, or <ip address>
# http/https is controlled by env variable
invokeRestAPIPut() {
    local ip
    if [ $# -eq "4" ]; then
        ip="$4"
    else
        ip="$MY_IP"
    fi
    curl -s -k -m $1 -u "$SYS_USER":"$SYS_USER_PWD" -XPUT "$HTTP_PROTOCOL://$ip:9200""$2" -H 'Content-Type: application/json' -d"$3"
}

isLocalServiceAvailable() {
    local res=$(invokeRestAPIGet 5 "/")
    local clname=$(echo "$res" | jq -r '.cluster_name')
    test "$clname" = "$CLUSTER_ID"
}

createIndex() {
    local data=$(cat<<MY_DATA
{
  "settings": {
    "number_of_shards": 1
  },
  "mappings": {
    "properties": {
      "field1": { "type": "text" }
    }
  }
}
MY_DATA
    )
    invokeRestAPIPut 5 "/mytest" "$data"
}