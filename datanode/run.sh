#!/bin/bash

REALM=PEGACORN-FHIRPLACE-NAMENODE.SITE-A

# kerberos client
echo ${NAMENODE_IP} pegacorn-fhirplace-namenode.kerberos.com >> /etc/hosts
sed -i "s/localhost/pegacorn-fhirplace-namenode.kerberos.com/g" /etc/krb5.conf

kinit alpha/admin@$REALM -kt ${KEYTAB_DIR}/alpha.hdfs.keytab -V &
wait -n
echo "DataNode TGT completed."

# certificates
cp /etc/hadoop/ssl/ca.crt /usr/local/share/ca-certificates
update-ca-certificates --verbose

function addProperty() {
  local path=$1
  local name=$2
  local value=$3

  local entry="<property><name>$name</name><value>${value}</value></property>"
  local escapedEntry=$(echo $entry | sed 's/\//\\\//g')
  sed -i "/<\/configuration>/ s/.*/${escapedEntry}\n&/" $path
}

function configure() {
    local path=$1
    local module=$2
    local envPrefix=$3

    local var
    local value
    
    echo "Configuring $module"
    for c in `printenv | perl -sne 'print "$1 " if m/^${envPrefix}_(.+?)=.*/' -- -envPrefix=$envPrefix`; do 
        name=`echo ${c} | perl -pe 's/___/-/g; s/__/@/g; s/_/./g; s/@/_/g;'`
        var="${envPrefix}_${c}"
        value=${!var}
        echo " - Setting $name=$value"
        addProperty $path $name "$value"
    done
}

configure /etc/hadoop/core-site.xml core CORE_CONF
configure /etc/hadoop/hdfs-site.xml hdfs HDFS_CONF

if [ "$MULTIHOMED_NETWORK" = "1" ]; then
    echo "Configuring for multihomed network"

    # CORE
    addProperty /etc/hadoop/core-site.xml fs.defaultFS hdfs://${CLUSTER_IP}:8020
    addProperty /etc/hadoop/core-site.xml hadoop.security.authentication kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.security.authorization true
    addProperty /etc/hadoop/core-site.xml hadoop.security.auth_to_local DEFAULT
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.server.conf ssl-server.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.client.conf ssl-client.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.require.client.cert false
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.hostname.verifier ALLOW_ALL
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.keystores.factory.class org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory
    addProperty /etc/hadoop/core-site.xml hadoop.rpc.protection privacy

    # HDFS
    addProperty /etc/hadoop/hdfs-site.xml dfs.replication 1
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.kerberos.principal alpha/admin@$REALM
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.keytab.file ${KEYTAB_DIR}/alpha.hdfs.keytab
    addProperty /etc/hadoop/hdfs-site.xml dfs.block.access.token.enable true
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.address ${MY_POD_NAME}:50010
    addProperty /etc/hadoop/hdfs-site.xml dfs.datanode.https.address ${MY_POD_NAME}:9865
    addProperty /etc/hadoop/hdfs-site.xml dfs.data.transfer.protection integrity
    addProperty /etc/hadoop/hdfs-site.xml dfs.http.policy HTTPS_ONLY
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.need-auth false
    addProperty /etc/hadoop/hdfs-site.xml dfs.encrypt.data.transfer true
    addProperty /etc/hadoop/hdfs-site.xml dfs.cluster.administrators jboss
    addProperty /etc/hadoop/hdfs-site.xml dfs.https.server.keystore.resource ssl-server.xml
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.keystore.resource ssl-client.xml
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.https-address ${CLUSTER_IP}:9871
fi


datadir=`echo $HDFS_CONF_dfs_datanode_data_dir | perl -pe 's#file://##'`
if [ ! -d $datadir ]; then
  echo "Datanode data directory not found: $datadir"
  exit 2
fi

$HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR datanode