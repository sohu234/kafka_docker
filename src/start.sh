#! /usr/bin/env bash

# Fail hard and fast
set -eo pipefail

# Evaluate commands
for VAR in $(env)
do
  if [[ $VAR =~ ^KAFKA_.*_COMMAND= ]]; then
    VAR_NAME=${VAR%%=*}
    EVALUATED_VALUE=$(eval ${!VAR_NAME})
    export ${VAR_NAME%_COMMAND}=${EVALUATED_VALUE}
    echo "${VAR} -> ${VAR_NAME%_COMMAND}=${EVALUATED_VALUE}"
  fi
done

KAFKA_BROKER_ID=`hostname | cut -d"-" -f2`

# Check mandatory parameters
if [ -z "$KAFKA_BROKER_ID" ]; then
  echo "\$KAFKA_BROKER_ID not set"
  exit 1
fi
echo "KAFKA_BROKER_ID=$KAFKA_BROKER_ID"

if [ -z "$KAFKA_ADVERTISED_HOST_NAME" ]; then
  echo "\$KAFKA_ADVERTISED_HOST_NAME not set"
  exit 1
fi
echo "KAFKA_ADVERTISED_HOST_NAME=$KAFKA_ADVERTISED_HOST_NAME"

if [ -z "$KAFKA_ZOOKEEPER_CONNECT" ]; then
  echo "\$KAFKA_ZOOKEEPER_CONNECT not set"
  exit 1
fi
echo "KAFKA_ZOOKEEPER_CONNECT=$KAFKA_ZOOKEEPER_CONNECT"

KAFKA_LOCK_FILE="/var/lib/kafka/.lock"
if [ -e "${KAFKA_LOCK_FILE}" ]; then
  echo "removing stale lock file"
  rm ${KAFKA_LOCK_FILE}
fi

export KAFKA_LOG_DIRS=${KAFKA_LOG_DIRS:-/var/lib/kafka}

# General config
for VAR in `env`
do
  if [[ $VAR =~ ^KAFKA_ && ! $VAR =~ ^KAFKA_HOME ]]; then
    KAFKA_CONFIG_VAR=$(echo "$VAR" | sed -r "s/KAFKA_(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .)
    KAFKA_ENV_VAR=${VAR%%=*}

    if egrep -q "(^|^#)$KAFKA_CONFIG_VAR" $KAFKA_HOME/config/server.properties; then
      sed -r -i "s (^|^#)$KAFKA_CONFIG_VAR=.*$ $KAFKA_CONFIG_VAR=${!KAFKA_ENV_VAR} g" $KAFKA_HOME/config/server.properties
    else
      echo "$KAFKA_CONFIG_VAR=${!KAFKA_ENV_VAR}" >> $KAFKA_HOME/config/server.properties
    fi
  fi
done

# Logging config
sed -i "s/^kafka\.logs\.dir=.*$/kafka\.logs\.dir=\/var\/log\/kafka/" /opt/kafka/config/log4j.properties
export LOG_DIR=/var/log/kafka

sed -i "s/^broker.id=.*$/broker.id=${KAFKA_BROKER_ID}/g" /opt/kafka/config/server.properties

su root -s /bin/bash -c "cd /opt/kafka && bin/kafka-server-start.sh config/server.properties"
