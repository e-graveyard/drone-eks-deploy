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
    - [k8s](#k8s)
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
image and push it at your registry:

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

`drone-eks-deploy` requires a set of [AWS credentials][aws-cred] (the access
and secret keys). These credentials must have enough permissions to perform the
desired changes at the EKS cluster.

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
`drone-eks-deploy` requires the ARN (Amazon Resource Name) of the EKS node
role. The IAM role typically comprises the following policies:

- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`

This role (the EKS node role) must be able to be assumed by the Drone agent. In
AWS, this means that the EC2 instance that runs Drone must have a role allowing
the "assume role" of the EKS node role.

Supposing a EKS node role named "`eks-node-role`" on an account with id
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
resource (namely, the EC2 instance that runs the Drone agent) and the account
itself to assume the role (the EKS node role).

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

Finally, the Drone agent must be able to describe (get information about) the
specified EKS cluster (at the `CLUSTER` parameter).

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


## Similar projects

- [`sailthru/sailthru-drone-eks`](https://github.com/sailthru/sailthru-drone-eks)
- [`honestbee/drone-kubernetes`](https://github.com/honestbee/drone-kubernetes)
- [`ipedrazas/drone-helm`](https://github.com/ipedrazas/drone-helm)
