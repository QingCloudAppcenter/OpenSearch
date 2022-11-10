# paths
OPENSEARCH_CONF_PATH=/opt/app/current/conf/opensearch/opensearch.yml
OPENSEARCH_CONF_REF_STATIC_PATH=/data/appctl/data/opensearch.conf.ref.static
JVM_OPTIONS_PATH=/opt/app/current/conf/opensearch/jvm.options
# recreate opensearch.yml according to static config

refreshOpenSearchConf() {
    local cfg=$(cat<<OS_CONF
cluster.name: ${CLUSTER_ID}
node.name: ${NODE_NAME}
path.data: /data/opensearch/data
path.logs: /data/opensearch/logs
network.host: ${MY_IP}
http.port: 9200
discovery.seed_hosts: [ ${STABLE_MASTER_NODES_HOSTS// /,} ]

plugins.security.ssl.http.enabled: false
plugins.security.ssl.http.pemcert_filepath: certs/qc/node1.pem
plugins.security.ssl.http.pemkey_filepath: certs/qc/node1-key.pem
plugins.security.ssl.http.pemtrustedcas_filepath: certs/qc/root-ca.pem

plugins.security.ssl.transport.pemkey_filepath: certs/qc/node1-key.pem
plugins.security.ssl.transport.pemcert_filepath: certs/qc/node1.pem
plugins.security.ssl.transport.pemtrustedcas_filepath: certs/qc/root-ca.pem
plugins.security.ssl.transport.enforce_hostname_verification: false

plugins.security.allow_unsafe_democertificates: true
plugins.security.allow_default_init_securityindex: true

plugins.security.authcz.admin_dn:
  - 'CN=qcadmin,OU=NoSql,O=QC,L=WuHan,ST=HuBei,C=CN'
plugins.security.nodes_dn:
  - 'CN=node.opensearch.cluster,OU=NoSql,O=QC,L=WuHan,ST=HuBei,C=CN'
OS_CONF
    )
    echo "$cfg" > ${OPENSEARCH_CONF_PATH}
}

refreshJvmOptions() {
    local osfolder="/data/opensearch"
    local cfg=$(cat<<JVM_CONF
## JVM configuration

################################################################
## IMPORTANT: JVM heap size
################################################################
##
## You should always set the min and max JVM heap
## size to the same value. For example, to set
## the heap to 4 GB, set:
##
## -Xms4g
## -Xmx4g
##
## See https://opensearch.org/docs/opensearch/install/important-settings/
## for more information
##
################################################################

# Xms represents the initial size of total heap space
# Xmx represents the maximum size of total heap space

-Xms1g
-Xmx1g

################################################################
## Expert settings
################################################################
##
## All settings below this section are considered
## expert settings. Don't tamper with them unless
## you understand what you are doing
##
################################################################

## GC configuration
8-10:-XX:+UseConcMarkSweepGC
8-10:-XX:CMSInitiatingOccupancyFraction=75
8-10:-XX:+UseCMSInitiatingOccupancyOnly

## G1GC Configuration
# NOTE: G1 GC is only supported on JDK version 10 or later
# to use G1GC, uncomment the next two lines and update the version on the
# following three lines to your version of the JDK
# 10:-XX:-UseConcMarkSweepGC
# 10:-XX:-UseCMSInitiatingOccupancyOnly
11-:-XX:+UseG1GC
11-:-XX:G1ReservePercent=25
11-:-XX:InitiatingHeapOccupancyPercent=30

## JVM temporary directory
-Djava.io.tmpdir=\${OPENSEARCH_TMPDIR}

## heap dumps

# generate a heap dump when an allocation from the Java heap fails
# heap dumps are created in the working directory of the JVM
-XX:+HeapDumpOnOutOfMemoryError

# specify an alternative path for heap dumps; ensure the directory exists and
# has sufficient space
-XX:HeapDumpPath=data

# specify an alternative path for JVM fatal error logs
-XX:ErrorFile=${osfolder}/logs/hs_err_pid%p.log

## JDK 8 GC logging
8:-XX:+PrintGCDetails
8:-XX:+PrintGCDateStamps
8:-XX:+PrintTenuringDistribution
8:-XX:+PrintGCApplicationStoppedTime
8:-Xloggc:${osfolder}/logs/gc.log
8:-XX:+UseGCLogFileRotation
8:-XX:NumberOfGCLogFiles=32
8:-XX:GCLogFileSize=64m

# JDK 9+ GC logging
9-:-Xlog:gc*,gc+age=trace,safepoint:file=${osfolder}/logs/gc.log:utctime,pid,tags:filecount=32,filesize=64m

# Explicitly allow security manager (https://bugs.openjdk.java.net/browse/JDK-8270380)
18-:-Djava.security.manager=allow

JVM_CONF
    )
    echo "$cfg" > ${JVM_OPTIONS_PATH}
}

start() {
    echo "start"
}

init() {
    _init
    echo "init"
}