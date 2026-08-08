export type AppEnvironment = "local" | "dev" | "prod";

export function appEnvironment(): AppEnvironment {
  const value = process.env.NEXT_PUBLIC_APP_ENV ?? process.env.APP_ENV;
  if (value === "dev" || value === "prod" || value === "local") return value;
  return "local";
}

export function showProtocolDetails(): boolean {
  return appEnvironment() !== "prod";
}
