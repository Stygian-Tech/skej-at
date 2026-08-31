import { describe, expect, it } from "bun:test";

import { calendarMonthDays, calendarMonthRange } from "@/lib/calendar";

describe("calendar URL range helpers", () => {
  it("uses half-open UTC month boundaries", () => {
    expect(calendarMonthRange("2028-02")).toEqual({
      from: "2028-02-01T00:00:00.000Z",
      to: "2028-03-01T00:00:00.000Z",
    });
  });

  it("builds leap-month cells with the correct weekday offset", () => {
    const days = calendarMonthDays("2028-02");
    expect(days).toHaveLength(29);
    expect(days[0]).toEqual({ key: "2028-02-01", day: 1, weekdayOffset: 2 });
    expect(days.at(-1)?.key).toBe("2028-02-29");
  });
});
