import { cn } from "@/lib/utils";

type AppEnv = "local" | "dev" | "prod";

const envConfig: Record<
  AppEnv,
  {
    label: string;
    description: string;
    className: string;
  }
> = {
  local: {
    label: "Local",
    description: "Running against your local workspace.",
    className: "border-ring/40 bg-secondary text-secondary-foreground",
  },
  dev: {
    label: "Dev",
    description: "Connected to the shared development environment.",
    className: "border-accent/60 bg-accent text-accent-foreground",
  },
  prod: {
    label: "Prod",
    description: "Production environment.",
    className: "border-primary/40 bg-primary text-primary-foreground",
  },
};

function normalizeEnv(value: string | undefined): AppEnv {
  if (value === "dev" || value === "prod" || value === "local") return value;
  return "local";
}

export function EnvironmentBanner() {
  const env = normalizeEnv(process.env.NEXT_PUBLIC_APP_ENV ?? process.env.APP_ENV);
  const config = envConfig[env];

  return (
    <div
      className={cn(
        "sticky top-0 z-50 flex h-9 items-center justify-center border-b px-4 text-center text-xs font-black shadow-[0_8px_24px_rgba(35,31,32,0.08)]",
        config.className
      )}
    >
      <span className="mr-2 rounded-full bg-background/25 px-2 py-0.5 uppercase tracking-normal">
        {config.label}
      </span>
      <span>{config.description}</span>
    </div>
  );
}
