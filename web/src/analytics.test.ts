import { duration, microDollars, percent, tickIndexes } from "./analytics";

describe("analytics formatting", () => {
  it("formats durations for minutes, hours, and days", () => {
    expect(duration(null)).toBe("No decisions yet");
    expect(duration(0)).toBe("1 min");
    expect(duration(0.5)).toBe("30 min");
    expect(duration(5.25)).toBe("5.3 hr");
    expect(duration(72)).toBe("3 days");
  });

  it("formats sub-cent AI costs without rounding them to zero", () => {
    expect(microDollars(2000)).toBe("$0.0020");
    expect(microDollars(1_250_000)).toBe("$1.25");
    expect(microDollars(null)).toBe("No AI drafts yet");
  });

  it("handles empty percentages", () => {
    expect(percent(1, 3)).toBe("33%");
    expect(percent(0, 0)).toBe("No data");
  });

  it("spaces chart ticks and always labels the last day", () => {
    expect(tickIndexes(5)).toEqual([0, 1, 2, 3, 4]);
    expect(tickIndexes(30)).toEqual([0, 6, 12, 17, 23, 29]);
  });
});
