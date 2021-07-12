#!/bin/bash

# Kerberos KDC server configuration
# Ref: https://github.com/dosvath/kerberos-containers/blob/master/kdc-server/init-script.sh

# kerberos client
echo ${MY_POD_IP} pegacorn-fhirplace-namenode.kerberos.com >> /etc/hosts
sed -i "s/localhost/pegacorn-fhirplace-namenode.kerberos.com/g" /etc/krb5.conf

# certificates
cp /etc/hadoop/ssl/ca.crt /usr/local/share/ca-certificates
update-ca-certificates --verbose

echo "==== Creating realm ==============================================================="
echo "==================================================================================="
# TDL -- Use HELM env variables for passwords
MASTER_PASSWORD=Peg@corn
KADMIN_PRINCIPAL=root/admin
REALM=PEGACORN-FHIRPLACE-NAMENODE.SITE-A
KADMIN_PRINCIPAL_FULL=$KADMIN_PRINCIPAL@$REALM
# This command also starts the krb5-kdc and krb5-admin-server services
krb5_newrealm <<EOF
$MASTER_PASSWORD
$MASTER_PASSWORD
EOF
echo ""

echo "==================================================================================="
echo "==== Creating hdfs principal in the acl ======================================="
echo "==================================================================================="
echo "Adding $KADMIN_PRINCIPAL principal"
# kadmin.local -q "delete_principal -force K/M@PEGACORN-FHIRPLACE-NAMENODE.SITE-A"
echo ""
kadmin.local -q "addprinc -pw $MASTER_PASSWORD $KADMIN_PRINCIPAL_FULL"
echo ""

kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey jboss/admin@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k root.hdfs.keytab jboss/admin"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey jboss@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k jboss.hdfs.keytab jboss"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey HTTP/jboss@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k http.hdfs.keytab HTTP/jboss"

# secure alpha datanode
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "addprinc -randkey alpha/admin@$REALM"
kadmin -p root/admin -w ${MASTER_PASSWORD} -q "xst -k alpha.hdfs.keytab alpha/admin"

mv root.hdfs.keytab ${KEYTAB_DIR}
mv alpha.hdfs.keytab ${KEYTAB_DIR}
mv jboss.hdfs.keytab ${KEYTAB_DIR}
mv http.hdfs.keytab ${KEYTAB_DIR}
chmod 400 ${KEYTAB_DIR}/root.hdfs.keytab
chmod 400 ${KEYTAB_DIR}/alpha.hdfs.keytab
chmod 400 ${KEYTAB_DIR}/http.hdfs.keytab
# chown jboss:0 ${KEYTAB_DIR}/jboss.hdfs.keytab
chmod 777 ${KEYTAB_DIR}/jboss.hdfs.keytab

kinit jboss/admin@$REALM -kt ${KEYTAB_DIR}/root.hdfs.keytab -V &
wait -n
echo "NameNode TGT completed."


### Start entrypoint.sh
### https://github.com/big-data-europe/docker-hadoop/blob/master/base/entrypoint.sh
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
configure /etc/hadoop/yarn-site.xml yarn YARN_CONF
configure /etc/hadoop/httpfs-site.xml httpfs HTTPFS_CONF
configure /etc/hadoop/kms-site.xml kms KMS_CONF
configure /etc/hadoop/mapred-site.xml mapred MAPRED_CONF

if [ "$MULTIHOMED_NETWORK" = "1" ]; then
    echo "Configuring for multihomed network"

    # CORE
    addProperty /etc/hadoop/core-site.xml fs.defaultFS hdfs://${MY_POD_NAME}:9820
    addProperty /etc/hadoop/core-site.xml hadoop.security.authentication kerberos
    addProperty /etc/hadoop/core-site.xml hadoop.security.authorization true
    addProperty /etc/hadoop/core-site.xml hadoop.security.auth_to_local DEFAULT
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.server.conf ssl-server.xml
    # addProperty /etc/hadoop/core-site.xml hadoop.ssl.client.conf ssl-client.xml
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.require.client.cert false
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.hostname.verifier ALLOW_ALL
    addProperty /etc/hadoop/core-site.xml hadoop.ssl.keystores.factory.class org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory
    addProperty /etc/hadoop/core-site.xml hadoop.rpc.protection privacy
    addProperty /etc/hadoop/core-site.xml hadoop.http.authentication.signature.secret.file ${KEYTAB_DIR}/hadoop-http-auth-signature-secret
    

    # HDFS
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.https-address ${MY_POD_NAME}:9871
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.datanode.registration.ip-hostname-check false
    # addProperty /etc/hadoop/hdfs-site.xml dfs.client.use.datanode.hostname true
    addProperty /etc/hadoop/hdfs-site.xml dfs.encrypt.data.transfer true
    addProperty /etc/hadoop/hdfs-site.xml dfs.permissions.superusergroup pegacorn
    addProperty /etc/hadoop/hdfs-site.xml dfs.replication 1
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.keytab.file ${KEYTAB_DIR}/root.hdfs.keytab
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.kerberos.principal jboss/admin@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.block.access.token.enable true
    addProperty /etc/hadoop/hdfs-site.xml dfs.http.policy HTTPS_ONLY
    addProperty /etc/hadoop/hdfs-site.xml dfs.client.https.need-auth false
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.principal HTTP/jboss@${REALM}
    addProperty /etc/hadoop/hdfs-site.xml dfs.web.authentication.kerberos.keytab ${KEYTAB_DIR}/http.hdfs.keytab
    addProperty /etc/hadoop/hdfs-site.xml dfs.namenode.kerberos.internal.spnego.principal HTTP/jboss@${REALM}  
fi

function wait_for_it()
{
    local serviceport=$1
    local service=${serviceport%%:*}
    local port=${serviceport#*:}
    local retry_seconds=5
    local max_try=100
    let i=1

    nc -z $service $port
    result=$?

    until [ $result -eq 0 ]; do
      echo "[$i/$max_try] check for ${service}:${port}..."
      echo "[$i/$max_try] ${service}:${port} is not available yet"
      if (( $i == $max_try )); then
        echo "[$i/$max_try] ${service}:${port} is still not available; giving up after ${max_try} tries. :/"
        exit 1
      fi
      
      echo "[$i/$max_try] try in ${retry_seconds}s once again ..."
      let "i++"
      sleep $retry_seconds

      nc -z $service $port
      result=$?
    done
    echo "[$i/$max_try] $service:${port} is available."
}

for i in ${SERVICE_PRECONDITION[@]}
do
    wait_for_it ${i}
done

### End entrypoint.sh

namedir=`echo $HDFS_CONF_dfs_namenode_name_dir | perl -pe 's#file://##'`
if [ ! -d $namedir ]; then
  echo "Namenode name directory not found: $namedir"
  exit 2
fi

if [ -z "$CLUSTER_NAME" ]; then
  echo "Cluster name not specified"
  exit 2
fi

echo "remove lost+found from $namedir"
rm -r $namedir/lost+found

if [ "`ls -A $namedir`" == "" ]; then
  echo "Formatting namenode name directory: $namedir"
  $HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR namenode -format $CLUSTER_NAME
fi

$HADOOP_HOME/bin/hdfs --config $HADOOP_CONF_DIR namenode