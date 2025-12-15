pipeline {
  agent any

  environment {
    AWS_REGION    = "us-east-1"
    CLUSTER_NAME  = "depi-eks"
    ECR_REPO      = "movie-manager"
    K8S_NAMESPACE = "default"
    K8S_PATH      = "k8s"
    DEPLOYMENT    = "movie-manager"   // لو عندك Deployment بنفس الاسم
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: 'main', url: 'https://github.com/saifelmasry1/Movie-Manager.git'
      }
    }

    stage('Prepare Vars') {
      steps {
        script {
          env.ACCOUNT_ID = sh(returnStdout: true, script: "aws sts get-caller-identity --query Account --output text").trim()
          env.ECR_REGISTRY = "${env.ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
          env.IMAGE = "${env.ECR_REGISTRY}/${env.ECR_REPO}:latest"
          echo "IMAGE = ${env.IMAGE}"
        }
      }
    }

    stage('Build Image') {
      steps {
        sh '''
          set -e
          docker build -t movie-manager:latest .
        '''
      }
    }

    stage('ECR Login + Push') {
      steps {
        sh '''
          set -e
          aws ecr get-login-password --region "$AWS_REGION" \
            | docker login --username AWS --password-stdin "$ECR_REGISTRY"

          # (اختياري) لو الريبو مش موجود يتعمل تلقائي
          aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 \
            || aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION" >/dev/null

          docker tag movie-manager:latest "$IMAGE"
          docker push "$IMAGE"
        '''
      }
    }

    stage('Deploy to EKS') {
      steps {
        sh '''
          set -e
          aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

          kubectl apply -f "$K8S_PATH" -n "$K8S_NAMESPACE"

          # Restart deployment لو موجود
          kubectl rollout restart "deployment/$DEPLOYMENT" -n "$K8S_NAMESPACE" >/dev/null 2>&1 || true
          kubectl rollout status "deployment/$DEPLOYMENT" -n "$K8S_NAMESPACE" --timeout=3m >/dev/null 2>&1 || true
        '''
      }
    }
  }

  post {
    success { echo "Done ✅" }
    failure { echo "Failed ❌" }
    always  {
      sh 'docker system prune -af >/dev/null 2>&1 || true'
    }
  }
}
