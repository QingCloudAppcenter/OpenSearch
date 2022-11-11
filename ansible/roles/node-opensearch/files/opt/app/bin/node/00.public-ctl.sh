# wrap the invoke of opensearch rest api
# $1 https://<ip>:9200/<your input>
# $2 optional, unset - this node's ip, or other ip address
# http/https is controlled by env variable
invokeRestAPIGet() {
    :
}

isClusterAvailable() {
    curl -u "$SYS_USER":"$SYS_USER_PWD"
}