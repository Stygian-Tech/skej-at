"use client";

import { Cloud, LockKeyhole } from "lucide-react";
import * as React from "react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { startOAuth } from "@/lib/api";

interface OAuthLoginFormProps {
  compact?: boolean;
}

export function OAuthLoginForm({
  compact = false,
}: OAuthLoginFormProps) {
  const [handle, setHandle] = React.useState("");

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedHandle = handle.trim();
    if (!normalizedHandle) {
      setHandle("");
      return;
    }
    window.location.href = startOAuth(normalizedHandle);
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
        required
        value={handle}
      />
      <Button className={compact ? "sm:w-auto" : "sm:min-w-44"} type="submit">
        {compact ? <LockKeyhole data-icon="inline-start" /> : <Cloud data-icon="inline-start" />}
        Connect Bluesky
      </Button>
    </form>
  );
}
