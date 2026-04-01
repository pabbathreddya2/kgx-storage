#!/bin/bash
# Create IAM Role for Service Account (IRSA) for kgx-storage

set -e

# Configuration - UPDATE THESE VALUES
CLUSTER_NAME="${CLUSTER_NAME:-your-eks-cluster-name}"
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ROLE_NAME="kgx-storage-s3-role"
NAMESPACE="kgx-storage"
SERVICE_ACCOUNT="kgx-storage-sa"

echo "=== Creating IAM Role for Service Account (IRSA) ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Role Name: $ROLE_NAME"
echo ""

# Get OIDC provider for the EKS cluster
echo "Getting OIDC provider for cluster..."
OIDC_PROVIDER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
OIDC_ID=$(echo "$OIDC_PROVIDER" | cut -d'/' -f4)

echo "OIDC Provider: $OIDC_PROVIDER"
echo "OIDC ID: $OIDC_ID"
echo ""

# Create trust policy
echo "Creating trust policy..."
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create IAM role
echo "Creating IAM role..."
if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    echo "Role $ROLE_NAME already exists. Updating trust policy..."
    aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document file:///tmp/trust-policy.json
else
    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file:///tmp/trust-policy.json
    echo "Role $ROLE_NAME created."
fi

# Attach S3 policy
echo "Creating and attaching S3 access policy..."
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-policy"

# Create inline policy for S3 access
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "S3ReadAccess" --policy-document file://kubernetes/iam-role-policy.json

echo ""
echo "=== IAM Role Created Successfully ==="
echo "Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
echo "Update the following in kubernetes/serviceaccount.yaml:"
echo "  eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo ""
