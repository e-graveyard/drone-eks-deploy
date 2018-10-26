#!/bin/sh

if [ -z ${PLUGIN_CLUSTER} ]; then
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


echo "Fetching the authentication token..."
KUBERNETES_TOKEN=$(aws-iam-authenticator token -i $PLUGIN_CLUSTER -r $PLUGIN_IAM_ROLE_ARN | jq -r .status.token)

if [ -z $KUBERNETES_TOKEN ]; then
    echo "Unable to obtain Kubernetes token - check Drone's IAM permissions"
    echo "Maybe it cannot assume the ${PLUGIN_IAM_ROLE_ARN} role?"
    exit 1
fi


echo "Fetching the EKS cluster information..."
EKS_URL=$(aws eks describe-cluster --name ${PLUGIN_CLUSTER} | jq -r .cluster.endpoint)
EKS_CA=$(aws eks describe-cluster --name ${PLUGIN_CLUSTER} | jq -r .cluster.certificateAuthority.data)

if [ -z $EKS_URL ] || [ -z $EKS_CA ]; then
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
  name: eks_${PLUGIN_CLUSTER}

contexts:
- context:
    cluster: eks_${PLUGIN_CLUSTER}
    user: eks_${PLUGIN_CLUSTER}
  name: eks_${PLUGIN_CLUSTER}

current-context: eks_${PLUGIN_CLUSTER}

users:
- name: eks_${PLUGIN_CLUSTER}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - "token"
        - "-i"
        - ${PLUGIN_CLUSTER}
        - -r
        - ${PLUGIN_IAM_ROLE_ARN}
EOF


echo "Applying the new manifest..."
cat ${PLUGIN_MANIFEST} | kubectl apply -f -
