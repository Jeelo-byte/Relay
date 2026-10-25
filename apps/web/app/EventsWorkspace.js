"use client";
import { useState } from "react";

export const formatMoney = (amount) => amount ? new Intl.NumberFormat(undefined, { style: "currency", currency: amount.currency }).format(amount.minor / 10 ** amount.exponent) : "Not stated";
export function dueDate(due) {
  if (!due) return null;
  if (due.type === "instant" && Number.isFinite(due.instant_utc)) return new Date(due.instant_utc);
  const text = due.type === "range" ? due.range_end : due.date;
  return /^\d{4}-\d{2}-\d{2}$/.test(text || "") ? new Date(text + "T12:00:00") : null;
}
export function formatDue(due) {
  const value = dueDate(due);
  if (!value || Number.isNaN(value.valueOf())) return "Not stated";
  return value.toLocaleString(undefined, { month: "short", day: "numeric", ...(due.type === "instant" ? { hour: "numeric", minute: "2-digit", timeZone: due.tz_assumed || undefined } : {}) }) + (due.ambiguous ? " (assumed)" : "");
}
export function Icon({ name, ...props }) {
  const files = { logo: "imgSymbolBubbleLeftAndBubbleRightFill", events: "imgSymbolCalendar", messages: "imgSymbolBubbleLeftAndBubbleRightFill1", people: "imgSymbolPerson2Fill", settings: "imgSymbolGearshapeFill", recaps: "imgSymbolHouseFill", search: "imgRelayIconMagnifyingglass", filter: "imgSymbolLine3HorizontalDecrease", item: "imgSymbolWaterbottle", chevron: "imgSymbolChevronRight", link: "imgSymbolLink", bell: "imgSymbolBell", privacy: "imgSymbolHandRaised", privacyHero: "imgSymbolHandRaised1", devices: "imgSymbolLaptopcomputer", help: "imgSymbolQuestionmarkCircle" };
  return <img className="design-icon" src={`/figma/${files[name]}.svg`} alt="" aria-hidden="true" {...props} />;
}
export const initials = (name) => name.split(/\s+/).filter(Boolean).slice(0, 2).map((word) => Array.from(word)[0]).join("").toLocaleUpperCase();
const source = (agreement) => agreement.source_room_names?.[0] || ({ imessage: "Messages", discord: "Discord", whatsapp: "WhatsApp", telegram: "Telegram", signal: "Signal", slack: "Slack", gmessages: "Google Messages", meta: "Messenger" }[agreement.evidence?.[0]?.network]) || "Added by you";
const personName = (agreement, id) => agreement.parties.find((p) => p.party_id === id)?.display_name_snapshot || "Not stated";
const calendarKey = (date) => [date.getFullYear(), date.getMonth(), date.getDate()].join("-");

