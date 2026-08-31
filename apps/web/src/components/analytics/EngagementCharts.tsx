"use client";

import * as React from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  LabelList,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

import type {
  EngagementAccountSeries,
  EngagementMetric,
} from "@/lib/analyticsTypes";

const ACCOUNT_COLORS = ["#ff4f6d", "#00a8c8", "#8b5cf6", "#d97706", "#16875b", "#be185d", "#4f46e5", "#64748b"];
const DASHES = [undefined, "8 4", "2 3", "12 4 2 4", "6 2", "1 3", "10 3", "4 4"];
const BAR_METRICS = ["likes", "reposts", "replies", "quotes"] as const;
const BAR_COLORS: Record<(typeof BAR_METRICS)[number], string> = {
  likes: "#ff4f6d",
  reposts: "#00a8c8",
  replies: "#8b5cf6",
  quotes: "#d97706",
};

function accountLabel(series: EngagementAccountSeries) {
  return series.account.displayName ?? series.account.handle ?? series.account.did;
}

function bucketLabel(value: string) {
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(
    new Date(value)
  );
}

function compactNumber(value: number) {
  return new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 1 }).format(
    value
  );
}

export function EngagementCharts({
  accounts,
  metric,
}: {
  accounts: EngagementAccountSeries[];
  metric: EngagementMetric;
}) {
  const lineData = React.useMemo(() => {
    const rows = new Map<string, Record<string, string | number>>();
    for (const series of accounts) {
      for (const point of series.points) {
        const row = rows.get(point.bucketStart) ?? { bucketStart: point.bucketStart };
        row[series.account.did] = point[metric];
        rows.set(point.bucketStart, row);
      }
    }
    return Array.from(rows.values()).sort((left, right) =>
      String(left.bucketStart).localeCompare(String(right.bucketStart))
    );
  }, [accounts, metric]);

  const barData = React.useMemo(
    () =>
      accounts.map((series) => ({
        account: accountLabel(series),
        ...series.period,
      })),
    [accounts]
  );

  return (
    <div className="grid gap-5">
      <section aria-labelledby="engagement-trend-title" className="rounded-[1.5rem] border border-border bg-card p-4">
        <h2 className="text-lg font-black" id="engagement-trend-title">
          Net {metric} over time
        </h2>
        <p className="mt-1 text-sm font-semibold text-muted-foreground">
          One line per account. Negative values reflect removed engagements.
        </p>
        <div
          aria-label={`Multi-line chart of net ${metric} by account`}
          className="mt-4 h-[22rem] min-h-72 w-full"
          role="img"
        >
          <ResponsiveContainer height="100%" width="100%">
            <LineChart accessibilityLayer data={lineData} margin={{ left: 4, right: 72, top: 16, bottom: 8 }}>
              <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" />
              <XAxis dataKey="bucketStart" minTickGap={28} tickFormatter={bucketLabel} />
              <YAxis tickFormatter={compactNumber} width={48} />
              <Tooltip
                content={({ active, label, payload }) =>
                  active && payload?.length ? (
                    <div className="rounded-xl border border-border bg-card p-3 text-xs shadow-xl">
                      <div className="mb-2 font-black">{bucketLabel(String(label))}</div>
                      {payload.map((entry) => (
                        <div className="flex items-center justify-between gap-5" key={String(entry.dataKey)}>
                          <span>{entry.name}</span>
                          <strong>{Number(entry.value).toLocaleString()}</strong>
                        </div>
                      ))}
                    </div>
                  ) : null
                }
              />
              <Legend />
              {accounts.map((series, index) => (
                <Line
                  activeDot={{ r: 6 }}
                  dataKey={series.account.did}
                  dot={{ r: 3, strokeWidth: 2 }}
                  key={series.account.did}
                  name={accountLabel(series)}
                  stroke={ACCOUNT_COLORS[index % ACCOUNT_COLORS.length]}
                  strokeDasharray={DASHES[index % DASHES.length]}
                  strokeWidth={3}
                  type="monotone"
                >
                  <LabelList
                    content={({ index: pointIndex, value, x, y }) =>
                      pointIndex === lineData.length - 1 && typeof x === "number" && typeof y === "number" ? (
                        <text
                          dominantBaseline="middle"
                          fill={ACCOUNT_COLORS[index % ACCOUNT_COLORS.length]}
                          fontSize={11}
                          fontWeight={800}
                          x={x + 8}
                          y={y}
                        >
                          {accountLabel(series)} {Number(value).toLocaleString()}
                        </text>
                      ) : null
                    }
                    dataKey={series.account.did}
                  />
                </Line>
              ))}
            </LineChart>
          </ResponsiveContainer>
        </div>
      </section>

      <section aria-labelledby="engagement-mix-title" className="rounded-[1.5rem] border border-border bg-card p-4">
        <h2 className="text-lg font-black" id="engagement-mix-title">
          Engagement mix by account
        </h2>
        <p className="mt-1 text-sm font-semibold text-muted-foreground">
          Grouped net likes, reposts, replies, and quotes for the selected period.
        </p>
        <div className="mt-4 overflow-x-auto pb-2">
          <div
            aria-label="Grouped bar chart of engagement metrics by account"
            className="h-[22rem] min-w-[44rem]"
            role="img"
          >
            <ResponsiveContainer height="100%" width="100%">
              <BarChart accessibilityLayer data={barData} margin={{ left: 4, right: 12, top: 16, bottom: 36 }}>
                <defs>
                  {BAR_METRICS.map((metricName, index) => (
                    <pattern height="8" id={`engagement-${metricName}`} key={metricName} patternUnits="userSpaceOnUse" width="8">
                      <rect fill={BAR_COLORS[metricName]} height="8" width="8" />
                      <path
                        d={index % 2 === 0 ? "M0 8L8 0" : "M0 0L8 8"}
                        opacity="0.32"
                        stroke="white"
                        strokeWidth="2"
                      />
                    </pattern>
                  ))}
                </defs>
                <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" />
                <XAxis angle={-18} dataKey="account" height={64} interval={0} textAnchor="end" />
                <YAxis tickFormatter={compactNumber} width={48} />
                <Tooltip
                  content={({ active, label, payload }) =>
                    active && payload?.length ? (
                      <div className="rounded-xl border border-border bg-card p-3 text-xs shadow-xl">
                        <div className="mb-2 font-black">{label}</div>
                        {payload.map((entry) => (
                          <div className="flex items-center justify-between gap-5" key={String(entry.dataKey)}>
                            <span className="capitalize">{entry.name}</span>
                            <strong>{Number(entry.value).toLocaleString()}</strong>
                          </div>
                        ))}
                      </div>
                    ) : null
                  }
                />
                <Legend />
                {BAR_METRICS.map((metricName) => (
                  <Bar
                    dataKey={metricName}
                    fill={`url(#engagement-${metricName})`}
                    key={metricName}
                    name={metricName.charAt(0).toUpperCase() + metricName.slice(1)}
                    radius={[5, 5, 0, 0]}
                  />
                ))}
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </section>
    </div>
  );
}
