#!/bin/sh

if [ -z ${PLUGIN_CLUSTER_ARN} ]; then
    echo "EKS_CLUSTER (Name of EKS cluster) must be defined."
    exit 1
fi

if [ -z ${PLUGIN_IAM_ROLE_ARN} ]; then
    echo "IAM_ROLE_ARN (ARN of the IAM role with cluster deploy/management perms) must be defined."
    exit 1
fi

if [ -z ${PLUGIN_MANIFEST} ]; then
    echo "MANIFEST_FILE (Manifest filepath to be applied) must be defined."
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


CLUSTER_NAME=$(echo "${PLUGIN_CLUSTER_ARN}" | cut -d"/" -f2)

echo "Fetching the authentication token..."
KUBERNETES_TOKEN=$(aws-iam-authenticator token -i $CLUSTER_NAME -r $PLUGIN_IAM_ROLE_ARN | jq -r .status.token)

if [ -z $KUBERNETES_TOKEN ]; then
    echo "Unable to obtain Kubernetes token - check Drone's IAM permissions"
    echo "Maybe it cannot assume the ${PLUGIN_IAM_ROLE_ARN} role?"
    exit 1
fi


echo "Fetching the EKS cluster information..."
EKS_URL=$(aws eks describe-cluster --name $CLUSTER_NAME | jq -r .cluster.endpoint)
EKS_CA=$(aws eks describe-cluster --name $CLUSTER_NAME | jq -r .cluster.certificateAuthority.data)

if [ -z $EKS_URL ] || [ -z $EKS_CA ]; then
    echo "Unable to obtain EKS cluster information - check Drone's EKS API permissions"
    exit 1
fi


echo "--------------------------------------------------"
echo "Cluster endpoint: $EKS_URL"
echo "Cluster certificate: $EKS_CA"
echo "--------------------------------------------------"


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
  name: ${PLUGIN_CLUSTER_ARN}

contexts:
- context:
    cluster: ${PLUGIN_CLUSTER_ARN}
    user: ${PLUGIN_CLUSTER_ARN}
  name: ${PLUGIN_CLUSTER_ARN}

current-context: ${PLUGIN_CLUSTER_ARN}

users:
- name: ${PLUGIN_CLUSTER_ARN}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
      - token
      - -i
      - $CLUSTER_NAME
EOF


echo "--------------------------------------------------"
echo "Configuration file:\n"
cat ~/.kube/config
echo "--------------------------------------------------"


echo "Exporting configuration path..."
export KUBECONFIG=$KUBECONFIG:~/.kube/config


echo "Exporting credentials..."
export AWS_ACCESS_KEY_ID=${PLUGIN_ACCESS_KEY}
export AWS_SECRET_ACCESS_KEY=${PLUGIN_SECRET_KEY}


kubectl get svc --v=10


echo "Applying the new manifest..."
cat ${PLUGIN_MANIFEST} | kubectl apply -f -
