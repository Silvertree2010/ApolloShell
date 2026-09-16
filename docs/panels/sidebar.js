import { whenVisible, mount, reduceMotion, cubicBezier, clamp01 } from "./shared.js";
const BAR = 44;
const SPATIAL_MS = 500;
const spatial = (x) => cubicBezier(x, 0.38, 1.21, 0.22, 1);
const POPOUT_RADIUS = 25;
const SEED_HEIGHT = 30;
const JOIN = 14;
const POPOUT_WIDTH = { wifi: 300, bluetooth: 300, battery: 270 };
const EXPANDED = BAR + Math.max(...Object.values(POPOUT_WIDTH)) + 24;
const HOLD_MS = 500;
const DRAG_THRESHOLD = 4;
const SPACE_SLOT = 26;
const SPACE_GAP = 3;
const BOUNCE_CYCLE_MS = 440;
const LAUNCH_MS = BOUNCE_CYCLE_MS * 3;
const PATHS = {
  grid: [
    "M4 5a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4",
    "M14 5a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4",
    "M4 15a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4",
    "M14 15a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4"
  ],
  sliders: [
    "M12 6a2 2 0 1 0 4 0a2 2 0 1 0 -4 0",
    "M4 6l8 0",
    "M16 6l4 0",
    "M6 12a2 2 0 1 0 4 0a2 2 0 1 0 -4 0",
    "M4 12l2 0",
    "M10 12l10 0",
    "M15 18a2 2 0 1 0 4 0a2 2 0 1 0 -4 0",
    "M4 18l11 0",
    "M19 18l1 0"
  ],
  power: ["M7 6a7.75 7.75 0 1 0 10 0", "M12 4l0 8"],
  calendar: [
    "M4 7a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-12",
    "M16 3v4",
    "M8 3v4",
    "M4 11h16",
    "M11 15h1",
    "M12 15v3"
  ],
  battery: [
    "M6 7h11a2 2 0 0 1 2 2v.5a.5 .5 0 0 0 .5 .5a.5 .5 0 0 1 .5 .5v3a.5 .5 0 0 1 -.5 .5a.5 .5 0 0 0 -.5 .5v.5a2 2 0 0 1 -2 2h-11a2 2 0 0 1 -2 -2v-6a2 2 0 0 1 2 -2",
    "M7 10l0 4",
    "M10 10l0 4",
    "M13 10l0 4"
  ],
  wifiOff: [
    "M12 18l.01 0",
    "M9.172 15.172a4 4 0 0 1 5.656 0",
    "M6.343 12.343a7.963 7.963 0 0 1 3.864 -2.14m4.163 .155a7.965 7.965 0 0 1 3.287 2",
    "M3.515 9.515a12 12 0 0 1 3.544 -2.455m3.101 -.92a12 12 0 0 1 10.325 3.374",
    "M3 3l18 18"
  ],
  gear: [
    "M10.325 4.317c.426 -1.756 2.924 -1.756 3.35 0a1.724 1.724 0 0 0 2.573 1.066c1.543 -.94 3.31 .826 2.37 2.37a1.724 1.724 0 0 0 1.065 2.572c1.756 .426 1.756 2.924 0 3.35a1.724 1.724 0 0 0 -1.066 2.573c.94 1.543 -.826 3.31 -2.37 2.37a1.724 1.724 0 0 0 -2.572 1.065c-.426 1.756 -2.924 1.756 -3.35 0a1.724 1.724 0 0 0 -2.573 -1.066c-1.543 .94 -3.31 -.826 -2.37 -2.37a1.724 1.724 0 0 0 -1.065 -2.572c-1.756 -.426 -1.756 -2.924 0 -3.35a1.724 1.724 0 0 0 1.066 -2.573c-.94 -1.543 .826 -3.31 2.37 -2.37c1 .608 2.296 .07 2.572 -1.065",
    "M9 12a3 3 0 1 0 6 0a3 3 0 0 0 -6 0"
  ],
  headphones: [
    "M4 15a2 2 0 0 1 2 -2h1a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2h-1a2 2 0 0 1 -2 -2l0 -3",
    "M15 15a2 2 0 0 1 2 -2h1a2 2 0 0 1 2 2v3a2 2 0 0 1 -2 2h-1a2 2 0 0 1 -2 -2l0 -3",
    "M4 15v-3a8 8 0 0 1 16 0v3"
  ]
};
function svg(name, size, stroke = 1.75, cls = "") {
  const paths = PATHS[name].map((d) => `<path d="${d}"/>`).join("");
  return `<svg class="sb-glyph ${cls}" width="${size}" height="${size}" viewBox="0 0 24 24" stroke-width="${stroke}" aria-hidden="true">${paths}</svg>`;
}
function wifiSvg(size, strength, stroke = 1.75) {
  const arcs = ["M9.172 15.172a4 4 0 0 1 5.656 0", "M6.343 12.343a8 8 0 0 1 11.314 0", "M3.515 9.515c4.686 -4.687 12.284 -4.687 17 0"];
  const lit = strength >= 1 ? 3 : strength >= 0.66 ? 2 : strength >= 0.33 ? 1 : 0;
  const bars = arcs.map((d, i) => `<path d="${d}"${i < lit ? "" : ' class="is-dim"'}/>`).join("");
  return `<svg class="sb-glyph" width="${size}" height="${size}" viewBox="0 0 24 24" stroke-width="${stroke}" aria-hidden="true"><path d="M12 18l.01 0"/>${bars}</svg>`;
}
const RUNE = `<svg class="sb-rune" width="10" height="15" viewBox="0 0 10 15" aria-hidden="true"><path d="M0 4.05L10 10.95L5 15L5 0L10 4.05L0 10.95"/></svg>`;
const ICONS = new URL("./assets/", import.meta.url);
const DOCK = [
  { id: "finder", name: "Finder", pinned: true, running: true },
  { id: "safari", name: "Safari", pinned: true, running: true },
  { id: "mail", name: "Mail", pinned: true, running: true, badge: "3" },
  { id: "notes", name: "Notes", pinned: true, running: false },
  { id: "calendar", name: "Calendar", pinned: true, running: false },
  { id: "music", name: "Music", pinned: true, running: true },
  { id: "settings", name: "System Settings", pinned: true, running: false },
  { id: "terminal", name: "Terminal", pinned: false, running: true }
];
const DESKTOPS = 4;
const WIFI = { rssi: -58, noise: -92, rate: 864, phy: "Wi-Fi 6 (802.11ax)", channel: "36 · 5 GHz", iface: "en0" };
const BATTERY = { level: 82, minutesToEmpty: 431, health: 100, cycles: 87 };
const wifiStrength = (rssi) => rssi >= -55 ? 1 : rssi >= -67 ? 0.66 : rssi >= -75 ? 0.33 : 0.1;
const quality = (rssi) => rssi >= -55 ? "Excellent" : rssi >= -67 ? "Good" : rssi >= -75 ? "Fair" : "Weak";
function duration(minutes) {
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return h === 0 ? `${m}m` : m === 0 ? `${h}h` : `${h}h ${m}m`;
}
function glassPath(height, bulge) {
  const x = -1;
  const edge = BAR;
  if (!(bulge.w > 0.5 && bulge.h > 0.5)) {
    return `M${x} 0H${edge}V${height}H${x}Z`;
  }
  const r = Math.min(POPOUT_RADIUS, bulge.w / 2, bulge.h / 2);
  const j = Math.min(JOIN, bulge.w, Math.max(0, (height - bulge.h) / 2));
  const top = Math.max(0, bulge.y);
  const bottom = Math.min(height, bulge.y + bulge.h);
  const right = edge + bulge.w;
  const f = (n) => Math.round(n * 100) / 100;
  return [
    `M${x} 0`,
    `L${edge} 0`,
    `L${edge} ${f(top - j)}`,
    `Q${edge} ${f(top)} ${f(edge + j)} ${f(top)}`,
    `L${f(right - r)} ${f(top)}`,
    `Q${f(right)} ${f(top)} ${f(right)} ${f(top + r)}`,
    `L${f(right)} ${f(bottom - r)}`,
    `Q${f(right)} ${f(bottom)} ${f(right - r)} ${f(bottom)}`,
    `L${f(edge + j)} ${f(bottom)}`,
    `Q${edge} ${f(bottom)} ${edge} ${f(bottom + j)}`,
    `L${edge} ${height}`,
    `L${x} ${height}`,
    "Z"
  ].join(" ");
}
const placeTop = (anchorY, height, container) => Math.max(0, Math.min(anchorY - height / 2, container - height));
function iconButton(label, glyph, cls = "") {
  return `<button type="button" class="sb-icon ${cls}" aria-label="${label}" title="${label}">${glyph}</button>`;
}
function dockItem(entry) {
  const label = entry.running ? `${entry.name}, running` : entry.name;
  return `<button type="button" class="sb-app" data-app="${entry.id}" aria-label="${label}" title="${entry.name}">
    <span class="sb-app-bounce"><img src="${new URL(`${entry.id}.webp`, ICONS)}" width="26" height="26" alt="" draggable="false"></span>
    <span class="sb-dot" aria-hidden="true"></span>
    ${entry.badge ? `<span class="sb-badge" aria-hidden="true">${entry.badge}</span>` : ""}
  </button>`;
}
function spaces() {
  const dots = (cls) => `<div class="sb-dots ${cls}" aria-hidden="true">${Array.from({ length: DESKTOPS }, () => '<span class="sb-space-dot"><i></i></span>').join("")}</div>`;
  const hits = Array.from(
    { length: DESKTOPS },
    (_, i) => `<button type="button" class="sb-space-hit" data-space="${i}" aria-label="To Desktop ${i + 1}" title="To Desktop ${i + 1}"></button>`
  ).join("");
  return `<div class="sb-spaces" role="group">
    ${dots("")}
    <span class="sb-pill" aria-hidden="true"></span>
    ${dots("is-tinted")}
    <div class="sb-space-hits">${hits}</div>
  </div>`;
}
function valueRow(label, value) {
  return `<div class="po-value"><span>${label}</span><span>${value}</span></div>`;
}
function settingsButton(title) {
  return `<button type="button" class="po-settings" data-close>${svg("gear", 15, 1.75)}<span>${title}</span></button>`;
}
function wifiContent(on) {
  const head = `<div class="po-head"><span class="po-title">Wi-Fi</span>
    <button type="button" class="po-switch" role="switch" aria-checked="${on}" aria-label="Wi-Fi"><span></span></button></div>`;
  if (!on) {
    return `${head}
      <div class="po-lead"><span class="po-lead-icon">${svg("wifiOff", 18, 2)}</span>
        <span class="po-lead-text"><span>Wi-Fi Is Off</span></span></div>
      ${settingsButton("Wi-Fi Settings…")}`;
  }
  const snr = WIFI.rssi - WIFI.noise;
  return `${head}
    <div class="po-lead"><span class="po-lead-icon is-active">${wifiSvg(19, wifiStrength(WIFI.rssi), 2.1)}</span>
      <span class="po-lead-text"><span>Connected</span><small>Network name needs Location Services</small></span></div>
    <div class="po-card">
      ${valueRow("Signal", `${WIFI.rssi} dBm · ${quality(WIFI.rssi)}`)}
      ${valueRow("Noise", `${WIFI.noise} dBm · SNR ${snr} dB`)}
      ${valueRow("Transmit Rate", `${WIFI.rate} Mbit/s`)}
      ${valueRow("Standard", WIFI.phy)}
      ${valueRow("Channel", WIFI.channel)}
      ${valueRow("Interface", WIFI.iface)}
    </div>
    ${settingsButton("Wi-Fi Settings…")}`;
}
function bluetoothContent() {
  const chip = (label, pct) => `<span class="po-chip">${label ? `<span>${label}</span>` : ""}<b>${pct} %</b></span>`;
  return `<div class="po-head"><span class="po-title">Bluetooth</span><span class="po-state" title="Turning it on or off only works in System Settings">On</span></div>
    <p class="po-note">2 paired devices, 1 connected</p>
    <div class="po-devices">
      <div class="po-device"><span class="po-lead-icon is-active">${svg("headphones", 17, 2)}</span>
        <span class="po-lead-text"><span>Headphones</span><span class="po-chips">${chip("L", 82)}${chip("R", 79)}${chip("Case", 64)}</span></span></div>
    </div>
    ${settingsButton("Bluetooth Settings…")}`;
}
function batteryContent() {
  return `<div class="po-battery"><span class="po-big">${BATTERY.level} <small>%</small></span>${svg("battery", 30, 1.5, "po-battery-glyph")}</div>
    <div class="po-battery-text"><strong>Battery</strong><span>${duration(BATTERY.minutesToEmpty)} Left</span></div>
    <div class="po-card">
      ${valueRow("Low Power Mode", "Off")}
      ${valueRow("Maximum Capacity", `${BATTERY.health} %`)}
      ${valueRow("Charge Cycles", `${BATTERY.cycles}`)}
    </div>
    ${settingsButton("Battery Settings…")}`;
}
const POPOUT_LABEL = { wifi: "Wi-Fi details", bluetooth: "Bluetooth details", battery: "Battery details" };
function build() {
  const stage = document.createElement("div");
  stage.className = "panel-stage sb-stage";
  const pinned = DOCK.filter((e) => e.pinned).map(dockItem).join("");
  const running = DOCK.filter((e) => !e.pinned).map(dockItem).join("");
  stage.innerHTML = `
    <div class="sb-glass glass" aria-hidden="true"></div>
    <svg class="sb-rim" aria-hidden="true"><path/></svg>
    <div class="sb-col">
      ${iconButton("Dashboard (SUPER+D)", svg("grid", 21, 1.9))}
      ${spaces()}
      <div class="sb-dock">
        <div class="sb-dock-scroll" data-lenis-prevent>
          <div class="sb-dock-col" role="group" aria-label="Dock">
            ${pinned}<span class="sb-divider" aria-hidden="true"></span>${running}
          </div>
        </div>
      </div>
      <div class="sb-clock" role="img">
        ${svg("calendar", 20, 1.9)}
        <span class="sb-hour"></span><span class="sb-minute"></span>
      </div>
      ${iconButton("Utilities (SUPER+U)", svg("sliders", 21, 1.9))}
      <div class="sb-status">
        <div class="sb-status-slot" data-kind="wifi">${iconButton("", "", "sb-status-icon")}</div>
        <div class="sb-status-slot" data-kind="bluetooth">${iconButton("Bluetooth On", RUNE, "sb-status-icon")}</div>
        <div class="sb-status-slot" data-kind="battery">${iconButton(`Battery ${BATTERY.level}%`, svg("battery", 22, 1.9, "sb-battery"), "sb-status-icon")}</div>
      </div>
      <div class="sb-popouts" style="width:${EXPANDED}px">
        ${["wifi", "bluetooth", "battery"].map((k) => `<div class="po-content" id="sb-po-${k}" data-kind="${k}" role="group" aria-label="${POPOUT_LABEL[k]}" aria-hidden="true" inert style="width:${POPOUT_WIDTH[k]}px"></div>`).join("")}
      </div>
      ${iconButton("Session", svg("power", 22, 1.9))}
    </div>`;
  return stage;
}
function setup(host) {
  const stage = build();
  const $ = (s) => stage.querySelector(s);
  const $$ = (s) => [...stage.querySelectorAll(s)];
  const glass = $(".sb-glass");
  const rim = $(".sb-rim path");
  const rimSvg = $(".sb-rim");
  const hoverable = (el) => {
    el.addEventListener("pointerenter", (e) => e.pointerType === "mouse" && el.classList.add("is-hover"));
    el.addEventListener("pointerleave", () => el.classList.remove("is-hover"));
  };
  $$(".sb-icon").forEach(hoverable);
  for (const b of $$(".sb-col > .sb-icon")) b.addEventListener("click", (e) => e.preventDefault());
  const spacesEl = $(".sb-spaces");
  let activeSpace = 1;
  function renderSpaces() {
    const y = activeSpace * (SPACE_SLOT + SPACE_GAP);
    spacesEl.style.setProperty("--pill-y", `${y}px`);
    for (const dots of spacesEl.querySelectorAll(".sb-dots")) {
      [...dots.children].forEach((d, i) => d.classList.toggle("is-active", i === activeSpace));
    }
    spacesEl.querySelectorAll(".sb-space-hit").forEach((b, i) => {
      if (i === activeSpace) b.setAttribute("aria-current", "true");
      else b.removeAttribute("aria-current");
    });
    const label = `Desktop ${activeSpace + 1} of ${DESKTOPS}`;
    spacesEl.setAttribute("aria-label", label);
    spacesEl.title = label;
  }
  spacesEl.addEventListener("click", (e) => {
    const hit = e.target.closest(".sb-space-hit");
    if (!hit) return;
    activeSpace = Number(hit.dataset.space);
    renderSpaces();
  });
  renderSpaces();
  const state = new Map(DOCK.map((e) => [e.id, { ...e, launching: false }]));
  let frontmost = "safari";
  function renderDock() {
    for (const el of $$(".sb-app")) {
      const s = state.get(el.dataset.app);
      el.classList.toggle("is-running", s.running);
      el.classList.toggle("is-active", s.id === frontmost);
      el.classList.toggle("is-launching", s.launching && !reduceMotion);
      el.setAttribute("aria-label", s.running ? `${s.name}, running` : s.name);
      if (s.id === frontmost) el.setAttribute("aria-current", "true");
      else el.removeAttribute("aria-current");
    }
  }
  function click(id) {
    const s = state.get(id);
    if (s.launching) return;
    if (!s.running) {
      s.launching = true;
      renderDock();
      setTimeout(() => {
        s.launching = false;
        s.running = true;
        frontmost = id;
        renderDock();
      }, LAUNCH_MS);
      return;
    }
    if (frontmost !== id) {
      frontmost = id;
      renderDock();
    }
  }
  for (const el of $$(".sb-app")) {
    hoverable(el);
    const id = el.dataset.app;
    let timer = 0;
    let down = null;
    let cancelled = false;
    const setPressed = (on) => el.classList.toggle("is-pressed", on);
    el.addEventListener("pointerdown", (e) => {
      if (e.button !== 0 || e.ctrlKey) return;
      cancelled = false;
      down = { x: e.clientX, y: e.clientY };
      setPressed(true);
      el.setPointerCapture?.(e.pointerId);
      timer = setTimeout(() => {
        cancelled = true;
        setPressed(false);
      }, HOLD_MS);
    });
    el.addEventListener("pointermove", (e) => {
      if (!down || cancelled) return;
      if (Math.hypot(e.clientX - down.x, e.clientY - down.y) > DRAG_THRESHOLD) {
        cancelled = true;
        clearTimeout(timer);
        setPressed(false);
      }
    });
    const end = (e, commit) => {
      clearTimeout(timer);
      if (!down) return;
      down = null;
      setPressed(false);
      if (!commit || cancelled) return;
      const r = el.getBoundingClientRect();
      if (e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom) click(id);
    };
    el.addEventListener("pointerup", (e) => end(e, true));
    el.addEventListener("pointercancel", (e) => end(e, false));
    el.addEventListener("contextmenu", (e) => e.preventDefault());
    el.addEventListener("click", (e) => {
      if (e.detail === 0) click(id);
    });
  }
  renderDock();
  const dock = $(".sb-dock");
  const dockCol = $(".sb-dock-col");
  const fitDock = () => dock.classList.toggle("is-scrolling", dockCol.offsetHeight > dock.clientHeight + 0.5);
  new ResizeObserver(fitDock).observe(dock);
  const hourEl = $(".sb-hour");
  const minuteEl = $(".sb-minute");
  const clockEl = $(".sb-clock");
  let clockTimer = 0;
  const two = (n) => String(n).padStart(2, "0");
  function tick() {
    clearTimeout(clockTimer);
    const now = new Date();
    hourEl.textContent = two(now.getHours());
    minuteEl.textContent = two(now.getMinutes());
    clockEl.setAttribute("aria-label", `${two(now.getHours())}:${two(now.getMinutes())}`);
    clockEl.title = now.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
    const next = (60 - now.getSeconds()) * 1e3 - now.getMilliseconds();
    clockTimer = setTimeout(tick, next + 50);
  }
  let wifiOn = true;
  const slots = Object.fromEntries($$(".sb-status-slot").map((s) => [s.dataset.kind, s]));
  const icons = Object.fromEntries(Object.entries(slots).map(([k, s]) => [k, s.querySelector("button")]));
  const contents = Object.fromEntries($$(".po-content").map((c) => [c.dataset.kind, c]));
  const popLayer = $(".sb-popouts");
  function renderWifiIcon() {
    const b = icons.wifi;
    b.innerHTML = wifiOn ? wifiSvg(21, wifiStrength(WIFI.rssi), 1.9) : svg("wifiOff", 21, 1.9);
    const label = wifiOn ? `Wi-Fi ${WIFI.rssi} dBm` : "Wi-Fi Off";
    b.setAttribute("aria-label", label);
    b.title = label;
  }
  function renderContents() {
    contents.wifi.innerHTML = wifiContent(wifiOn);
    contents.bluetooth.innerHTML = bluetoothContent();
    contents.battery.innerHTML = batteryContent();
    stage.querySelectorAll(".po-settings").forEach(hoverable);
  }
  renderWifiIcon();
  renderContents();
  for (const [k, b] of Object.entries(icons)) {
    b.setAttribute("aria-expanded", "false");
    b.setAttribute("aria-controls", `sb-po-${k}`);
  }
  const sizes = {};
  const measure = () => {
    for (const [k, c] of Object.entries(contents)) sizes[k] = { w: POPOUT_WIDTH[k], h: c.offsetHeight };
  };
  const pop = { open: false, shown: "wifi", anchorY: 0 };
  let height = 0;
  let bulge = { y: 0, w: 0, h: SEED_HEIGHT };
  let contentTop = 0;
  let tween = null;
  let raf = 0;
  function apply() {
    const path = glassPath(height, bulge);
    glass.style.clipPath = `path("${path}")`;
    rim.setAttribute("d", path);
    const w = Math.max(0, bulge.w);
    const h = Math.max(0, bulge.h);
    const right = EXPANDED - BAR - w;
    const bottom = height - bulge.y - h;
    popLayer.style.clipPath = w > 0.5 && h > 0.5 ? `inset(${bulge.y}px ${right}px ${bottom}px ${BAR}px round ${POPOUT_RADIUS}px)` : "inset(50%)";
    popLayer.style.setProperty("--top", `${contentTop}px`);
  }
  function frame(t) {
    raf = 0;
    if (!tween) return;
    const p = clamp01((t - tween.start) / SPATIAL_MS);
    const e = spatial(p);
    const lerp = (a, b) => a + (b - a) * e;
    bulge = { y: lerp(tween.from.y, tween.to.y), w: lerp(tween.from.w, tween.to.w), h: lerp(tween.from.h, tween.to.h) };
    contentTop = lerp(tween.fromTop, tween.toTop);
    apply();
    if (p < 1) raf = requestAnimationFrame(frame);
    else tween = null;
  }
  function animate({ instantTop = false } = {}) {
    const size = sizes[pop.shown];
    const top = placeTop(pop.anchorY, size.h, height);
    const to = pop.open ? { y: top, w: size.w, h: size.h } : { y: pop.anchorY - SEED_HEIGHT / 2, w: 0, h: SEED_HEIGHT };
    const toTop = pop.open ? top : contentTop;
    if (instantTop) contentTop = toTop;
    if (reduceMotion) {
      bulge = to;
      contentTop = toTop;
      tween = null;
      apply();
      return;
    }
    tween = { from: { ...bulge }, to, fromTop: contentTop, toTop, start: performance.now() };
    if (!raf) raf = requestAnimationFrame(frame);
  }
  function renderActive() {
    for (const [k, c] of Object.entries(contents)) {
      const active = pop.open && pop.shown === k;
      c.classList.toggle("is-active", active);
      c.toggleAttribute("inert", !active);
      c.setAttribute("aria-hidden", String(!active));
      slots[k].classList.toggle("is-open", active);
      icons[k].setAttribute("aria-expanded", String(active));
    }
  }
  const anchorOf = (kind) => {
    const s = stage.getBoundingClientRect();
    const r = slots[kind].getBoundingClientRect();
    return r.top + r.height / 2 - s.top;
  };
  function iconClicked(kind) {
    measure();
    const anchor = anchorOf(kind);
    if (pop.open) {
      if (pop.shown === kind) return close();
      pop.shown = kind;
      pop.anchorY = anchor;
      renderActive();
      animate();
      return;
    }
    pop.shown = kind;
    pop.anchorY = anchor;
    tween = null;
    bulge = { y: anchor - SEED_HEIGHT / 2, w: 0, h: SEED_HEIGHT };
    pop.open = true;
    renderActive();
    animate({ instantTop: true });
    document.addEventListener("pointerdown", outside, true);
    document.addEventListener("keydown", escape);
  }
  function close() {
    if (!pop.open) return;
    const hadFocus = popLayer.contains(document.activeElement);
    pop.open = false;
    renderActive();
    animate();
    document.removeEventListener("pointerdown", outside, true);
    document.removeEventListener("keydown", escape);
    if (hadFocus) icons[pop.shown].focus({ preventScroll: true });
  }
  function outside(e) {
    if (Object.values(icons).some((b) => b.contains(e.target))) return;
    const s = stage.getBoundingClientRect();
    const x = e.clientX - s.left;
    const y = e.clientY - s.top;
    const inBulge = x >= BAR && x <= BAR + bulge.w && y >= bulge.y && y <= bulge.y + bulge.h;
    if (!inBulge || !popLayer.contains(e.target)) close();
  }
  function escape(e) {
    if (e.key === "Escape") close();
  }
  for (const [k, b] of Object.entries(icons)) b.addEventListener("click", () => iconClicked(k));
  popLayer.addEventListener("click", (e) => {
    const sw = e.target.closest(".po-switch");
    if (sw) {
      wifiOn = !wifiOn;
      sw.setAttribute("aria-checked", String(wifiOn));
      sw.classList.toggle("is-off", !wifiOn);
      renderWifiIcon();
      setTimeout(() => {
        renderContents();
        renderActive();
        measure();
        contents.wifi.querySelector(".po-switch")?.focus({ preventScroll: true });
        if (pop.open && pop.shown === "wifi") animate();
      }, reduceMotion ? 0 : 200);
      return;
    }
    if (e.target.closest("[data-close]")) close();
  });
  const resize = () => {
    height = stage.clientHeight;
    rimSvg.setAttribute("width", EXPANDED);
    rimSvg.setAttribute("height", height);
    rimSvg.setAttribute("viewBox", `0 0 ${EXPANDED} ${height}`);
    glass.style.height = `${height}px`;
    if (pop.open) {
      measure();
      pop.anchorY = anchorOf(pop.shown);
      tween = null;
      const size = sizes[pop.shown];
      const top = placeTop(pop.anchorY, size.h, height);
      bulge = { y: top, w: size.w, h: size.h };
      contentTop = top;
    }
    apply();
  };
  mount(host, stage);
  new ResizeObserver(resize).observe(stage);
  resize();
  fitDock();
  whenVisible(host, (visible) => {
    if (visible) tick();
    else {
      clearTimeout(clockTimer);
      close();
    }
  }, 0);
  tick();
}
document.querySelectorAll('.panel-host[data-panel="sidebar"]').forEach(setup);
