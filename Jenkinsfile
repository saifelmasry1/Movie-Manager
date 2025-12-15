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
    booleanParam(name: 'RUN_SEED', defaultValue: true, description: 'Run Mongo seed job after deploy')
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

          echo "ACCOUNT_ID   = ${env.ACCOUNT_ID}"
          echo "GIT_SHA      = ${env.GIT_SHA}"
          echo "ECR_FRONTEND = ${env.ECR_FRONTEND}"
          echo "ECR_BACKEND  = ${env.ECR_BACKEND}"
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

    stage('Deploy App to EKS') {
      steps {
        sh '''
          set -e

          # Apply manifests
          kubectl apply -n "$K8S_NAMESPACE" -f k8s/

          # Update images (explicit container names) + fallback wildcard
          kubectl -n "$K8S_NAMESPACE" set image deployment/movie-manager-frontend movie-manager-frontend=${ECR_FRONTEND}:${GIT_SHA} \
            || kubectl -n "$K8S_NAMESPACE" set image deployment/movie-manager-frontend *=${ECR_FRONTEND}:${GIT_SHA}

          kubectl -n "$K8S_NAMESPACE" set image deployment/movie-manager-backend movie-manager-backend=${ECR_BACKEND}:${GIT_SHA} \
            || kubectl -n "$K8S_NAMESPACE" set image deployment/movie-manager-backend *=${ECR_BACKEND}:${GIT_SHA}

          # Wait for rollouts
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/mongo --timeout=10m || true
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/movie-manager-frontend --timeout=10m
          kubectl -n "$K8S_NAMESPACE" rollout status deployment/movie-manager-backend  --timeout=10m

          kubectl -n "$K8S_NAMESPACE" get pods -o wide || true
          kubectl -n "$K8S_NAMESPACE" get svc -o wide  || true
          kubectl -n "$K8S_NAMESPACE" get ingress -o wide || true
        '''
      }
    }

    stage('Seed Mongo') {
      when { expression { return params.RUN_SEED } }
      steps {
        sh '''
          set -e

          kubectl -n "$K8S_NAMESPACE" delete job mongo-seed-movies --ignore-not-found=true
          kubectl -n "$K8S_NAMESPACE" apply -f k8s/mongo-seed-configmap.yaml
          kubectl -n "$K8S_NAMESPACE" apply -f k8s/mongo-seed-job.yaml
          kubectl -n "$K8S_NAMESPACE" wait --for=condition=complete job/mongo-seed-movies --timeout=10m

          echo "Seed done."
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
