// Configuration for API URL
// In dev: default http://localhost:5000
// In prod: default /api (same host as frontend / ALB)
const DEFAULT_API_BASE_URL = import.meta.env.DEV
  ? "http://localhost:5000"
  : "/api";

export const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE_URL;
