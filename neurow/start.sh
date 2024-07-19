#!/bin/sh -e

echo "*** Neurow ***"

if [ "$POD_IP" != "" ]; then
  export RELEASE_DISTRIBUTION="name"
  export RELEASE_NODE="neurow@${POD_IP}"
  echo "Starting Elixir daemon in kubernetes, node: $RELEASE_NODE"
else
  echo "Starting Elixir daemon"
fi

exec /app/bin/neurow start