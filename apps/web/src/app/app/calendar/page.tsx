import { Suspense } from "react";

import { CalendarWorkspace } from "@/components/CalendarWorkspace";

export default function CalendarPage() {
  return (
    <Suspense fallback={<main className="p-8">Loading calendar…</main>}>
      <CalendarWorkspace />
    </Suspense>
  );
}
