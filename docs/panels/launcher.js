import { fit, whenVisible, mount, reduceMotion, cubicBezier, clamp01 } from "./shared.js";
const WIDTH = 560;
const HEIGHT = 520;
const RADIUS = 26;
const OPEN_RESPONSE = 0.42;
const CLOSE_RESPONSE = 0.28;
const FADE_IN_MS = 160;
const FADE_OUT_MS = 140;
const TRAVEL = 40;
const CLOSED_SCALE = 0.92;
const fadeCurve = (x) => cubicBezier(x, 0.23, 1, 0.32, 1);
const REOPEN_MS = 700;
const HALF_LIFE = 7 * 24 * 60 * 60 * 1e3;
const USED_THRESHOLD = 0.05;
const MAX_USAGE_BONUS = 15;
const ICONS = new URL("./assets/", import.meta.url);
const APPS = [
  ["Safari", "com.apple.Safari", "safari"],
  ["Mail", "com.apple.mail", "mail"],
  ["Notes", "com.apple.Notes", "notes"],
  ["Calendar", "com.apple.iCal", "calendar"],
  ["Music", "com.apple.Music", "music"],
  ["Photos", "com.apple.Photos", "photos"],
  ["Maps", "com.apple.Maps", "maps"],
  ["Terminal", "com.apple.Terminal", "terminal"],
  ["TextEdit", "com.apple.TextEdit", "textedit"],
  ["System Settings", "com.apple.systempreferences", "settings"],
  ["Weather", "com.apple.weather", "weather"],
  ["Preview", "com.apple.Preview", "preview"]
].map(([name, key, icon]) => ({ name, key, icon: new URL(`${icon}.webp`, ICONS).href }));
const PINNED = ["com.apple.Safari", "com.apple.mail", "com.apple.Notes"];
const normalize = (s) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
const isBoundary = (ch) => ch === " " || ch === "-" || ch === "_" || ch === "." || ch === "(";
function fuzzyScore(query, candidate) {
  const q = [...normalize(query)].filter((ch) => !/\s/.test(ch));
  if (q.length === 0) return 0;
  const normalized = normalize(candidate);
  const c = [...normalized];
  let score = 0;
  let qi = 0;
  let previous = -2;
  for (let ci = 0; ci < c.length && qi < q.length; ci++) {
    if (c[ci] !== q[qi]) continue;
    let points = 1;
    if (ci === 0) points += 8;
    else if (isBoundary(c[ci - 1])) points += 5;
    if (ci === previous + 1) points += 3;
    score += points;
    previous = ci;
    qi++;
  }
  if (qi !== q.length) return null;
  const plain = q.join("");
  if (normalized.startsWith(plain)) score += 20;
  else if (normalized.includes(plain)) score += 10;
  return score;
}
const usage = new Map();
function weight(key, now) {
  const entry = usage.get(key);
  if (!entry) return 0;
  return entry.score * 0.5 ** (Math.max(0, now - entry.updated) / HALF_LIFE);
}
function record(key) {
  const now = Date.now();
  usage.set(key, { score: weight(key, now) + 1, updated: now });
}
const alphabetical = (a, b) => a.name.localeCompare(b.name, void 0, { numeric: true, sensitivity: "base" });
const usageBonus = (w) => Math.min(Math.log2(1 + w) * 6, MAX_USAGE_BONUS);
function rank(apps, query) {
  const now = Date.now();
  const trimmed = query.replace(/^\s+|\s+$/g, "");
  if (!trimmed) {
    const pos = new Map();
    PINNED.forEach((k, i) => pos.has(k) || pos.set(k, i));
    const top = apps.filter((a) => pos.has(a.key)).sort((a, b) => pos.get(a.key) - pos.get(b.key));
    const rest = apps.filter((a) => !pos.has(a.key)).map((a) => [a, weight(a.key, now)]).sort(([a, wa], [b, wb]) => {
      const ua = wa >= USED_THRESHOLD;
      const ub = wb >= USED_THRESHOLD;
      if (ua !== ub) return ua ? -1 : 1;
      if (ua && wa !== wb) return wb - wa;
      return alphabetical(a, b);
    }).map(([a]) => a);
    return top.concat(rest);
  }
  return apps.map((a) => {
    const s = fuzzyScore(trimmed, a.name);
    return s === null ? null : [a, s + usageBonus(weight(a.key, now))];
  }).filter(Boolean).sort(([a, sa], [b, sb]) => sa !== sb ? sb - sa : alphabetical(a, b)).map(([a]) => a);
}
function springAt(t, response) {
  const w = 2 * Math.PI / response;
  return 1 - (1 + w * t) * Math.exp(-w * t);
}
const settled = (t, response) => 1 - springAt(t, response) < 5e-4;
const SEARCH = '<svg class="lc-glyph" width="23" height="23" viewBox="0 0 24 24" stroke-width="2" aria-hidden="true"><path d="M3 10a7 7 0 1 0 14 0a7 7 0 1 0 -14 0"/><path d="M21 21l-6 -6"/></svg>';
let uid = 0;
function build() {
  const id = `lc-${++uid}`;
  const stage = document.createElement("div");
  stage.className = "panel-stage lc-stage";
  stage.innerHTML = `
    <div class="lc-clip">
      <div class="lc-panel glass" style="--radius:${RADIUS}px">
        <div class="lc-search">
          ${SEARCH}
          <input class="lc-input" type="text" placeholder="Search…" autocomplete="off" autocapitalize="off" spellcheck="false"
            role="combobox" aria-expanded="true" aria-autocomplete="list" aria-controls="${id}-list" aria-label="Search apps">
        </div>
        <div class="lc-divider" aria-hidden="true"></div>
        <div class="lc-list" data-lenis-prevent>
          <div class="lc-rows" id="${id}-list" role="listbox" aria-label="Apps"></div>
        </div>
        <p class="lc-empty" hidden>No App Found</p>
      </div>
    </div>`;
  return { stage, id };
}
function setup(host) {
  const { stage, id } = build();
  const panel = stage.querySelector(".lc-panel");
  const input = stage.querySelector(".lc-input");
  const list = stage.querySelector(".lc-list");
  const rowsEl = stage.querySelector(".lc-rows");
  const empty = stage.querySelector(".lc-empty");
  let query = "";
  let results = [];
  let selected = 0;
  let rows = [];
  function renderRows() {
    rowsEl.replaceChildren(
      ...results.map((app, i) => {
        const row = document.createElement("div");
        row.className = "lc-row";
        row.id = `${id}-row-${i}`;
        row.setAttribute("role", "option");
        const img = document.createElement("img");
        img.src = app.icon;
        img.width = 32;
        img.height = 32;
        img.alt = "";
        img.draggable = false;
        const name = document.createElement("span");
        name.textContent = app.name;
        row.append(img, name);
        return row;
      })
    );
    rows = [...rowsEl.children];
    list.hidden = results.length === 0;
    empty.hidden = results.length !== 0;
    renderSelection(false);
  }
  function renderSelection(scroll = true) {
    rows.forEach((r, i) => {
      r.classList.toggle("is-selected", i === selected);
      r.setAttribute("aria-selected", String(i === selected));
    });
    if (rows[selected]) input.setAttribute("aria-activedescendant", rows[selected].id);
    else input.removeAttribute("aria-activedescendant");
    if (!scroll || !rows[selected]) return;
    const row = rows[selected];
    const top = row.offsetTop - 8;
    const bottom = row.offsetTop + row.offsetHeight + 8;
    if (top < list.scrollTop) list.scrollTop = top;
    else if (bottom > list.scrollTop + list.clientHeight) list.scrollTop = bottom - list.clientHeight;
  }
  function applyFilter() {
    results = rank(APPS, query);
    selected = 0;
    renderRows();
    list.scrollTop = 0;
  }
  function move(delta) {
    if (!results.length) return;
    selected = Math.min(Math.max(selected + delta, 0), results.length - 1);
    renderSelection();
  }
  let isOpen = false;
  let progress = 0;
  let alpha = 0;
  let anim = null;
  let raf = 0;
  let reopenTimer = 0;
  let generation = 0;
  function paint() {
    const p = reduceMotion ? 1 : progress;
    const scale = CLOSED_SCALE + (1 - CLOSED_SCALE) * p;
    const y = TRAVEL * (1 - p);
    panel.style.transform = p === 1 ? "" : `translateY(${y.toFixed(2)}px) scale(${scale.toFixed(4)})`;
    panel.style.opacity = alpha.toFixed(3);
  }
  function step(now) {
    raf = 0;
    if (!anim) return;
    const t = (now - anim.start) / 1e3;
    const done = settled(t, anim.response);
    progress = done ? anim.to : anim.from + (anim.to - anim.from) * springAt(t, anim.response);
    const f = clamp01((now - anim.start) / anim.fadeMs);
    alpha = anim.alphaFrom + (anim.alphaTo - anim.alphaFrom) * fadeCurve(f);
    paint();
    if (done && f >= 1) {
      const end = anim.onEnd;
      anim = null;
      end?.();
    } else {
      raf = requestAnimationFrame(step);
    }
  }
  function animate(open2, onEnd) {
    anim = {
      from: progress,
      to: open2 ? 1 : 0,
      response: open2 ? OPEN_RESPONSE : CLOSE_RESPONSE,
      alphaFrom: alpha,
      alphaTo: open2 ? 1 : 0,
      fadeMs: open2 ? FADE_IN_MS : FADE_OUT_MS,
      start: performance.now(),
      onEnd
    };
    if (!raf) raf = requestAnimationFrame(step);
  }
  function open() {
    if (isOpen) return;
    isOpen = true;
    generation++;
    clearTimeout(reopenTimer);
    query = "";
    input.value = "";
    applyFilter();
    panel.inert = false;
    panel.classList.remove("is-closed");
    input.readOnly = false;
    animate(true);
  }
  function close(after) {
    if (!isOpen) return;
    isOpen = false;
    const current = ++generation;
    input.readOnly = true;
    panel.classList.add("is-closed");
    animate(false, () => {
      if (generation !== current || !after) return;
      reopenTimer = setTimeout(() => {
        if (generation !== current || !visible) return;
        open();
      }, REOPEN_MS);
    });
  }
  function jumpClosed() {
    isOpen = false;
    generation++;
    clearTimeout(reopenTimer);
    anim = null;
    progress = 0;
    alpha = 0;
    input.readOnly = true;
    panel.classList.add("is-closed");
    panel.inert = true;
    paint();
  }
  function launchSelected() {
    const app = results[selected];
    if (!app || !isOpen) return;
    record(app.key);
    close(true);
  }
  input.addEventListener("input", () => {
    query = input.value;
    applyFilter();
  });
  input.addEventListener("keydown", (e) => {
    if (e.isComposing) return;
    if (!isOpen) {
      if (e.key.length === 1 || e.key.startsWith("Arrow") || e.key === "Enter") e.preventDefault();
      return;
    }
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      move(e.key === "ArrowDown" ? 1 : -1);
    } else if (e.key === "Enter") {
      e.preventDefault();
      launchSelected();
    } else if (e.key === "Escape") {
      e.preventDefault();
      close(true);
    }
  });
  let last = null;
  rowsEl.addEventListener("pointermove", (e) => {
    if (e.pointerType !== "mouse") return;
    if (last && last.x === e.clientX && last.y === e.clientY) return;
    last = { x: e.clientX, y: e.clientY };
    const row = e.target.closest(".lc-row");
    const index = rows.indexOf(row);
    if (index >= 0 && index !== selected) {
      selected = index;
      renderSelection(false);
    }
  });
  rowsEl.addEventListener("click", (e) => {
    const index = rows.indexOf(e.target.closest(".lc-row"));
    if (index < 0) return;
    selected = index;
    renderSelection(false);
    input.focus({ preventScroll: true });
    launchSelected();
  });
  panel.addEventListener("pointerdown", (e) => {
    if (e.target !== input) {
      e.preventDefault();
      input.focus({ preventScroll: true });
    }
  });
  jumpClosed();
  applyFilter();
  fit(host, stage, WIDTH, HEIGHT);
  mount(host, stage);
  let visible = false;
  whenVisible(host, (v) => {
    visible = v;
    if (v) open();
    else if (!panel.contains(document.activeElement)) jumpClosed();
  }, 0.35);
}
document.querySelectorAll('.panel-host[data-panel="launcher"]').forEach(setup);
