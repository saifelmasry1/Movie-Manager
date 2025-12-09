
// Configuration for API URL
// In dev: http://localhost:5000/api
// In prod (EKS): /api  (ALB + Ingress هيكمّلوا الباقي)
const DEFAULT_API_BASE_URL = import.meta.env.DEV
  ? "http://localhost:5000/api"
  : "/api";

export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE_URL;
