"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import * as React from "react";

import { listProEntitlements } from "@/lib/api";
import { cn } from "@/lib/utils";

const items = [
  { href: "/app", label: "Scheduler", exact: true },
  { href: "/app/calendar", label: "Calendar", exact: false },
  { href: "/app/analytics", label: "Analytics", exact: false },
  { href: "/app/account", label: "Account & teams", exact: false },
] as const;

export function AuthenticatedNav({ className }: { className?: string }) {
  const pathname = usePathname();
  const [showAdmin, setShowAdmin] = React.useState(false);

  React.useEffect(() => {
    let cancelled = false;
    void listProEntitlements()
      .then(() => {
        if (!cancelled) setShowAdmin(true);
      })
      .catch(() => {
        if (!cancelled) setShowAdmin(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <nav
      aria-label="Skej workspace"
      className={cn(
        "flex flex-wrap items-center gap-1 rounded-[1.25rem] border border-border bg-card/90 p-1.5 text-sm font-black shadow-sm",
        className
      )}
    >
      {items.map((item) => {
        const current = item.exact ? pathname === item.href : pathname.startsWith(item.href);
        return (
          <Link
            aria-current={current ? "page" : undefined}
            className={cn(
              "min-h-10 rounded-xl px-3 py-2 transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
              current && "bg-primary text-primary-foreground"
            )}
            href={item.href}
            key={item.href}
          >
            {item.label}
          </Link>
        );
      })}
      {showAdmin ? (
        <Link
          aria-current={pathname.startsWith("/app/admin") ? "page" : undefined}
          className={cn(
            "min-h-10 rounded-xl px-3 py-2 transition hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
            pathname.startsWith("/app/admin") && "bg-primary text-primary-foreground"
          )}
          href="/app/admin"
        >
          Admin
        </Link>
      ) : null}
    </nav>
  );
}
