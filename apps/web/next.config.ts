import type { NextConfig } from "next";
import path from "node:path";

const localApiBase = "http://127.0.0.1:8080";
const devApiBase = "https://api.testing.skej.at";
const hostedApiBase = "https://api.skej.at";
const appEnv = process.env.NEXT_PUBLIC_APP_ENV ?? process.env.APP_ENV ?? "local";
const apiBase =
  process.env.SKEJ_API_URL ??
  (process.env.NODE_ENV === "development"
    ? localApiBase
    : appEnv === "dev"
      ? devApiBase
      : hostedApiBase);

const nextConfig: NextConfig = {
  output: "standalone",
  outputFileTracingRoot: path.resolve(process.cwd(), "../.."),
  allowedDevOrigins: ["127.0.0.1"],
  env: {
    NEXT_PUBLIC_APP_ENV: appEnv,
  },
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
