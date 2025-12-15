pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  // No triggers here on purpose.
  // You will click "Build Now" manually from the Jenkins UI.

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS Region (e.g. us-east-1)')
    string(name: 'EKS_CLUSTER_NAME', defaultValue: 'depi-eks', description: 'EKS cluster name')
    string(name: 'ECR_REPOSITORY', defaultValue: 'movie-manager', description: 'ECR repo name (will be created if missing)')
    string(name: 'DOCKER_CONTEXT', defaultValue: '.', description: 'Docker build context path')
    string(name: 'DOCKERFILE', defaultValue: 'Dockerfile', description: 'Dockerfile path')
    booleanParam(name: 'DEPLOY_TO_EKS', defaultValue: false, description: 'If true, deploy manifests to the cluster after pushing the image')
    string(name: 'K8S_MANIFEST_PATH', defaultValue: 'k8s', description: 'Path to Kubernetes manifests (folder)')
    string(name: 'K8S_NAMESPACE', defaultValue: 'default', description: 'Namespace to deploy to')
    string(name: 'K8S_DEPLOYMENT', defaultValue: 'movie-manager', description: 'Deployment name to update (optional)')
    string(name: 'K8S_CONTAINER', defaultValue: 'movie-manager', description: 'Container name in the deployment (optional)')
  }

  environment {
    AWS_DEFAULT_REGION = "${params.AWS_REGION}"
  }

  stages {
    stage('Prepare') {
      steps {
        script {
          env.AWS_ACCOUNT_ID = sh(
            returnStdout: true,
            script: "aws sts get-caller-identity --query Account --output text"
          ).trim()

          env.GIT_SHA = sh(returnStdout: true, script: "git rev-parse --short=12 HEAD").trim()
          env.ECR_REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${params.AWS_REGION}.amazonaws.com"
          env.IMAGE_URI = "${env.ECR_REGISTRY}/${params.ECR_REPOSITORY}:${env.GIT_SHA}"

          echo "AWS_ACCOUNT_ID = ${env.AWS_ACCOUNT_ID}"
          echo "IMAGE_URI      = ${env.IMAGE_URI}"
        }
      }
    }

    stage('ECR Login + Ensure Repo') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail

          aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" --region "${AWS_REGION}" >/dev/null 2>&1 \
            || aws ecr create-repository --repository-name "${ECR_REPOSITORY}" --image-scanning-configuration scanOnPush=true --region "${AWS_REGION}" >/dev/null

          aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
        '''
      }
    }

    stage('Build Image') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail

          if [ ! -f "${DOCKERFILE}" ]; then
            echo "ERROR: Dockerfile not found at ${DOCKERFILE}"
            echo "Fix DOCKERFILE parameter (or add Dockerfile to repo)."
            exit 1
          fi

          docker build -f "${DOCKERFILE}" -t "${IMAGE_URI}" "${DOCKER_CONTEXT}"
        '''
      }
    }

    stage('Push Image') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          docker push "${IMAGE_URI}"
        '''
      }
    }

    stage('Deploy to EKS (manual toggle)') {
      when { expression { return params.DEPLOY_TO_EKS } }
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail

          aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"

          if [ -d "${K8S_MANIFEST_PATH}" ]; then
            if [ -f "${K8S_MANIFEST_PATH}/kustomization.yaml" ]; then
              kubectl apply -k "${K8S_MANIFEST_PATH}"
            else
              kubectl apply -f "${K8S_MANIFEST_PATH}"
            fi
          else
            echo "ERROR: K8S_MANIFEST_PATH not found: ${K8S_MANIFEST_PATH}"
            exit 1
          fi

          kubectl -n "${K8S_NAMESPACE}" get deploy "${K8S_DEPLOYMENT}" >/dev/null 2>&1 && \
            kubectl -n "${K8S_NAMESPACE}" set image "deployment/${K8S_DEPLOYMENT}" "${K8S_CONTAINER}=${IMAGE_URI}" --record || true

          kubectl -n "${K8S_NAMESPACE}" rollout status "deployment/${K8S_DEPLOYMENT}" --timeout=3m || true
        '''
      }
    }
  }

  post {
    always {
      sh 'docker system prune -af >/dev/null 2>&1 || true'
    }
  }
}
