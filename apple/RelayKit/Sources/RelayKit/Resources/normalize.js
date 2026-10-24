var RelayNormalize = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // packages/normalize/index.ts
  var index_exports = {};
  __export(index_exports, {
    normalized: () => normalized,
    parseAmount: () => parseAmount,
    quoteValid: () => quoteValid,
    resolveDate: () => resolveDate,
    triage: () => triage,
    validateExtraction: () => validateExtraction
  });
  function normalized(value) {
    return value.normalize("NFKC").toLowerCase().replace(/[‘’]/g, "'").replace(/[“”]/g, '"').replace(/[–—]/g, "-").replace(/\s+/g, " ").trim();
  }
  function quoteValid(quote, text) {
    return !!quote.trim() && normalized(text).includes(normalized(quote));
  }
  function triage(text) {
    let score = 0;
    if (/(?:[$€£¥₹]\s?\d|\d+(?:[.,]\d+)?\s?(?:bucks|dollars|usd|eur|euros|pounds|gbp)\b)/i.test(text)) score += 2;
    if (/\b(i'?ll|i will|i'?m gonna|i promise|i owe|you owe|owe you|pay (you|me|back)|send (it|you)|deal|count me in|i got you)\b/i.test(text)) score += 2;
    if (/\b(by |tomorrow|friday|monday|at \d|deadline)/i.test(text)) score++;
    const label = /\b(actually|instead|works better|change)\b/i.test(text) ? "change" : /\b(nvm|never mind|cancel|can't anymore)\b/i.test(text) ? "cancel" : /\b(paid|sent|done|got it thanks)\b/i.test(text) ? "completion" : /\b(yeah ok|sounds good|deal|agreed)\b/i.test(text) ? "acceptance" : score >= 2 ? "promise" : "none";
    return { label, score: Math.min(5, score) };
  }
  function parseAmount(text, currencyHint) {
    if (/split|each|half|\/\s*\d/.test(text.toLowerCase())) return null;
    const match = text.match(/(?:([$€£¥₹])\s*)?(\d+(?:[.,]\d{1,3})?)\s*(USD|EUR|GBP|JPY|INR|KWD|BHD|dollars|bucks|euros|pounds|k)?\b/i);
    if (!match) return null;
    const codes = { "$": "USD", "\u20AC": "EUR", "\xA3": "GBP", "\xA5": "JPY", "\u20B9": "INR", dollars: "USD", bucks: "USD", euros: "EUR", pounds: "GBP" };
    const token = (match[3] || "").toLowerCase();
    const currency = codes[match[1]] || codes[token] || (token && token !== "k" ? token.toUpperCase() : currencyHint || null);
    const exponent = currency === "JPY" ? 0 : currency === "KWD" || currency === "BHD" ? 3 : 2;
    let raw = match[2];
    if (raw.includes(",") && /,\d{3}$/.test(raw)) raw = raw.replace(",", "");
    else raw = raw.replace(",", ".");
    const value = Number(raw) * (token === "k" ? 1e3 : 1), minor = Math.round(value * 10 ** exponent);
    if (!Number.isSafeInteger(minor) || minor < 0 || minor > 1e14) return null;
    return { minor, currency, exponent, currency_assumed: match[1] === "$", derived: false, formula: null, raw_text: text };
  }
  function resolveDate(text, anchor, tz) {
    const parts = new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(anchor));
    const get = (type) => Number(parts.find((x) => x.type === type).value);
    const base = new Date(Date.UTC(get("year"), get("month") - 1, get("day"), 12));
    const value = normalized(text);
    let delta = 0, ambiguous = false;
    if (value === "tomorrow") delta = 1;
    else if (value === "today") delta = 0;
    else if (value === "yesterday") delta = -1;
    else {
      const weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
      const day = weekdays.findIndex((d) => value === d || value === `by ${d}` || value === `next ${d}` || value === `this ${d}`);
      if (day >= 0) {
        delta = (day - base.getUTCDay() + 7) % 7;
        if (value.startsWith("next ") && delta === 0) delta = 7;
        ambiguous = true;
      } else if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        const d = /* @__PURE__ */ new Date(value + "T12:00:00Z");
        if (isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value) return null;
        return { type: "date", date: value, tz_assumed: tz, raw_text: text, ambiguous: false, anchor_ts: anchor };
      } else return null;
    }
    base.setUTCDate(base.getUTCDate() + delta);
    return { type: "date", date: base.toISOString().slice(0, 10), tz_assumed: tz, raw_text: text, ambiguous, anchor_ts: anchor };
  }
  function validateExtraction(result, messages, parties) {
    const errors = [];
    if (!result || !Array.isArray(result.agreements) || result.agreements.length > 5) return ["schema:agreements"];
    result.agreements.forEach((a, i) => {
      if (!["create", "update", "complete", "cancel"].includes(a.op) || !["payment", "task", "meeting", "item", "other"].includes(a.kind) || !["offered", "agreed"].includes(a.lifecycle) || typeof a.title !== "string" || !a.title.length || a.title.length > 80 || typeof a.confidence !== "number" || a.confidence < 0 || a.confidence > 1) errors.push(`schema:agreements[${i}]`);
      if (!Array.isArray(a.evidence) || !a.evidence.length || a.evidence.length > 10) errors.push("schema:evidence");
      else a.evidence.forEach((e) => {
        if (!messages[e.m]) errors.push("unknown_message");
        else if (typeof e.quote !== "string" || e.quote.length > 280 || !quoteValid(e.quote, messages[e.m])) errors.push("quote_not_found");
      });
      if (!Array.isArray(a.obligations) || !a.obligations.length || a.obligations.length > 5) errors.push("schema:obligations");
      else a.obligations.forEach((o) => {
        if (!parties.includes(o.obligor) || !parties.includes(o.obligee)) errors.push("unknown_party");
        if (o.obligor === o.obligee) errors.push("self_obligation");
        if (typeof o.what !== "string" || !o.what.length || o.what.length > 140) errors.push("schema:what");
        for (const key of ["amount_text", "due_text", "place_text"]) if (o[key] && !a.evidence?.some((e) => typeof e.quote === "string" && quoteValid(o[key], e.quote))) delete o[key];
      });
    });
    return errors;
  }
  return __toCommonJS(index_exports);
})();
