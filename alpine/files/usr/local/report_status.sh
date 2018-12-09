#!/bin/sh

TYPE=$1
SEQNO=$2
CLUSTER_NAME=$3
TTL=$4
ETCD_HOSTS=$5

function check_etcd()
{
  etcd_hosts=$(echo $ETCD_HOSTS | tr ',' ' ')
  flag=1

  for i in $etcd_hosts
  do
    curl -s http://$i/health > /dev/null || continue
    if curl -s http://$i/health | jq -e 'contains({ "health": "true"})' > /dev/null; then
      healthy_etcd=$i
      flag=0
      break
    fi
  done

  [ $flag -ne 0 ] && echo "report>> Couldn't reach healthy etcd nodes."
}

function report_status()
{
  value=$2
  key=$1

  check_etcd

  URL="http://$healthy_etcd/v2/keys/$TYPE/$CLUSTER_NAME"
  if [ -z $key ]; then
    key=0
  fi
  ipaddr=$(hostname -i | awk {'print $1'})

  if [ ! -z $value ]; then
#    echo "register $URL/$ipaddr/$key value:$value"
    curl -s $URL/$ipaddr/$key -X PUT -d "value=$value&ttl=$TTL" > /dev/null
  fi
}

function get_current_role()
{
  if [ $SEQNO -eq "0" ]; then
    role=master
  elif [ $SEQNO -eq "1" ]; then
    role=slave
  else
    redis=$(redis-cli -a $REDIS_CLUSTER_PASS role)
    role=$(echo $redis | awk -F' ' '{print $1}')
  fi
}

while true;
do
  get_current_role
  report_status hostname $(hostname)
  report_status seqno $SEQNO
  report_status role $role
  # report every ttl - 2 to ensure value does not expire
  sleep $(($TTL - 2))
  SEQNO="-1"
done

