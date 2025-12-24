  // apiConfig.js

  // 1. رابط التطوير المحلي
  const DEV_API = "http://localhost:5000/api";

  // 2. رابط الإنتاج (مسار نسبي ليتم توجيهه عبر Ingress)
  const PROD_API = "/api";

  // 3. متغير البيئة الممرر من Docker/Vite (إن وجد)
  const ENV_API = import.meta.env.VITE_API_BASE_URL;

  /**
   * import.meta.env.DEV:
   * - تكون true عند تشغيل السيرفر محلياً (npm run dev)
   * - تكون false عند بناء المشروع (npm run build)
   */
  export const API_BASE_URL = ENV_API || (import.meta.env.DEV ? DEV_API : PROD_API);
