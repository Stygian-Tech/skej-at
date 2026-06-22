import Image from "next/image";
import Link from "next/link";
import { ArrowRight, CalendarClock, Cloud, Database, Send } from "lucide-react";

import { OAuthLoginForm } from "@/components/OAuthLoginForm";
import { ThemeToggle } from "@/components/ThemeToggle";
import { Badge } from "@/components/ui/badge";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

const steps = [
  {
    title: "Connect",
    text: "OAuth keeps posting permission attached to the account you choose.",
    icon: Cloud,
  },
  {
    title: "Compose",
    text: "Write a post, thread, reply, quote, image draft, link card, tags, and labels.",
    icon: Send,
  },
  {
    title: "Schedule",
    text: "Skej stores the queue in SQLite and publishes when the worker sees it due.",
    icon: CalendarClock,
  },
];

export function LandingPage() {
  return (
    <main className="min-h-dvh overflow-hidden px-4 pb-16 pt-4 text-foreground sm:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-7xl flex-col gap-12">
        <header className="flex items-center justify-between gap-3 rounded-[2rem] border border-border bg-card/80 px-4 py-3 shadow-[0_20px_60px_rgba(70,52,70,0.1)] backdrop-blur">
          <Link className="flex items-center gap-3" href="/">
            <div className="grid size-12 place-items-center rounded-2xl bg-primary text-xl font-black text-primary-foreground shadow-[0_14px_30px_rgba(255,79,109,0.22)]">
              S
            </div>
            <div className="flex flex-col">
              <div className="flex items-center gap-2">
                <span className="text-2xl font-black text-primary">Skej</span>
                <Badge variant="sunny">Alpha</Badge>
              </div>
              <span className="text-xs font-bold text-muted-foreground">
                Schedule posts from your PDS
              </span>
            </div>
          </Link>
          <div className="flex items-center gap-2">
            <Link className={buttonVariants({ variant: "outline" })} href="/app">
              Open app
              <ArrowRight data-icon="inline-end" />
            </Link>
            <ThemeToggle />
          </div>
        </header>

        <section className="grid min-h-[calc(100dvh-12rem)] items-center gap-8 lg:grid-cols-[0.78fr_1.22fr]">
          <div className="flex flex-col gap-6">
            <div className="flex flex-col gap-4">
              <h1 className="max-w-xl text-5xl font-black leading-[0.95] text-foreground sm:text-6xl lg:text-7xl">
                Skej
              </h1>
              <p className="max-w-xl text-lg font-semibold leading-8 text-muted-foreground sm:text-xl">
                A bubbly little scheduler for Bluesky posts. Compose from your phone,
                queue it with OAuth, and let the Swift worker publish it on time.
              </p>
            </div>
            <div className="max-w-xl rounded-[1.75rem] border border-border bg-card/85 p-3 shadow-[0_24px_70px_rgba(70,52,70,0.12)]">
              <OAuthLoginForm defaultHandle="skej.demo" />
            </div>
            <div className="flex flex-wrap gap-2 text-sm font-black text-secondary-foreground">
              <span className="rounded-full border border-border bg-secondary px-3 py-1.5">
                Threads
              </span>
              <span className="rounded-full border border-border bg-secondary px-3 py-1.5">
                Replies and quotes
              </span>
              <span className="rounded-full border border-border bg-secondary px-3 py-1.5">
                Failed-post recovery
              </span>
            </div>
          </div>

          <div className="relative">
            <Image
              alt="Skej mobile composer and desktop queue interface"
              className="h-auto w-full rounded-[2rem] border border-border bg-card shadow-[0_28px_90px_rgba(70,52,70,0.18)]"
              height={1024}
              priority
              src="/skej-product-preview.png"
              width={1536}
            />
          </div>
        </section>

        <section className="grid gap-4 lg:grid-cols-3">
          {steps.map((step) => {
            const Icon = step.icon;
            return (
              <Card key={step.title}>
                <CardContent className="flex flex-col gap-4 p-5">
                  <div className="grid size-11 place-items-center rounded-2xl bg-primary text-primary-foreground">
                    <Icon />
                  </div>
                  <div className="flex flex-col gap-1">
                    <h2 className="text-xl font-black">{step.title}</h2>
                    <p className="text-sm font-semibold leading-6 text-muted-foreground">
                      {step.text}
                    </p>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </section>

        <section className="grid gap-5 rounded-[2rem] border border-border bg-card/80 p-5 shadow-[0_24px_70px_rgba(70,52,70,0.12)] lg:grid-cols-[1fr_auto] lg:items-center">
          <div className="flex flex-col gap-2">
            <div className="flex items-center gap-2 text-sm font-black text-muted-foreground">
              <Database />
              SQLite alpha
            </div>
            <h2 className="text-3xl font-black">Useful now, intentionally small.</h2>
            <p className="max-w-2xl text-sm font-semibold leading-6 text-muted-foreground">
              The alpha build uses a simple SQLite queue and local OAuth session flow
              so the core scheduling loop can be tested before the production PDS
              integration is hardened.
            </p>
          </div>
          <Link className={buttonVariants({ size: "lg" })} href="/app">
            Start scheduling
            <ArrowRight data-icon="inline-end" />
          </Link>
        </section>
      </div>
    </main>
  );
}
