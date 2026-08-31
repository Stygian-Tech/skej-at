import { Suspense } from "react";

import { AnalyticsDashboard } from "@/components/analytics/AnalyticsDashboard";

export default function AnalyticsPage() {
  return (
    <Suspense fallback={<main className="min-h-dvh animate-pulse bg-muted" />}>
      <AnalyticsDashboard />
    </Suspense>
  );
}
