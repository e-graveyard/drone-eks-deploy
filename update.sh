#!/bin/sh

echo "Initializing..."

if [ -z ${PLUGIN_AWS_REGION} ]; then
    # Try to pull the region from the host that is running Drone - this assumes
    # the Drone EC2 instance is in the same region as the EKS cluster you are
    # deploying onto. If needed, override with PLUGIN_AWS_REGION param,
    export AWS_REGION_AND_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
    export PLUGIN_AWS_REGION=$(echo ${AWS_REGION_AND_ZONE} | sed 's/[a-z]$//')
fi
export AWS_DEFAULT_REGION=${PLUGIN_AWS_REGION}


export NODE_GROUP_ARN=${PLUGIN_NODE_ROLE}
export CLUSTER_NAME=$(echo "${PLUGIN_CLUSTER}" | cut -d"/" -f2)
echo ""
echo "Trying to deploy against '$CLUSTER_NAME' ($AWS_DEFAULT_REGION)."
echo ""

echo "Fetching the authentication token..."
KUBERNETES_TOKEN=$(aws-iam-authenticator token -i $CLUSTER_NAME -r $NODE_GROUP_ARN | jq -r .status.token)

if [ -z $KUBERNETES_TOKEN ]; then
    echo ""
    echo "Unable to obtain Kubernetes token - check Drone's IAM permissions"
    echo "Maybe it cannot assume the '$NODE_GROUP_ARN' role?"
    exit 1
fi


echo "Fetching the EKS cluster information..."
EKS_URL=$(aws eks describe-cluster --name $CLUSTER_NAME | jq -r .cluster.endpoint)
EKS_CA=$(aws eks describe-cluster --name $CLUSTER_NAME | jq -r .cluster.certificateAuthority.data)

if [ -z $EKS_URL ] || [ -z $EKS_CA ]; then
    echo ""
    echo "Unable to obtain EKS cluster information - check Drone's EKS API permissions"
    exit 1
fi


echo "Generating the k8s configuration file..."
mkdir ~/.kube
cat > ~/.kube/config << EOF
apiVersion: v1
preferences: {}
kind: Config

clusters:
- cluster:
    server: ${EKS_URL}
    certificate-authority-data: ${EKS_CA}
  name: ${PLUGIN_CLUSTER}

contexts:
- context:
    cluster: ${PLUGIN_CLUSTER}
    user: ${PLUGIN_CLUSTER}
  name: ${PLUGIN_CLUSTER}

current-context: ${PLUGIN_CLUSTER}

users:
- name: ${PLUGIN_CLUSTER}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
      - token
      - -i
      - $CLUSTER_NAME
EOF


echo "Exporting k8s configuration path..."
export KUBECONFIG=$KUBECONFIG:~/.kube/config


echo "Applying the manifest..."
echo ""
cat ${PLUGIN_MANIFEST} | kubectl apply -f -
echo ""
echo "Flow has ended."
