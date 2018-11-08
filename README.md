# Drone EKS Deploy

`drone-eks-deploy` is a [Drone-CI][drone] plugin that allows you to apply Kubernetes
manifests to [EKS][eks]-based clusters.

[drone]: https://drone.io
[eks]: https://aws.amazon.com/eks


## Table of Contents

- [Usage](#usage)
    - [Statement](#statement)
    - [Image](#image)
    - [Parameters](#parameters)
    - [Secrets](#secrets)
- [Permissions](#permissions)
    - [aws](#aws)
        - [ConfigMap](#configmap)
        - [RBAC](#rbac)
- [Similar Projects](#similar-projects)


## Usage

### Statement

This is a typical statement using the plugin:

```yaml
pipeline:
  deploy:
    image: caian/drone-eks-plugin
    cluster: arn:aws:eks:us-east-1:001122334455:cluster/cluster-name
    node_role: arn:aws:iam::001122334455:role/eks-node-role
    manifest: k8s/deployment.yml
    secrets: [ aws_access_key, aws_secret_key ]
    when:
      branch: master
      event: tag
```


### Image

The image is publicly available at the Docker Hub in
[caian/drone-eks-plugin][plugin-docker]. Alternatively, you can build your own
image and push it to your registry:

```sh
$ docker build -t drone-eks-deploy .
```

[plugin-docker]: https://hub.docker.com/r/caian/drone-eks-plugin/


### Parameters

| Parameter    | Required? | Description                 |
|--------------|-----------|-----------------------------|
| `CLUSTER`    | Yes       | The EKS cluster's ARN.      |
| `MANIFEST`   | Yes       | The k8s manifest file path. |
| `NODE_ROLE`  | Yes       | The k8s node AMI role ARN.  |
| `AWS_REGION` | No        | The EKS cluster's region.   |

The `AWS_REGION` parameter will be set by default to the Drone's agent region.


### Secrets

`drone-eks-deploy` requires a set of [AWS credentials][aws-cred] (_the access
and secret keys_). These credentials __must have enough permissions__ to
perform the desired changes at the EKS cluster.

The access and secret keys can be injected into the container via [Drone's
secrets][drone-secrets]. It is important to notice that the secrets must be
named according to the [environment variables the `awscli` looks
for][awscli-env]. If you manage multiple AWS credentials within Drone-CI, you
can use alternate names. Example:

```yaml
pipeline:
  deploy-staging:
    secrets:
      - aws_access_key: stg_aws_access_key
        aws_secret_key: stg_aws_secret_key

  deploy-production:
    secrets:
      - aws_access_key: prd_aws_access_key
        aws_secret_key: prd_aws_secret_key
```

[aws-cred]: https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html
[drone-secrets]: http://docs.drone.io/manage-secrets
[awscli-env]: https://docs.aws.amazon.com/cli/latest/userguide/cli-environment.html


## Permissions

### aws

As stated at the [parameters](#parameters) section of this document,
`drone-eks-deploy` requires the ARN (_Amazon Resource Name_) of the EKS node
role. The IAM role typically comprises the following policies:

- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`

This role (_the EKS node role_) __must be able to be assumed__ by the Drone
agent. In AWS, this means that the EC2 instance that runs Drone must have a
role allowing the "assume role" of the EKS node role.

Supposing an EKS node role named "`eks-node-role`" on an account with id
"`012345678901`", this could be accomplished by the following statement:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "arn:aws:iam::012345678901:role/eks-node-role"
        }
    ]
}
```

The EKS node role will in turn require a trust relationship, allowing the
resource (_namely, the EC2 instance that runs the Drone agent_) and the account
itself to assume the role (_the EKS node role_).

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::012345678901:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

Finally, the Drone agent must be able to describe (_get information about_) the
specified EKS cluster (_at the `CLUSTER` parameter_).

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "*"
        }
    ]
}
```


### k8s

Kubernetes must also be configured to allow changes received from the user
whose credentials are being used to perform the manifest appliances. One
approach to that is to bound an AWS user to a group. This group will be then
subject to a [RBAC declaration][rbac], allowing the user to perform the
necessary actions within the cluster.

To begin, provided you have the [`awscli` configured][awscli-conf], you can
easily update your [kubeconfig][kube-context] to add the context of your EKS
cluster.

```sh
$ aws eks update-kubeconfig --name cluster-name
```

It is important to notice, however, that the AWS user used in this approach
__must be the same__ that have originated the EKS cluster. In the examples
below, the "`k8sadmin`" user will be considered as the creator of the cluster.

[rbac]: https://kubernetes.io/docs/reference/access-authn-authz/rbac
[awscli-conf]: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html
[kube-context]: https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters


#### ConfigMap

The [`aws-auth` ConfigMap][kube-configmap] can be used in order to bound the
AWS user to a group.

```sh
$ kubectl edit -n kube-system configmap/aws-auth
```

Inside the configuration file, at the `data` key, include a `mapUsers` section.
At the example below, the `k8sadmin` user will be bound to the "`deployer`"
group.

```yaml
apiVersion: v1
data:
  mapUsers: |
    - userarn: arn:aws:iam::012345678901:user/k8sadmin
    username: k8sadmin
    groups:
      - deployer
```

The ConfigMap statement must contain the user name, as well it's ARN.

[kube-configmap]: https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html


#### RBAC

Once the user `k8admin` is now part of the group `deployer`, the RBAC must be
applied to the cluster to finish the authorization. The RBAC below is comprised
of two statements: a `ClusterRole` and a `ClusterRoleBinding`.

The `ClusterRole` statement defines a cluster role named `drone-deployer` with
a given list of authorized verbs and resources. The `ClusterRoleBinding`
statement then binds the `deployer` group to the `drone-deployer` role, thus,
authorizing the `k8sadmin` to apply the given manifest (_at the `MANIFEST`
parameter_).

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: drone-deployer
rules:
  - apiGroups:
      - extensions
    resources:
      - deployments
    verbs:
      - get
      - list
      - patch
      - update

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: drone-deployer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: drone-deployer
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: deployer
```


## Similar projects

- [`sailthru/sailthru-drone-eks`](https://github.com/sailthru/sailthru-drone-eks)
- [`honestbee/drone-kubernetes`](https://github.com/honestbee/drone-kubernetes)
- [`ipedrazas/drone-helm`](https://github.com/ipedrazas/drone-helm)