export default function EventsWorkspace({ items, onSelect, onBrowse }) {
  const [week, setWeek] = useState(() => new Date());
  const [calendarVisible, setCalendarVisible] = useState(false);
  const accepted = items.filter((a) => a.review_state === "accepted" && ["offered", "agreed"].includes(a.lifecycle));
  const suggestions = items.filter((a) => a.review_state === "suggested");
  const money = accepted.flatMap((a) => a.obligations.filter((o) => o.status === "open" && o.amount).map((o) => ({ a, o })));
  const borrowed = accepted.filter((a) => a.kind === "item");
  const start = new Date(week.getFullYear(), week.getMonth(), week.getDate() - (week.getDay() + 6) % 7);
  const days = Array.from({ length: 7 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
  const firstDue = (a) => a.obligations.filter((o) => o.status === "open").map((o) => dueDate(o.due)).filter(Boolean).sort((a, b) => a - b)[0];
  function shiftWeek(amount) { setWeek(new Date(week.getFullYear(), week.getMonth(), week.getDate() + amount)); }
  return <div className="events-workspace">
    <div className="section-heading date-heading"><h2>{new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</h2><button className="text-action" onClick={() => setCalendarVisible(!calendarVisible)} aria-expanded={calendarVisible}>Week View ›</button></div>
    {!!suggestions.length && <section className="review-section"><div className="section-heading"><h2>To review</h2><button className="text-action" onClick={() => onBrowse("Suggested")}>See All ›</button></div>{suggestions.map((a) => <button key={a.id} className="review-row" onClick={() => onSelect(a.id)}><span><strong>{a.title}</strong><small>Review the source before saving</small></span><Icon name="chevron" /></button>)}</section>}
    <div className="event-summary">
      <section><div className="section-heading"><h2>Money</h2><button className="text-action" onClick={() => onBrowse("Money")}>See All ›</button></div><div className="money-grid">{money.slice(0, 2).map(({ a, o }) => <button key={a.id + o.id} className="money-card" onClick={() => onSelect(a.id)}><strong>{formatMoney(o.amount)}</strong><span>{a.parties.find((p) => p.party_id === o.obligor_party_id)?.is_self ? `You owe ${personName(a, o.obligee_party_id)}` : `${personName(a, o.obligor_party_id)} owes you`}</span><span className="source-badge">{source(a)}</span></button>)}{!money.length && <div className="quiet-card">No open amounts to remember.</div>}</div></section>
      <section><div className="section-heading"><h2>Items</h2><button className="text-action" onClick={() => onBrowse("Items")}>See All ›</button></div><div className="items-card">{borrowed.slice(0, 3).map((a) => <button key={a.id} className="item-row" onClick={() => onSelect(a.id)}><Icon name="item" /><span><strong>{a.title}</strong><small>With {a.parties.find((p) => !p.is_self)?.display_name_snapshot || "you"} · {formatDue(a.obligations[0]?.due)}</small></span><Icon name="chevron" /></button>)}{!borrowed.length && <p className="muted">Nothing borrowed to keep track of.</p>}</div></section>
    </div>
    <section className={`week-calendar ${calendarVisible ? "calendar-expanded" : ""}`} aria-label="Week calendar">
      <div className="calendar-controls"><button onClick={() => shiftWeek(-7)} aria-label="Previous week">‹</button><h3>{week.toLocaleDateString(undefined, { month: "long", year: "numeric" })}</h3><button className="text-action" onClick={() => setWeek(new Date())}>Today</button><button onClick={() => shiftWeek(7)} aria-label="Next week">›</button></div>
      <div className="week-scroll"><div className="week-days">{days.map((day) => <div className={`week-day ${calendarKey(day) === calendarKey(new Date()) ? "today" : ""}`} key={calendarKey(day)}><span>{day.toLocaleDateString(undefined, { weekday: "short" }).toUpperCase()}</span><strong>{day.getDate()}</strong>{accepted.filter((a) => !["payment", "item"].includes(a.kind) && firstDue(a) && calendarKey(firstDue(a)) === calendarKey(day)).map((a) => <button key={a.id} onClick={() => onSelect(a.id)} className="calendar-plan"><b>{a.title}</b><small>{formatDue(a.obligations[0]?.due)}</small><small>{source(a)}</small></button>)}</div>)}</div></div>
      <p className="muted">Choose a plan to view its people, details, and original conversation.</p>
    </section>
    <section className="coming-up"><div className="section-heading"><h2>Coming up</h2><button className="text-action" onClick={() => setCalendarVisible(!calendarVisible)}>Calendar ›</button></div>{accepted.filter((a) => !["payment", "item"].includes(a.kind)).sort((a, b) => (firstDue(a)?.valueOf() || Infinity) - (firstDue(b)?.valueOf() || Infinity)).map((a) => <button className="upcoming-plan" key={a.id} onClick={() => onSelect(a.id)}><span className="date-tile">{firstDue(a) ? <><small>{firstDue(a).toLocaleDateString(undefined, { weekday: "short" }).toUpperCase()}</small><strong>{firstDue(a).getDate()}</strong></> : "—"}</span><span><b>{a.title}</b><span>{formatDue(a.obligations[0]?.due)}</span><span className="source-badge">{source(a)}</span></span></button>)}</section>
    <button className="text-action" onClick={() => onBrowse("All")}>All Agreements ›</button>
  </div>;
}
