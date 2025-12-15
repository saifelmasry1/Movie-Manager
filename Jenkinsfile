pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '15'))
  }

  parameters {
    string(name: 'AWS_REGION',    defaultValue: 'us-east-1', description: 'AWS Region')
    string(name: 'CLUSTER_NAME',  defaultValue: 'depi-eks',  description: 'EKS Cluster Name')
    string(name: 'K8S_NAMESPACE', defaultValue: 'default',   description: 'Namespace for app manifests')
  }

  environment {
    AWS_REGION    = "${params.AWS_REGION}"
    CLUSTER_NAME  = "${params.CLUSTER_NAME}"
    K8S_NAMESPACE = "${params.K8S_NAMESPACE}"

    TF_IN_AUTOMATION = "true"
    TF_INPUT         = "0"
  }

  stages {

    stage('Prepare Vars') {
      steps {
        script {
          env.ACCOUNT_ID = sh(returnStdout: true, script: 'aws sts get-caller-identity --query Account --output text').trim()
          env.GIT_SHA    = sh(returnStdout: true, script: 'git rev-parse --short=12 HEAD').trim()

          env.ECR_REGISTRY = "${env.ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
          env.ECR_FRONTEND = "${env.ECR_REGISTRY}/movie-manager-frontend"
          env.ECR_BACKEND  = "${env.ECR_REGISTRY}/movie-manager-backend"

          env.EBS_CSI_ROLE_NAME  = "${env.CLUSTER_NAME}-ebs-csi-irsa"
          env.EBS_CSI_POLICY_ARN = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

          echo "ACCOUNT_ID   = ${env.ACCOUNT_ID}"
          echo "GIT_SHA      = ${env.GIT_SHA}"
          echo "ECR_FRONTEND = ${env.ECR_FRONTEND}"
          echo "ECR_BACKEND  = ${env.ECR_BACKEND}"
          echo "EBS_CSI_ROLE = ${env.EBS_CSI_ROLE_NAME}"
        }
      }
    }

    stage('Build Docker Images') {
      steps {
        sh '''
          set -e
          unset DOCKER_CONTEXT || true

          echo "Building Frontend..."
          docker build -t movie-manager-frontend:${GIT_SHA} -f app/frontend/Dockerfile app/frontend

          echo "Building Backend..."
          docker build -t movie-manager-backend:${GIT_SHA} -f app/backend/Dockerfile app/backend
        '''
      }
    }

    stage('AWS ECR Login + Ensure Repos') {
      steps {
        sh '''
          set -e
          unset DOCKER_CONTEXT || true

          aws ecr describe-repositories --region "$AWS_REGION" --repository-names "movie-manager-frontend" >/dev/null 2>&1 \
            || aws ecr create-repository --region "$AWS_REGION" --repository-name "movie-manager-frontend" >/dev/null

          aws ecr describe-repositories --region "$AWS_REGION" --repository-names "movie-manager-backend" >/dev/null 2>&1 \
            || aws ecr create-repository --region "$AWS_REGION" --repository-name "movie-manager-backend" >/dev/null

          aws ecr get-login-password --region "$AWS_REGION" \
            | docker login --username AWS --password-stdin "$ECR_REGISTRY"
        '''
      }
    }

    stage('Tag & Push Images') {
      steps {
        sh '''
          set -e
          unset DOCKER_CONTEXT || true

          docker tag movie-manager-frontend:${GIT_SHA} ${ECR_FRONTEND}:${GIT_SHA}
          docker tag movie-manager-backend:${GIT_SHA}  ${ECR_BACKEND}:${GIT_SHA}

          docker push ${ECR_FRONTEND}:${GIT_SHA}
          docker push ${ECR_BACKEND}:${GIT_SHA}

          docker tag movie-manager-frontend:${GIT_SHA} ${ECR_FRONTEND}:latest
          docker tag movie-manager-backend:${GIT_SHA}  ${ECR_BACKEND}:latest

          docker push ${ECR_FRONTEND}:latest
          docker push ${ECR_BACKEND}:latest
        '''
      }
    }

    stage('Configure kubeconfig') {
      steps {
        sh '''
          set -e
          aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
          kubectl get nodes -o wide
        '''
      }
    }

    stage('Install AWS Load Balancer Controller (ALB)') {
      steps {
        sh '''
          set -e
          chmod +x infra/addons/aws-lbc-cli.sh

          VPC_ID="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
            --query "cluster.resourcesVpcConfig.vpcId" --output text)"

          bash infra/addons/aws-lbc-cli.sh \
            --cluster "$CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --vpc-id "$VPC_ID" \
            --no-sample

          kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=10m
          kubectl get ingressclass alb || true
        '''
      }
    }

    stage('Terraform: Monitoring Addons (EBS CSI + gp3 default)') {
      steps {
        sh '''
          set -e
          cd infra/monitoring

          terraform fmt -recursive
          terraform init -upgrade

          # Import existing namespace (prevents "namespace already exists")
          terraform import kubernetes_namespace_v1.monitoring monitoring >/dev/null 2>&1 || true

          # Import existing IAM role/attachment if they already exist
          terraform import aws_iam_role.ebs_csi_irsa "${EBS_CSI_ROLE_NAME}" >/dev/null 2>&1 || true
          terraform import aws_iam_role_policy_attachment.ebs_csi "${EBS_CSI_ROLE_NAME}/${EBS_CSI_POLICY_ARN}" >/dev/null 2>&1 || true

          # Import EBS CSI addon if it already exists in EKS (prevents 409 Addon already exists)
          ADDON_NAME="aws-ebs-csi-driver"
          if ! terraform state show aws_eks_addon.ebs_csi >/dev/null 2>&1; then
            if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name "$ADDON_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
              terraform import aws_eks_addon.ebs_csi "${CLUSTER_NAME}:${ADDON_NAME}" >/dev/null 2>&1 || true
            fi
          fi

          # (Optional but safe) Import storage class if it already exists
          terraform import kubernetes_storage_class_v1.gp3 gp3 >/dev/null 2>&1 || true

          # If the role is tainted from a previous failure, untaint it so no delete/recreate happens
          terraform untaint aws_iam_role.ebs_csi_irsa >/dev/null 2>&1 || true

          terraform apply -auto-approve

          kubectl get sc || true
          terraform output || true
        '''
      }
    }

    stage('Deploy App to EKS + Seed Mongo') {
      steps {
        sh '''
          set -e

          kubectl apply -n "$K8S_NAMESPACE" -f k8s/

          # Update images safely (use explicit container names)
          kubectl -n "$K8S_NAMESPACE" set image deployment/movie-manager-frontend movie-manager-frontend=${ECR_FRONTEND}:${GIT_SHA}
          kubectl -n "$K8S_NAMESPACE" set image deployment/movie-manager-backend  movie-manager-backend=${ECR_BACKEND}:${GIT_SHA}

          # Ensure mongo is ready before seeding
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/mongo --timeout=10m

          # Re-run seed job
          kubectl -n "$K8S_NAMESPACE" delete job mongo-seed-movies --ignore-not-found=true
          kubectl -n "$K8S_NAMESPACE" apply -f k8s/mongo-seed-configmap.yaml
          kubectl -n "$K8S_NAMESPACE" apply -f k8s/mongo-seed-job.yaml
          kubectl -n "$K8S_NAMESPACE" wait --for=condition=complete job/mongo-seed-movies --timeout=10m

          # Wait for app rollouts
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/movie-manager-frontend --timeout=6m
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/movie-manager-backend  --timeout=6m

          kubectl -n "$K8S_NAMESPACE" get pods -o wide || true
          kubectl -n "$K8S_NAMESPACE" get ingress -o wide || true
          kubectl -n "$K8S_NAMESPACE" get ingress movie-manager-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\\n"}' || true
        '''
      }
    }
  }

  post {
    always {
      sh 'docker system prune -af >/dev/null 2>&1 || true'
    }
    success {
      echo "Deployment Completed Successfully ✔"
    }
    failure {
      echo "Deployment Failed ❌"
    }
  }
}
