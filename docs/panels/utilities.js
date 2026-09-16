import { fit, whenVisible, mount, reduceMotion } from "./shared.js";
const ICON = {
  "coffee": '<path d="M3 14c.83 .642 2.077 1.017 3.5 1c1.423 .017 2.67 -.358 3.5 -1c.83 -.642 2.077 -1.017 3.5 -1c1.423 -.017 2.67 .358 3.5 1"/> <path d="M8 3a2.4 2.4 0 0 0 -1 2a2.4 2.4 0 0 0 1 2"/> <path d="M12 3a2.4 2.4 0 0 0 -1 2a2.4 2.4 0 0 0 1 2"/> <path d="M3 10h14v5a6 6 0 0 1 -6 6h-2a6 6 0 0 1 -6 -6v-5"/> <path d="M16.746 16.726a3 3 0 1 0 .252 -5.555"/>',
  "volume1": '<path d="M15 8a5 5 0 0 1 0 8"/> <path d="M6 15h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l3.5 -4.5a.8 .8 0 0 1 1.5 .5v14a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5"/>',
  "volume2": '<path d="M15 8a5 5 0 0 1 0 8"/> <path d="M17.7 5a9 9 0 0 1 0 14"/> <path d="M6 15h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l3.5 -4.5a.8 .8 0 0 1 1.5 .5v14a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5"/>',
  "volume3": '<path d="M15 8a5 5 0 0 1 0 8"/> <path d="M17.7 5a9 9 0 0 1 0 14"/> <path d="M6 15h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l3.5 -4.5a.8 .8 0 0 1 1.5 .5v14a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5"/>',
  "volumeOff": '<path d="M6 15h-2a1 1 0 0 1 -1 -1v-4a1 1 0 0 1 1 -1h2l3.5 -4.5a.8 .8 0 0 1 1.5 .5v14a.8 .8 0 0 1 -1.5 .5l-3.5 -4.5"/> <path d="M16 10l4 4m0 -4l-4 4"/>',
  "mic": '<path d="M19 9a1 1 0 0 1 1 1a8 8 0 0 1 -6.999 7.938l-.001 2.062h3a1 1 0 0 1 0 2h-8a1 1 0 0 1 0 -2h3v-2.062a8 8 0 0 1 -7 -7.938a1 1 0 1 1 2 0a6 6 0 0 0 12 0a1 1 0 0 1 1 -1m-7 -8a4 4 0 0 1 4 4v5a4 4 0 1 1 -8 0v-5a4 4 0 0 1 4 -4"/>',
  "micOff": '<path d="M3 3l18 18"/> <path d="M9 5a3 3 0 0 1 6 0v5a3 3 0 0 1 -.13 .874m-2 2a3 3 0 0 1 -3.87 -2.872v-1"/> <path d="M5 10a7 7 0 0 0 10.846 5.85m2 -2a6.967 6.967 0 0 0 1.152 -3.85"/> <path d="M8 21l8 0"/> <path d="M12 17l0 4"/>',
  "selector": '<path d="M8 9l4 -4l4 4"/> <path d="M16 15l-4 4l-4 -4"/>',
  "wifi": '<path d="M12 18l.01 0"/> <path d="M9.172 15.172a4 4 0 0 1 5.656 0"/> <path d="M6.343 12.343a8 8 0 0 1 11.314 0"/> <path d="M3.515 9.515c4.686 -4.687 12.284 -4.687 17 0"/>',
  "wifiOff": '<path d="M12 18l.01 0"/> <path d="M9.172 15.172a4 4 0 0 1 5.656 0"/> <path d="M6.343 12.343a7.963 7.963 0 0 1 3.864 -2.14m4.163 .155a7.965 7.965 0 0 1 3.287 2"/> <path d="M3.515 9.515a12 12 0 0 1 3.544 -2.455m3.101 -.92a12 12 0 0 1 10.325 3.374"/> <path d="M3 3l18 18"/>',
  "bluetooth": '<path d="M7 8l10 8l-5 4l0 -16l5 4l-10 8"/>',
  "contrast": '<path d="M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0"/> <path d="M12 17a5 5 0 0 0 0 -10v10"/>',
  "sunset": '<path d="M4 12a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/> <path d="M21 12a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/> <path d="M6.307 5.893l.7 .7a1 1 0 0 1 -1.414 1.414l-.7 -.7a1 1 0 0 1 1.414 -1.414"/> <path d="M19.107 5.893a1 1 0 0 1 0 1.414l-.7 .7a1 1 0 0 1 -1.414 -1.414l.7 -.7a1 1 0 0 1 1.414 0"/> <path d="M12 3a1 1 0 0 1 1 1v1a1 1 0 0 1 -2 0v-1a1 1 0 0 1 1 -1"/> <path d="M3 16h18a1 1 0 0 1 0 2h-18a1 1 0 0 1 0 -2"/> <path d="M12 8a5 5 0 0 1 4.583 7.002h-9.166a5 5 0 0 1 4.583 -7.002"/> <path d="M12 19a1 1 0 0 1 0 2h-5a1 1 0 0 1 0 -2z"/> <path d="M17 19a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/>',
  "capture": '<path d="M4 8v-2a2 2 0 0 1 2 -2h2"/> <path d="M4 16v2a2 2 0 0 0 2 2h2"/> <path d="M16 4h2a2 2 0 0 1 2 2v2"/> <path d="M16 20h2a2 2 0 0 0 2 -2v-2"/> <path d="M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0"/>',
  "desktop": '<path d="M3 5a1 1 0 0 1 1 -1h16a1 1 0 0 1 1 1v10a1 1 0 0 1 -1 1h-16a1 1 0 0 1 -1 -1v-10"/> <path d="M7 20h10"/> <path d="M9 16v4"/> <path d="M15 16v4"/>',
  "picker": '<path d="M11 7l6 6"/> <path d="M4 16l11.7 -11.7a1 1 0 0 1 1.4 0l2.6 2.6a1 1 0 0 1 0 1.4l-11.7 11.7h-4v-4"/>',
  "lock": '<path d="M12 2a5 5 0 0 1 5 5v3a3 3 0 0 1 3 3v6a3 3 0 0 1 -3 3h-10a3 3 0 0 1 -3 -3v-6a3 3 0 0 1 3 -3v-3a5 5 0 0 1 5 -5m0 12a2 2 0 0 0 -1.995 1.85l-.005 .15a2 2 0 1 0 2 -2m0 -10a3 3 0 0 0 -3 3v3h6v-3a3 3 0 0 0 -3 -3"/>',
  "settings": '<path d="M14.647 4.081a.724 .724 0 0 0 1.08 .448c2.439 -1.485 5.23 1.305 3.745 3.744a.724 .724 0 0 0 .447 1.08c2.775 .673 2.775 4.62 0 5.294a.724 .724 0 0 0 -.448 1.08c1.485 2.439 -1.305 5.23 -3.744 3.745a.724 .724 0 0 0 -1.08 .447c-.673 2.775 -4.62 2.775 -5.294 0a.724 .724 0 0 0 -1.08 -.448c-2.439 1.485 -5.23 -1.305 -3.745 -3.744a.724 .724 0 0 0 -.447 -1.08c-2.775 -.673 -2.775 -4.62 0 -5.294a.724 .724 0 0 0 .448 -1.08c-1.485 -2.439 1.305 -5.23 3.744 -3.745a.722 .722 0 0 0 1.08 -.447c.673 -2.775 4.62 -2.775 5.294 0zm-2.647 4.919a3 3 0 1 0 0 6a3 3 0 0 0 0 -6"/>'
};
const FILLED = new Set(["mic", "sunset", "lock", "settings"]);
const SVGNS = "http://www.w3.org/2000/svg";
const WIDTH = 430;
const HEIGHT = 2 * 16 + 68 + 141 + 161 + 2 * 12;
const VOLUME_STEP = 1 / 16;
function el(tag, props = {}, ...kids) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null || v === false) continue;
    if (k === "class") node.className = v;
    else if (k === "text") node.textContent = v;
    else if (k === "style") node.style.cssText = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) node.append(kid);
  return node;
}
function icon(name, size) {
  const s = document.createElementNS(SVGNS, "svg");
  s.setAttribute("viewBox", "0 0 24 24");
  s.setAttribute("width", size);
  s.setAttribute("height", size);
  s.setAttribute("aria-hidden", "true");
  s.setAttribute("class", `ic ${FILLED.has(name) ? "ic-fill" : "ic-line"}`);
  s.innerHTML = ICON[name];
  return s;
}
const two = (n) => String(n).padStart(2, "0");
const hhmm = (d) => `${two(d.getHours())}:${two(d.getMinutes())}`;
function keepAwakeSubtitle(since, now) {
  if (!since) return "Mac sleeps normally";
  if (since.toDateString() === now.toDateString()) return `Active since ${hhmm(since)}`;
  const y = new Date(now);
  y.setDate(y.getDate() - 1);
  if (since.toDateString() === y.toDateString()) return `Active since yesterday, ${hhmm(since)}`;
  return `Active since ${two(since.getDate())}.${two(since.getMonth() + 1)}., ${hhmm(since)}`;
}
function volumeIcon(volume, muted) {
  if (muted || volume <= 1e-3) return "volumeOff";
  if (volume < 0.34) return "volume1";
  if (volume < 0.67) return "volume2";
  return "volume3";
}
const DEVICES = [
  { id: 61, name: "External Display", output: true, input: true },
  { id: 100, name: "Built-in Microphone", output: false, input: true },
  { id: 93, name: "Built-in Speakers", output: true, input: false },
  { id: 107, name: "Headphones", output: true, input: false }
];
function build(host2) {
  const since = new Date();
  since.setHours(0, 0, 0, 0);
  since.setHours(-15, 30);
  const state = {
    keepAwakeSince: since,
    volume: 0.45,
    muted: false,
    output: 107,
    input: 100,
    toggles: { wifi: true, microphone: true, bluetooth: true, darkMode: true, nightShift: false }
  };
  const stage = el("div", { class: "panel-stage util" });
  const chip = el("span", { class: "ka-chip", "aria-hidden": "true" }, icon("coffee", 19));
  const subtitle = el("span", { class: "sec", style: "font-size:12px" });
  const knob = el("span", { class: "sw-knob" });
  const sw = el("button", { type: "button", class: "switch", role: "switch", "aria-label": "Keep Awake" }, knob);
  const renderKeepAwake = () => {
    const on = !!state.keepAwakeSince;
    stage.classList.toggle("ka-on", on);
    sw.setAttribute("aria-checked", String(on));
    subtitle.textContent = keepAwakeSubtitle(state.keepAwakeSince, new Date());
  };
  sw.addEventListener("click", () => {
    state.keepAwakeSince = state.keepAwakeSince ? null : new Date();
    renderKeepAwake();
  });
  const keepAwake = el(
    "div",
    { class: "u-card", style: "height:68px" },
    el(
      "div",
      { class: "row", style: "gap:12px" },
      chip,
      el("div", { class: "col texts" }, el("span", { style: "font-size:14px;font-weight:500", text: "Keep Awake" }), subtitle),
      el("span", { style: "flex:1;min-width:8px" }),
      sw
    )
  );
  const level = el("span", { class: "sec level", "aria-hidden": "true" });
  const muteIcon = el("span", { class: "mute-ic" });
  const mute = el("button", { type: "button", class: "tile mute" }, muteIcon);
  const fill = el("span", { class: "sl-fill" });
  const sKnob = el("span", { class: "sl-knob" });
  const slider = el("div", { class: "slider", role: "slider", tabindex: "0", "aria-label": "Volume", "aria-valuemin": "0", "aria-valuemax": "100" }, fill, sKnob);
  const renderVolume = () => {
    const v = state.muted ? 0 : Math.min(Math.max(state.volume, 0), 1);
    const w = slider.clientWidth || 318;
    const h = 24;
    const f = h + v * (w - h);
    fill.style.width = `${f}px`;
    fill.style.opacity = v > 0 ? 1 : 0;
    sKnob.style.transform = `translateX(${f - h + 2}px)`;
    const pct = Math.round(state.volume * 100);
    level.textContent = state.muted ? "Muted" : `${pct} %`;
    slider.setAttribute("aria-valuenow", String(state.muted ? 0 : pct));
    slider.setAttribute("aria-valuetext", state.muted ? "Muted" : `${pct} %`);
    const name = volumeIcon(state.volume, state.muted);
    if (muteIcon.dataset.name !== name) {
      muteIcon.dataset.name = name;
      muteIcon.replaceChildren(icon(name, 16));
      if (!reduceMotion && muteIcon.isConnected) muteIcon.animate([{ transform: "scale(0.5)", opacity: 0 }, { transform: "none", opacity: 1 }], { duration: 300, easing: "cubic-bezier(0.38, 1.21, 0.22, 1)" });
    }
    const label = state.muted ? "Unmute" : "Mute";
    mute.setAttribute("aria-label", label);
    mute.title = label;
  };
  mute.addEventListener("click", () => {
    state.muted = !state.muted;
    renderVolume();
  });
  const setVolume = (v) => {
    state.volume = Math.min(Math.max(v, 0), 1);
    state.muted = false;
    renderVolume();
  };
  const fromPointer = (e) => {
    const r = slider.getBoundingClientRect();
    const scale = r.width / (slider.clientWidth || r.width);
    const h = 24 * scale;
    setVolume((e.clientX - r.left - h / 2) / Math.max(r.width - h, 1));
  };
  slider.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    slider.setPointerCapture(e.pointerId);
    slider.classList.add("is-dragging");
    fromPointer(e);
  });
  slider.addEventListener("pointermove", (e) => {
    if (slider.hasPointerCapture(e.pointerId)) fromPointer(e);
  });
  const endDrag = () => slider.classList.remove("is-dragging");
  slider.addEventListener("pointerup", endDrag);
  slider.addEventListener("pointercancel", endDrag);
  slider.addEventListener("keydown", (e) => {
    const map = { ArrowRight: VOLUME_STEP, ArrowUp: VOLUME_STEP, ArrowLeft: -VOLUME_STEP, ArrowDown: -VOLUME_STEP, Home: -1, End: 1 };
    if (!(e.key in map)) return;
    e.preventDefault();
    setVolume(state.volume + map[e.key]);
  });
  let openMenu = null;
  const closeMenu = (focusBack = false) => {
    if (!openMenu) return;
    openMenu.menu.remove();
    openMenu.button.setAttribute("aria-expanded", "false");
    if (focusBack) openMenu.button.focus();
    openMenu = null;
  };
  function deviceButton(scope, iconName, caption) {
    const name = el("span", { class: "dev-name" });
    const button = el(
      "button",
      { type: "button", class: "tile dev", "aria-haspopup": "menu", "aria-expanded": "false" },
      el("span", { class: "dev-ic sec" }, icon(iconName, 16)),
      el("span", { class: "col texts" }, el("span", { class: "sec", style: "font-size:11px", text: caption }), name),
      el("span", { style: "flex:1;min-width:4px" }),
      el("span", { class: "sec", style: "display:flex" }, icon("selector", 13))
    );
    const list = () => DEVICES.filter((d) => d[scope]);
    const render = () => {
      const current = DEVICES.find((d) => d.id === state[scope]);
      name.textContent = current?.name ?? "No Device";
      button.setAttribute("aria-label", `${caption}: ${name.textContent}`);
      button.title = `${caption}: ${name.textContent}`;
    };
    const choose = (id) => {
      state[scope] = id;
      render();
      closeMenu(true);
    };
    button.addEventListener("click", (e) => {
      const wasOpen = openMenu?.button === button;
      closeMenu();
      if (wasOpen) return;
      const items = list().map((d) => el("button", {
        type: "button",
        class: "menu-item",
        role: "menuitemradio",
        "aria-checked": String(d.id === state[scope]),
        onclick: (ev) => {
          ev.stopPropagation();
          choose(d.id);
        }
      }, el("span", { class: "check", "aria-hidden": "true", text: d.id === state[scope] ? "✓" : "" }), el("span", { text: d.name })));
      const menu = el("div", { class: "dev-menu", role: "menu", "aria-label": caption }, items);
      stage.append(menu);
      const s = stage.getBoundingClientRect();
      const scale = s.width / WIDTH;
      const b = button.getBoundingClientRect();
      const px = e.clientX && e.detail ? e.clientX : b.left + b.width / 2;
      const py = e.clientY && e.detail ? e.clientY : b.top + b.height / 2;
      const index = Math.max(0, list().findIndex((d) => d.id === state[scope]));
      let x = (px - s.left) / scale - 14;
      let y = (py - s.top) / scale - (5 + index * 24 + 12);
      x = Math.min(Math.max(x, 8), WIDTH - menu.offsetWidth - 8);
      y = Math.min(Math.max(y, 8), HEIGHT - menu.offsetHeight - 8);
      menu.style.left = `${x}px`;
      menu.style.top = `${y}px`;
      button.setAttribute("aria-expanded", "true");
      openMenu = { menu, button };
      items[index].focus({ preventScroll: true });
      menu.addEventListener("keydown", (k) => {
        const i = items.indexOf(document.activeElement);
        if (k.key === "ArrowDown" || k.key === "ArrowUp") {
          k.preventDefault();
          const n = items[(i + (k.key === "ArrowDown" ? 1 : items.length - 1)) % items.length];
          n.focus({ preventScroll: true });
        } else if (k.key === "Escape" || k.key === "Tab") {
          k.preventDefault();
          closeMenu(true);
        }
      });
      menu.addEventListener("pointermove", (m) => {
        const item = m.target.closest(".menu-item");
        if (item && document.activeElement !== item) item.focus({ preventScroll: true });
      });
    });
    render();
    return button;
  }
  document.addEventListener("pointerdown", (e) => {
    if (openMenu && !openMenu.menu.contains(e.target) && !openMenu.button.contains(e.target)) closeMenu();
  });
  const audio = el(
    "div",
    { class: "u-card", style: "height:141px" },
    el(
      "div",
      { class: "col", style: "gap:10px;align-items:stretch;width:100%" },
      el(
        "div",
        { class: "row", style: "justify-content:space-between;height:17px" },
        el("span", { style: "font-size:14px;font-weight:500", text: "Sound" }),
        level
      ),
      el("div", { class: "row", style: "gap:10px" }, mute, slider),
      el(
        "div",
        { class: "row", style: "gap:8px" },
        deviceButton("output", "volume2", "Output"),
        deviceButton("input", "mic", "Input")
      )
    )
  );
  const LOOKS = {
    wifi: (on) => ({ icon: on ? "wifi" : "wifiOff", help: on ? "Wi-Fi On" : "Wi-Fi Off" }),
    microphone: (on) => ({ icon: on ? "mic" : "micOff", help: on ? "Microphone On" : "Microphone Muted" }),
    bluetooth: (on) => ({ icon: "bluetooth", help: on ? "Bluetooth On, opens Settings" : "Bluetooth Off, opens Settings" }),
    darkMode: (on) => ({ icon: "contrast", help: on ? "Dark Mode On" : "Dark Mode Off" }),
    nightShift: (on) => ({ icon: "sunset", help: on ? "Night Shift On" : "Night Shift Off" })
  };
  const ACTIONS = [
    { icon: "capture", help: "Screenshot or Recording (⌘⇧5)" },
    { icon: "desktop", help: "Show Desktop" },
    { icon: "picker", help: "Color Picker, copies the hex value" },
    { icon: "lock", help: "Lock Screen (⌃⌘Q)" },
    { icon: "settings", help: "Settings (SUPER+,)" }
  ];
  const qt = (help) => el("button", { type: "button", class: "qt" });
  const stateful = Object.keys(LOOKS).map((key) => {
    const b = qt();
    const render = () => {
      const on = state.toggles[key];
      const look = LOOKS[key](on);
      b.classList.toggle("on", on);
      if (key !== "bluetooth") b.setAttribute("aria-pressed", String(on));
      b.setAttribute("aria-label", look.help);
      b.title = look.help;
      if (b.dataset.icon !== look.icon) {
        b.dataset.icon = look.icon;
        b.replaceChildren(icon(look.icon, 21));
      }
    };
    if (key !== "bluetooth") b.addEventListener("click", () => {
      state.toggles[key] = !state.toggles[key];
      render();
    });
    render();
    return b;
  });
  const actions = ACTIONS.map((a) => {
    const b = qt();
    b.setAttribute("aria-label", a.help);
    b.title = a.help;
    b.append(icon(a.icon, 21));
    return b;
  });
  const toggles = el(
    "div",
    { class: "u-card", style: "height:161px" },
    el(
      "div",
      { class: "col", style: "gap:12px;align-items:stretch;width:100%" },
      el("span", { style: "font-size:14px;font-weight:500;line-height:17px", text: "Quick Toggles" }),
      el(
        "div",
        { class: "col", style: "gap:8px;align-items:stretch" },
        el("div", { class: "qt-row", role: "group", "aria-label": "Switches" }, stateful),
        el("div", { class: "qt-row", role: "group", "aria-label": "Actions" }, actions)
      )
    )
  );
  const slide = el(
    "div",
    { class: "util-slide" },
    el("div", { class: "glass util-glass", "aria-hidden": "true" }),
    el("div", { class: "util-cards" }, keepAwake, audio, toggles)
  );
  stage.append(el("div", { class: "util-clip" }, slide));
  fit(host2, stage, WIDTH, HEIGHT);
  mount(host2, stage);
  renderKeepAwake();
  renderVolume();
  let minute = 0;
  whenVisible(host2, (visible) => {
    clearInterval(minute);
    if (visible) {
      stage.classList.add("is-open");
      renderKeepAwake();
      renderVolume();
      minute = setInterval(renderKeepAwake, 6e4);
    } else {
      closeMenu();
      stage.classList.remove("is-open");
    }
  });
}
const host = document.querySelector('.panel-host[data-panel="utilities"]');
if (host) build(host);
