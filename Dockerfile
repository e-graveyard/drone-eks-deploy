FROM alpine:3.8

# Install base utilities
RUN apk --no-cache add curl ca-certificates bash jq groff less python py-pip py-setuptools
RUN pip --no-cache-dir install awscli

# Download the Amazon blessed utilities as per:
# https://docs.aws.amazon.com/eks/latest/userguide/configure-kubectl.html
ADD https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/kubectl /usr/bin/kubectl
ADD https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/aws-iam-authenticator /usr/bin/aws-iam-authenticator
RUN chmod +x /usr/bin/kubectl /usr/bin/aws-iam-authenticator

# Install the Drone plugin script
COPY update.sh /bin/

ENTRYPOINT ["/bin/sh"]
CMD ["/bin/update.sh"]
