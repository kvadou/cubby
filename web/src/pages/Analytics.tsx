import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router";
import { api } from "../api";
import { duration, microDollars, percent, tickIndexes } from "../analytics";
import { KIND_LABEL, parseDay, timeAgo } from "../present";
import type { AnalyticsReport, Center } from "../types";

const WINDOWS = [7, 30, 90] as const;

export function Analytics({ center }: { center: Center }) {
  const [params, setParams] = useSearchParams();
  const days = WINDOWS.find((w) => String(w) === params.get("days")) ?? 30;
  const query = useQuery({
    queryKey: ["analytics", center.id, days],
    queryFn: () => api.analytics(center.id, days),
    refetchInterval: 30_000,
  });

  return (
    <>
      <div className="filters" role="group" aria-label="Time range">
        {WINDOWS.map((w) => (
          <button
            key={w}
            type="button"
            className="chip"
            aria-pressed={w === days}
            onClick={() => setParams(w === 30 ? {} : { days: String(w) }, { replace: true })}
          >
            Last {w} days
          </button>
        ))}
      </div>
      {query.isPending && <div className="card skeleton" aria-busy="true" aria-label="Loading" />}
      {query.isError && (
        <div className="empty" role="alert">
          <h2>Couldn't load analytics</h2>
          <button type="button" className="button button--quiet" onClick={() => query.refetch()}>Try again</button>
        </div>
      )}
      {query.data && <Report report={query.data} />}
    </>
  );
}

function Report({ report }: { report: AnalyticsReport }) {
  const { totals, messages, ai } = report;
  const decided = totals.approved + totals.dismissed;
  const drafted = messages.draft_as_is + messages.draft_edited;

  if (totals.proposed === 0 && decided === 0) {
    return (
      <div className="empty">
        <h2>No activity in this range yet</h2>
        <p className="muted">Decisions show up here a few seconds after you make them.</p>
        <PipelineNote report={report} />
      </div>
    );
  }

  return (
    <div className="analytics">
      <section className="tiles" aria-label="Summary">
        <Tile label="Decisions" value={String(decided)} detail={`${totals.approved} approved, ${totals.dismissed} dismissed`} />
        <Tile label="Approval rate" value={totals.approval_rate === null ? "No data" : percent(totals.approved, decided)} detail="of items you decided" />
        <Tile label="Time to decision" value={duration(report.median_hours_to_decision)} detail="median, from found to decided" />
        <Tile
          label="Drafts sent as written"
          value={drafted > 0 ? percent(messages.draft_as_is, drafted) : "No drafts yet"}
          detail={`${messages.draft_edited} edited, ${messages.starter_or_own} written without a draft`}
        />
        <Tile
          label="AI cost per message"
          value={microDollars(ai.cost_per_approved_message_micros)}
          detail={ai.drafts > 0 ? `${ai.drafts} drafts, ${microDollars(ai.cost_micros)} total` : "No drafts in this range"}
        />
      </section>

      <section className="panel" aria-labelledby="by-kind">
        <h2 id="by-kind" className="panel__title">By type</h2>
        <table className="kinds">
          <thead>
            <tr>
              <th scope="col">Type</th>
              <th scope="col">Found</th>
              <th scope="col">Approved</th>
              <th scope="col">Dismissed</th>
              <th scope="col">Cleared on its own</th>
              <th scope="col">Time to decision</th>
            </tr>
          </thead>
          <tbody>
            {report.by_kind.map((k) => (
              <tr key={k.kind}>
                <th scope="row"><span className={`badge badge--${k.kind}`}>{KIND_LABEL[k.kind]}</span></th>
                <td>{k.proposed}</td>
                <td>{k.approved}</td>
                <td>{k.dismissed}</td>
                <td>{k.resolved}</td>
                <td>{k.median_hours_to_decision === null ? "None" : duration(k.median_hours_to_decision)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section className="panel" aria-labelledby="daily">
        <h2 id="daily" className="panel__title">Decisions per day</h2>
        <DailyChart daily={report.daily} />
      </section>

      <PipelineNote report={report} />
    </div>
  );
}

function Tile({ label, value, detail }: { label: string; value: string; detail: string }) {
  return (
    <div className="tile">
      <div className="tile__label">{label}</div>
      <div className={/\d/.test(value) ? "tile__value" : "tile__value tile__value--empty"}>{value}</div>
      <div className="tile__detail">{detail}</div>
    </div>
  );
}

function DailyChart({ daily }: { daily: AnalyticsReport["daily"] }) {
  const max = Math.max(1, ...daily.map((d) => d.approved + d.dismissed));
  const width = 720;
  const height = 160;
  const gap = daily.length > 40 ? 1 : 3;
  const bar = (width - gap * (daily.length - 1)) / daily.length;
  const y = (n: number) => (n / max) * (height - 4);
  const label = (d: string) => parseDay(d).toLocaleDateString("en-US", { month: "short", day: "numeric" });
  const total = daily.reduce((s, d) => s + d.approved + d.dismissed, 0);

  return (
    <figure className="chart">
      <svg viewBox={`0 0 ${width} ${height + 2}`} role="img" aria-label={`${total} decisions over ${daily.length} days; the table below lists each day.`}>
        {daily.map((d, i) => {
          const x = i * (bar + gap);
          const a = y(d.approved);
          const s = y(d.dismissed);
          return (
            <g key={d.date}>
              <title>{`${label(d.date)}: ${d.approved} approved, ${d.dismissed} dismissed`}</title>
              <rect x={x} y={height - a} width={bar} height={a} rx={2} className="chart__approved" />
              <rect x={x} y={height - a - s} width={bar} height={s} rx={2} className="chart__dismissed" />
            </g>
          );
        })}
        <line x1={0} x2={width} y1={height} y2={height} className="chart__axis" />
      </svg>
      {/* HTML labels keep a readable size when the chart scales down on phones. */}
      <div className="chart__ticks" aria-hidden="true">
        {tickIndexes(daily.length, daily.length > 10 ? 4 : 7).map((i, n, all) => {
          const d = daily[i];
          if (!d) return null;
          const edge = n === 0 ? "chart__tick--start" : n === all.length - 1 ? "chart__tick--end" : "";
          const left = ((i * (bar + gap) + bar / 2) / width) * 100;
          return (
            <span key={d.date} className={`chart__tick ${edge}`} style={{ left: `${left}%` }}>
              {label(d.date)}
            </span>
          );
        })}
      </div>
      <figcaption className="chart__legend">
        <span><i className="swatch swatch--approved" /> Approved</span>
        <span><i className="swatch swatch--dismissed" /> Dismissed</span>
      </figcaption>
      <table className="visually-hidden">
        <caption>Decisions per day</caption>
        <thead><tr><th scope="col">Day</th><th scope="col">Approved</th><th scope="col">Dismissed</th></tr></thead>
        <tbody>{daily.map((d) => <tr key={d.date}><td>{label(d.date)}</td><td>{d.approved}</td><td>{d.dismissed}</td></tr>)}</tbody>
      </table>
    </figure>
  );
}

function PipelineNote({ report }: { report: AnalyticsReport }) {
  const { waiting_to_publish, last_received_at } = report.pipeline;
  return (
    <p className="pipeline muted">
      Built from events delivered through SNS and SQS.{" "}
      {last_received_at ? `Last event received ${timeAgo(last_received_at)}.` : "No events received yet."}{" "}
      {waiting_to_publish > 0 ? `${waiting_to_publish} waiting to publish.` : "Nothing waiting to publish."}
    </p>
  );
}
