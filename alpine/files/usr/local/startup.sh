#!/bin/sh

TYPE=redis

[ -z "$REDIS_MASTER_NAME" ] && REDIS_MASTER_NAME='mymaster'

[ -z "$TTL" ] && TTL=10

function join { local IFS="$1"; shift; echo "$*"; }

if [ ! -z "$DISCOVERY_SERVICE" ]; then
  echo '>> Registering in the discovery service'

  etcd_hosts=$(echo $DISCOVERY_SERVICE | tr ',' ' ')
  flag=1

  echo
  # Loop to find a healthy etcd host
  for i in $etcd_hosts
  do
    echo ">> Connecting to http://${i}/health"
    curl -s http://${i}/health || continue
    if curl -s http://$i/health | jq -e 'contains({ "health": "true"})'; then
      healthy_etcd=$i
      flag=0
      break
    else
      echo >&2 ">> Node $i is unhealty. Proceed to the next node."
    fi
  done

  # Flag is 0 if there is a healthy etcd host
  if [ $flag -ne 0 ]; then
    echo ">> Couldn't reach healthy etcd nodes."
    exit 1
  fi

  echo
  echo ">> Selected healthy etcd: $healthy_etcd"

  if [ ! -z "$healthy_etcd" ]; then
    URL="http://$healthy_etcd/v2/keys/$TYPE/$REDIS_MASTER_NAME"

    set +e
    echo >&2 ">> Waiting for $TTL seconds to read non-expired keys.."
    sleep $((TTL + (RANDOM % 10 ) + 2 ))

    # Read the list of registered IP addresses
    echo >&2 ">> Retrieving list of keys for $REDIS_MASTER_NAME"
    addr=$(curl -s $URL | jq -r '.node.nodes[]?.key' | awk -F'/' '{print $(NF)}')
    cluster_join=$(join , $addr)

    ipaddr=$(hostname -i | awk {'print $1'})
    [ -z $ipaddr ] && ipaddr=$(hostname -I | awk {'print $1'})

     if [ -z $cluster_join ]; then
       echo >&2 ">> KV store is empty. This is a the first node to come up."
       echo
       echo >&2 ">> Registering $ipaddr in http://$healthy_etcd"
       curl -s $URL/$ipaddr/ipaddress -X PUT -d "value=$ipaddr"
       REDIS_MASTER_HOST=$ipaddr
       ipaddr_master=$ipaddr
       SEQNO=0
     else
       curl -s ${URL}?recursive=true\&sorted=true > /tmp/out
       master_node=$(cat /tmp/out | jq -r '.node.nodes[].nodes[]? | select(.key | contains ("role")) | select(.value == "master") | .key' | awk -F'/' '{print $(NF-1)}' | tr "\n" ' '| sed -e 's/[[:space:]]*$//')

       if [ -z "$master_node" ]; then
         SEQNO=0
         ipaddr_master=$ipaddr
       else
         ipaddr_master=$(join , $master_node)
         slave_config="slaveof $ipaddr_master $REDIS_MASTER_PORT"
         echo "Starting as slave with config: $slave_config"
         SEQNO=1
       fi
     fi
    set -e

    nohup /usr/local/report_status.sh $TYPE $SEQNO $REDIS_MASTER_NAME $TTL $DISCOVERY_SERVICE &
  fi
else
  ipaddr_master=$REDIS_MASTER_HOST
fi

echo "Using $ipaddr_master as master IP"

#Prepare configuration files
sed -i "s/replace_redis_cluster_pass/$REDIS_CLUSTER_PASS/gI" /etc/redis.conf
sed -i "s/replace_redis_cluster_master_pass/$REDIS_CLUSTER_MASTER_PASS/gI" /etc/redis.conf
sed -i "s/replace_slave_config/$slave_config/gI" /etc/redis.conf

sed -i "s/replace_redis_master_host/$ipaddr_master/gI" /etc/redis-sentinel.conf
sed -i "s/replace_redis_master_port/$REDIS_MASTER_PORT/gI" /etc/redis-sentinel.conf
sed -i "s/replace_redis_cluster_master_pass/$REDIS_CLUSTER_MASTER_PASS/gI" /etc/redis-sentinel.conf
sed -i "s/replace_redis_master_name/$REDIS_MASTER_NAME/gI" /etc/redis-sentinel.conf

echo "Starting redis-server"
redis-server /etc/redis.conf &

echo "Starting redis-sentinel"
redis-sentinel /etc/redis-sentinel.conf

