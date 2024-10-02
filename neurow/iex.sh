#!/bin/sh -e

if [ "$POD_IP" != "" ]; then
  export RELEASE_DISTRIBUTION="name"
  export RELEASE_NODE="neurow@${POD_IP}"
fi

/app/bin/neurow remote