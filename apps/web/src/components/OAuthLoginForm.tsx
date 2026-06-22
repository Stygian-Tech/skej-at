"use client";

import { Cloud, LockKeyhole } from "lucide-react";
import * as React from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { startOAuth } from "@/lib/api";

interface OAuthLoginFormProps {
  compact?: boolean;
  defaultHandle?: string;
}

export function OAuthLoginForm({
  compact = false,
  defaultHandle = "",
}: OAuthLoginFormProps) {
  const [handle, setHandle] = React.useState(defaultHandle);

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    window.location.href = startOAuth(handle || "skej.demo");
  }

  return (
    <form className="flex w-full flex-col gap-2 sm:flex-row" onSubmit={submit}>
      <label className="sr-only" htmlFor={compact ? "app-handle" : "landing-handle"}>
        Bluesky handle
      </label>
      <Input
        id={compact ? "app-handle" : "landing-handle"}
        inputMode="url"
        onChange={(event) => setHandle(event.target.value)}
        placeholder="you.bsky.social"
        value={handle}
      />
      <Button className={compact ? "sm:w-auto" : "sm:min-w-44"} type="submit">
        {compact ? <LockKeyhole data-icon="inline-start" /> : <Cloud data-icon="inline-start" />}
        Connect PDS
      </Button>
    </form>
  );
}
