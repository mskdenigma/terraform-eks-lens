#!/bin/bash

# Check if DOIT_API_KEY is set
if [ -z "${DOIT_API_KEY}" ]; then
  echo "DOIT_API_KEY is not set"
  read -p "Enter DOIT_API_KEY: " DOIT_API_KEY
fi

# check if terraform init is done
if [ ! -d ".terraform" ]; then
  echo "Terraform init not done"
  terraform init
fi

# check if terraform.tfvars is present
if [ ! -f "doit-eks-lens.tfvars" ]; then
  echo "doit-eks-lens.tfvars is not present"

  if  [ -z "${ACCOUNT_ID}" ]; then
    read -p "Enter AWS account_id: " ACCOUNT_ID
  fi

  if  [ -z "${REGION}" ]; then
    read -p "Enter AWS region: " REGION
  fi

  if  [ -z "${CLUSTER_NAME}" ]; then
    read -p "Enter AWS cluster_name: " CLUSTER_NAME
  fi
  # download doit-eks-lens.tfvars
  curl -o doit-eks-lens.tfvars -X POST -H "Authorization: Bearer ${DOIT_API_KEY}" -H "Content-Type: application/json" -d "{\"account_id\": \"${ACCOUNT_ID}\",\"region\": \"${REGION}\",\"cluster_name\": \"${CLUSTER_NAME}\"}" http://localhost:8086/doit-eks-lens-tfvars
fi

# check if ec2_cluster is true
ec2_cluster=false
if [ $(cat doit-eks-lens.tfvars|grep ec2_cluster|grep -c true) -eq 1 ]; then
  ec2_cluster=true
fi

# if it's a regular EKS cluster then add cluster_oidc_issuer_url to terraform.tfvars if its not present
if [ $ec2_cluster = false ]; then
  # check if terraform.tfvars is present
  if [ ! -f "terraform.tfvars" ]; then
    echo "terraform.tfvars is not present"

    if  [ -z "${CLUSTER_OIDC_ISSUER_URL}" ]; then
      read -p "Enter OIDC Identity issuer URL for the cluster: " CLUSTER_OIDC_ISSUER_URL
    fi

    printf "cluster_oidc_issuer_url = \"${CLUSTER_OIDC_ISSUER_URL}\"\n" >> terraform.tfvars
  else
    # check if cluster_oidc_issuer_url is present
    if [ $(cat terraform.tfvars|grep -c cluster_oidc_issuer_url) -eq 0 ]; then
      echo "terraform.tfvars is present but does not have cluster_oidc_issuer_url"

      if  [ -z "${CLUSTER_OIDC_ISSUER_URL}" ]; then
      read -p "Enter OIDC Identity issuer URL for the cluster: " CLUSTER_OIDC_ISSUER_URL
      fi

      printf "\ncluster_oidc_issuer_url = \"${CLUSTER_OIDC_ISSUER_URL}\"\n" >> terraform.tfvars
    fi
  fi
else 
  # if it's an EC2 cluster then we don't need cluster_oidc_issuer_url
  if [ ! -f "terraform.tfvars" ]; then
    touch terraform.tfvars
  fi
fi

# check if terraform plan has changes
terraform plan -input=false -no-color -detailed-exitcode -var-file=<(cat doit-eks-lens.tfvars terraform.tfvars) 
terraformHasChanges=$?

# check if terraform plan was successful and has changes then apply
if [ $terraformHasChanges -eq 2 ]; then
  terraform apply -var-file=<(cat doit-eks-lens.tfvars terraform.tfvars) -auto-approve # eks-lens.plan

  # check if terraform apply was successful
  if [ $? -eq 0 ]; then
      echo "Successfully applied terraform configuration"

      account_id=$(terraform output account_id)
      region=$(terraform output region)
      cluster_name=$(terraform output cluster_name)
      deployment_id=$(terraform output deployment_id)

      echo "Validating s3 bucket data"

      curl -X POST -H "Authorization: Bearer ${DOIT_API_KEY}" -H "Content-Type: application/json" -d "{\"account_id\": ${account_id},\"region\": ${region},\"cluster_name\": ${cluster_name}, \"deployment_id\": ${deployment_id}}" http://localhost:8086/terraform-validate
  fi
else
  echo "No changes to apply"
fi