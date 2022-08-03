#!/usr/bin/env bash
VERSION=001
LOG_FILE=/data/patch.log
BACK_FOLDER=/data/patch_back/$VERSION
PATCH_FOLDER=/data/patch${VERSION}

APPCTL_DATA_PATH="/data/appctl/data"
APPCTL_CUR_ADMIN_PWD="admin.cur"
APPCTL_SECURITY_BACKUP_FOLDER="security_backup"

SECURITY_TOOL_FOLDER="/opt/opensearch/current/plugins/opensearch-security/tools"
ADMIN_TOOL=$SECURITY_TOOL_FOLDER/securityadmin.sh
HASH_TOOL=$SECURITY_TOOL_FOLDER/hash.sh

set -eo pipefail

log() {
  echo "$1" >> $LOG_FILE
}

apply() {
  log "backup old files"
  mkdir -p $BACK_FOLDER
  cp /etc/confd/conf.d/opensearch.sh.toml $BACK_FOLDER
  cp /etc/confd/templates/opensearch.sh.tmpl $BACK_FOLDER
  cp /opt/app/bin/node/opensearch.sh $BACK_FOLDER
  log "copy files"
  cp -r $PATCH_FOLDER/etc/* /etc
  cp -r $PATCH_FOLDER/opt/* /opt
  log "restart confd"
  systemctl restart confd || :;
  log "prepare files & folders"
  mkdir -p $APPCTL_DATA_PATH/$APPCTL_SECURITY_BACKUP_FOLDER
  while [ ! -f /opt/app/conf/appctl/admin.pwd.new ]; do sleep 1s; done
  cat /opt/app/conf/appctl/admin.pwd.new > $APPCTL_DATA_PATH/$APPCTL_CUR_ADMIN_PWD
  chmod +x $ADMIN_TOOL
  chmod +x $HASH_TOOL
  log "patch succeed!"
}

rollback() {
  if [ -f $BACK_FOLDER/opensearch.sh.toml ]; then
    log "revert file: opensearch.sh.toml"
    cp $BACK_FOLDER/opensearch.sh.toml /etc/confd/conf.d
  fi
  if [ -f $BACK_FOLDER/opensearch.sh.tmpl ]; then
    log "revert file: opensearch.sh.tmpl"
    cp $BACK_FOLDER/opensearch.sh.tmpl /etc/confd/templates
  fi
  if [ -f $BACK_FOLDER/opensearch.sh ]; then
    log "revert file: opensearch.sh"
    cp $BACK_FOLDER/opensearch.sh /opt/app/bin/node
  fi
  log "restart confd"
  systemctl restart confd || :;
  log "remove folder: /data/appctl/data"
  rm -rf /data/appctl/data
  log "remove folder: /opt/app/conf/appctl"
  rm -rf /opt/app/conf/appctl
  log "rollback succeed!"
}

info() {
  :
}

dev() {
  :
}

command=$1

if [ "$command" = "apply" ]; then
  apply
elif [ "$command" = "rollback" ]; then
  rollback
elif [ "$command" = "dev" ]; then
  dev
elif [ "$command" = "info" ]; then
  info
else
  echo 'usage: patch [ apply | rollback | info ]'
fi