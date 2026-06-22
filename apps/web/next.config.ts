import type { NextConfig } from "next";
import path from "node:path";

const localApiBase = "http://127.0.0.1:8080";
const hostedApiBase = "https://skej-at-prod-gateway.fly.dev";
const apiBase =
  process.env.SKEJ_API_URL ??
  (process.env.NODE_ENV === "development" ? localApiBase : hostedApiBase);

const nextConfig: NextConfig = {
  allowedDevOrigins: ["127.0.0.1"],
  turbopack: {
    root: path.resolve(process.cwd(), "../.."),
  },
  async rewrites() {
    return [
      {
        source: "/oauth/:path*",
        destination: `${apiBase}/oauth/:path*`,
      },
      {
        source: "/v1/:path*",
        destination: `${apiBase}/v1/:path*`,
      },
    ];
  },
};

export default nextConfig;
