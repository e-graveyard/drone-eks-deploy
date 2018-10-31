#!/bin/sh

if [ -z ${PLUGIN_ACCESS_KEY} ]; then
    echo "Missing access key"
    exit 1
fi

if [ -z ${PLUGIN_SECRET_KEY} ]; then
    echo "Missing secret key"
    exit 1
fi

if [ -z ${PLUGIN_CLUSTER} ]; then
    echo "Missing cluster name"
    exit 1
fi

if [ -z ${PLUGIN_MANIFEST} ]; then
    echo "Missing manifest name"
    exit 1
fi

if [ -z ${PLUGIN_AWS_REGION} ]; then
    # Try to pull the region from the host that is running Drone - this assumes
    # the Drone EC2 instance is in the same region as the EKS cluster you are
    # deploying onto. If needed, override with PLUGIN_AWS_REGION param,
    export AWS_REGION_AND_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
    export PLUGIN_AWS_REGION=$(echo ${AWS_REGION_AND_ZONE} | sed 's/[a-z]$//')
fi
export AWS_DEFAULT_REGION=${PLUGIN_AWS_REGION}


echo "Exporting credentials..."
export AWS_ACCESS_KEY_ID=${PLUGIN_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${PLUGIN_SECRET_KEY}


echo "Updating kubernetes configuration..."
aws eks update-kubeconfig --name ${PLUGIN_CLUSTER}


echo "Applying the new manifest..."
cat ${PLUGIN_MANIFEST} | kubectl apply -f -
