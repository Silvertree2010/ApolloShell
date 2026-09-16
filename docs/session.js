const TAU = Math.PI * 2;
const clamp01 = (x) => Math.min(Math.max(x, 0), 1);
const easeOutCubic = (x) => 1 - (1 - x) ** 3;
const easeInOutCubic = (x) => x < 0.5 ? 4 * x * x * x : 1 - (-2 * x + 2) ** 3 / 2;
const easeInOutSine = (x) => (1 - Math.cos(Math.PI * x)) / 2;
function cubicBezier(x, x1, y1, x2, y2) {
  const coord = (s2, a, b) => 3 * (1 - s2) * (1 - s2) * s2 * a + 3 * (1 - s2) * s2 * s2 * b + s2 * s2 * s2;
  const slope = (s2, a, b) => 3 * (1 - s2) * (1 - s2) * a + 6 * (1 - s2) * s2 * (b - a) + 3 * s2 * s2 * (1 - b);
  let s = x;
  for (let i = 0; i < 8; i++) {
    const d = slope(s, x1, x2);
    if (Math.abs(d) <= 1e-6) break;
    s = clamp01(s - (coord(s, x1, x2) - x) / d);
  }
  return coord(s, y1, y2);
}
const menuCurve = (x) => cubicBezier(x, 0.38, 1.21, 0.22, 1);
const IDLE_SPEED = TAU / 9;
const REST_GLOW = 0.45;
const SLEEP_GLOW = 0.04;
const GREET = 1.4;
const FAREWELL = 1.1;
const SLEEP_SETTLE = 2.6;
const THINK_SETTLE = 0.8;
const THINK_SPEED = 0.3;
const WOBBLE_DEG = 7;
const WOBBLE_PERIOD = 2.8;
const DOT_PERIOD = 1.2;
const REST_ANGLE = 0.12 * Math.PI;
const DURATION = { greet: GREET, farewell: FAREWELL };
const REACTION = { logOut: "think", shutDown: "farewell", restart: "farewell", sleep: "sleep" };
const reactingTo = (action) => action ? REACTION[action] : "idle";
const restingFor = (action) => {
  const r = reactingTo(action);
  return DURATION[r] ? "idle" : r;
};
function angle(reaction, t, start) {
  const w = IDLE_SPEED;
  switch (reaction) {
    case "greet":
      return start + w * t + TAU * 1.25 * easeOutCubic(clamp01(t / GREET));
    case "farewell":
      return start + w * t + TAU * easeInOutCubic(clamp01(t / FAREWELL));
    case "sleep": {
      const p = clamp01(t / SLEEP_SETTLE);
      return start + w * SLEEP_SETTLE / 2 * (1 - (1 - p) * (1 - p));
    }
    case "think": {
      const p = clamp01(t / THINK_SETTLE);
      const brake = w * (1 - THINK_SPEED) * THINK_SETTLE / 2 * (1 - (1 - p) * (1 - p));
      return start + w * THINK_SPEED * t + brake;
    }
    default:
      return start + w * t;
  }
}
function basePose(moonAngle) {
  return {
    moonAngle,
    moonSpeed: IDLE_SPEED,
    moonOpacity: 1,
    orbitOpacity: 1,
    orbitTilt: 0,
    planetScale: 1,
    glow: REST_GLOW,
    night: 0,
    stars: [0, 0, 0],
    dots: [0, 0, 0]
  };
}
function poseAt(reaction, time, start) {
  const t = Math.max(0, time);
  const pose = basePose(angle(reaction, t, start));
  const h = 0.01;
  pose.moonSpeed = (angle(reaction, t + h, start) - angle(reaction, Math.max(0, t - h), start)) / (t + h - Math.max(0, t - h));
  switch (reaction) {
    case "idle": {
      const breath = Math.sin(TAU * t / 4.4);
      pose.glow = REST_GLOW + 0.15 * breath;
      pose.planetScale = 1 + 0.012 * breath;
      break;
    }
    case "greet":
      pose.planetScale = 0.7 + 0.3 * menuCurve(clamp01(t / 0.5));
      pose.orbitOpacity = easeOutCubic(clamp01((t - 0.1) / 0.45));
      pose.moonOpacity = easeOutCubic(clamp01((t - 0.15) / 0.35));
      pose.glow = REST_GLOW + 0.4 * Math.sin(Math.PI * clamp01((t - 0.1) / 1.1)) ** 2;
      break;
    case "farewell": {
      const dip = t < 0.35 ? Math.sin(Math.PI * t / 0.35) : 0;
      const rebound = t >= 0.35 ? Math.sin(Math.PI * clamp01((t - 0.35) / 0.55)) : 0;
      pose.planetScale = 1 - 0.1 * dip + 0.04 * rebound;
      pose.glow = REST_GLOW + 0.45 * Math.sin(Math.PI * clamp01(t / FAREWELL)) ** 2;
      break;
    }
    case "sleep": {
      const dusk = easeInOutSine(clamp01(t / 1.6));
      pose.night = easeInOutSine(clamp01((t - 0.1) / 1.6));
      pose.glow = REST_GLOW - (REST_GLOW - SLEEP_GLOW) * dusk;
      pose.orbitOpacity = 1 - 0.55 * dusk;
      pose.moonOpacity = 1 - 0.35 * dusk;
      pose.planetScale = 1 - 0.04 * dusk + 6e-3 * Math.sin(TAU * t / 5) * dusk;
      const starsIn = easeInOutSine(clamp01((t - 0.5) / 1.2));
      const periods = [2.3, 3.1, 2.7];
      const phases = [0, 2.1, 4];
      pose.stars = [0, 1, 2].map((i) => starsIn * (0.6 + 0.4 * Math.sin(TAU * t / periods[i] + phases[i])));
      break;
    }
    case "think": {
      const ramp = easeInOutSine(clamp01(t / 0.5));
      pose.orbitTilt = WOBBLE_DEG * Math.sin(TAU * t / WOBBLE_PERIOD) * ramp;
      pose.glow = REST_GLOW + 0.08 * Math.sin(TAU * t / DOT_PERIOD) * ramp;
      pose.dots = [0, 1, 2].map((i) => {
        let phase = (t / DOT_PERIOD - i * 0.16) % 1;
        if (phase < 0) phase += 1;
        return ramp * (0.35 + 0.65 * Math.max(0, Math.sin(TAU * phase)));
      });
      break;
    }
  }
  return pose;
}
function stillPose(reaction) {
  const pose = basePose(REST_ANGLE);
  pose.moonSpeed = 0;
  if (reaction === "sleep") {
    Object.assign(pose, { night: 1, glow: SLEEP_GLOW, orbitOpacity: 0.45, moonOpacity: 0.65, planetScale: 0.96, stars: [0.95, 0.65, 0.8] });
  } else if (reaction === "think") {
    pose.dots = [1, 0.7, 0.4];
  }
  return pose;
}
const PLANET_R = 16.5;
const ORBIT_A = 33;
const ORBIT_B = 10.5;
const ORBIT_TILT = -16;
const MOON_R = 3.6;
const MOON_GAP = 1.3;
const LINE = 1.25;
const STARS = [[15, 17, 3.4], [62, 13, 2.4], [66, 64, 2.9]];
function readColors() {
  const css = getComputedStyle(document.documentElement);
  const get = (name, fallback) => css.getPropertyValue(name).trim() || fallback;
  return {
    accent: get("--gold", "#e2a84b"),
    onAccent: get("--gold-ink", "#1b1204"),
    neutral: get("--marble", "#ece8e1")
  };
}
function hexToRgb(hex) {
  const n = parseInt(hex.replace("#", ""), 16);
  return [n >> 16 & 255, n >> 8 & 255, n & 255];
}
const rgba = ([r, g, b], a) => `rgba(${r}, ${g}, ${b}, ${a})`;
const mix = ([r, g, b], [r2, g2, b2], t) => [r + (r2 - r) * t, g + (g2 - g) * t, b + (b2 - b) * t].map(Math.round);
const scratches = new WeakMap();
function scratchFor(canvas) {
  let scratch = scratches.get(canvas);
  if (!scratch) {
    scratch = document.createElement("canvas");
    scratches.set(canvas, scratch);
  }
  if (scratch.width !== canvas.width || scratch.height !== canvas.height) {
    scratch.width = canvas.width;
    scratch.height = canvas.height;
  }
  return scratch;
}
function drawPose(ctx, size, pose, colors) {
  const k = size / 80;
  const c = size / 2;
  const tilt = (ORBIT_TILT + pose.orbitTilt) * Math.PI / 180;
  const a = ORBIT_A * k;
  const b = ORBIT_B * k;
  const accent = hexToRgb(colors.accent);
  const onAccent = hexToRgb(colors.onAccent);
  const neutral = hexToRgb(colors.neutral);
  const moonColor = (op) => rgba(neutral, 0.9 * op);
  const orbitPoint = (th) => {
    const x = a * Math.cos(th);
    const y = b * Math.sin(th);
    return [c + x * Math.cos(tilt) - y * Math.sin(tilt), c + x * Math.sin(tilt) + y * Math.cos(tilt)];
  };
  const arcPath = (from, to) => {
    const p = new Path2D();
    for (let i = 0; i <= 48; i++) {
      const [x, y] = orbitPoint(from + (to - from) * i / 48);
      i === 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p;
  };
  const circle = (x, y, r) => {
    const p = new Path2D();
    p.arc(x, y, Math.max(r, 0), 0, TAU);
    return p;
  };
  const moonRadius = (dot) => dot.radius * k * (1 + 0.12 * Math.sin(dot.theta));
  const radius = PLANET_R * k * pose.planetScale;
  const planet = circle(c, c, radius);
  const shadowOffset = radius * (2.2 - 1.6 * pose.night);
  const hasNight = pose.night > 1e-3;
  const shadow = circle(c - shadowOffset * 0.72, c - shadowOffset * 0.7, radius);
  ctx.clearRect(0, 0, size, size);
  ctx.lineCap = "round";
  ctx.lineWidth = LINE * k;
  const moon = { theta: pose.moonAngle, radius: MOON_R, opacity: 1 };
  const trail = [];
  const strength = clamp01((Math.abs(pose.moonSpeed) - 2 * IDLE_SPEED) / (6 * IDLE_SPEED));
  if (strength > 0.01) {
    const spacing = Math.min(Math.abs(pose.moonSpeed) * 0.028, 0.24) * (pose.moonSpeed < 0 ? -1 : 1);
    for (let i = 1; i <= 5; i++) {
      const fade = 1 - i / 6;
      trail.push({ theta: pose.moonAngle - spacing * i, radius: MOON_R * (0.55 + 0.4 * fade), opacity: 0.5 * fade * strength });
    }
  }
  const dots = [...trail].reverse().concat([moon]);
  const fillDots = (list) => {
    for (const dot of list) {
      const [x, y] = orbitPoint(dot.theta);
      ctx.fillStyle = moonColor(pose.moonOpacity * dot.opacity);
      ctx.fill(circle(x, y, moonRadius(dot)));
    }
  };
  const litLayer = (paint) => {
    ctx.save();
    ctx.clip(planet);
    if (hasNight) {
      const outside = new Path2D();
      outside.rect(0, 0, size, size);
      outside.addPath(shadow);
      ctx.clip(outside, "evenodd");
    }
    paint();
    ctx.restore();
  };
  ctx.strokeStyle = rgba(neutral, 0.2 * pose.orbitOpacity);
  ctx.stroke(arcPath(Math.PI, TAU));
  fillDots(dots.filter((d) => Math.sin(d.theta) < 0));
  if (pose.glow > 0.01) {
    const scale = ctx.getTransform().a;
    const scratch = scratchFor(ctx.canvas);
    const sctx = scratch.getContext("2d");
    sctx.setTransform(1, 0, 0, 1, 0, 0);
    sctx.clearRect(0, 0, scratch.width, scratch.height);
    sctx.setTransform(scale, 0, 0, scale, 0, 0);
    sctx.fillStyle = rgba(accent, 1);
    sctx.fill(planet);
    if (hasNight) {
      sctx.globalCompositeOperation = "destination-out";
      sctx.fill(shadow);
      sctx.globalCompositeOperation = "source-over";
    }
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.shadowColor = rgba(accent, pose.glow);
    ctx.shadowBlur = 18 * k * scale;
    ctx.drawImage(scratch, 0, 0);
    ctx.restore();
  }
  if (hasNight) {
    ctx.fillStyle = rgba(neutral, 0.14);
    ctx.fill(planet);
  }
  litLayer(() => {
    const x0 = c - radius + radius * 2 * 0.2;
    const x1 = c + radius - radius * 2 * 0.2;
    const g = ctx.createLinearGradient(x0, c - radius, x1, c + radius);
    g.addColorStop(0, rgba(mix(accent, [255, 255, 255], 0.28), 1));
    g.addColorStop(0.5, rgba(accent, 1));
    g.addColorStop(1, rgba(mix(accent, [0, 0, 0], 0.18), 1));
    ctx.fillStyle = g;
    ctx.fill(planet);
  });
  pose.dots.forEach((op, i) => {
    if (op <= 0.01) return;
    ctx.fillStyle = rgba(onAccent, op);
    ctx.fill(circle(c + (i - 1) * 6.2 * k, c - 1.5 * k, 2.1 * k));
  });
  const front = arcPath(0, Math.PI);
  ctx.save();
  const outsidePlanet = new Path2D();
  outsidePlanet.rect(0, 0, size, size);
  outsidePlanet.addPath(planet);
  ctx.clip(outsidePlanet, "evenodd");
  ctx.strokeStyle = rgba(neutral, 0.32 * pose.orbitOpacity);
  ctx.stroke(front);
  ctx.restore();
  ctx.save();
  ctx.clip(planet);
  ctx.strokeStyle = rgba(onAccent, 0.5 * pose.orbitOpacity);
  ctx.stroke(front);
  ctx.restore();
  if (Math.sin(moon.theta) >= 0 && pose.moonOpacity > 0.01) {
    const [x, y] = orbitPoint(moon.theta);
    ctx.save();
    ctx.clip(planet);
    ctx.globalCompositeOperation = "destination-out";
    ctx.fillStyle = `rgba(0, 0, 0, ${pose.moonOpacity})`;
    ctx.fill(circle(x, y, moonRadius(moon) + MOON_GAP * k));
    ctx.restore();
  }
  fillDots(dots.filter((d) => Math.sin(d.theta) >= 0));
  STARS.forEach(([sx, sy, sr], i) => {
    const brightness = pose.stars[i];
    if (brightness <= 0.01) return;
    const x = sx * k;
    const y = sy * k;
    const r = sr * k;
    const w = r * 0.16;
    const p = new Path2D();
    p.moveTo(x, y - r);
    p.quadraticCurveTo(x + w, y - w, x + r, y);
    p.quadraticCurveTo(x + w, y + w, x, y + r);
    p.quadraticCurveTo(x - w, y + w, x - r, y);
    p.quadraticCurveTo(x - w, y - w, x, y - r);
    ctx.fillStyle = rgba(neutral, 0.75 * brightness);
    ctx.fill(p);
  });
}
const ORDER = ["logOut", "shutDown", "sleep", "restart"];
const CROSSFADE = 0.18;
function setupMenu(root) {
  const canvas = root.querySelector(".emblem");
  const panel = root.querySelector(".session-panel");
  const buttons = [...root.querySelectorAll("button[data-action]")];
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const colors = readColors();
  const now = () => performance.now() / 1e3;
  const layers = [document.createElement("canvas"), document.createElement("canvas")];
  const ctx = canvas.getContext("2d");
  let size = 80;
  let dpr = 1;
  function resize() {
    size = canvas.clientWidth || 80;
    dpr = Math.min(devicePixelRatio || 1, 3);
    for (const c of [canvas, ...layers]) {
      c.width = Math.round(size * dpr);
      c.height = Math.round(size * dpr);
    }
  }
  let timeline = { reaction: "idle", start: 0, angle: REST_ANGLE };
  let previous = null;
  let hovered = null;
  let selected = null;
  let endTimer = 0;
  let running = false;
  const pose = (tl, t) => reduceMotion ? stillPose(tl.reaction) : poseAt(tl.reaction, t - tl.start, tl.angle);
  const active = () => hovered ?? selected;
  function show(reaction) {
    if (reaction === timeline.reaction) return;
    const t = now();
    const current = pose(timeline, t).moonAngle % TAU;
    previous = { timeline, fadeStart: t };
    timeline = { reaction, start: t, angle: current };
    scheduleEnd();
  }
  function scheduleEnd() {
    clearTimeout(endTimer);
    const duration = DURATION[timeline.reaction];
    if (!duration) return;
    const reaction = timeline.reaction;
    endTimer = setTimeout(() => {
      if (timeline.reaction === reaction) show(restingFor(active()));
    }, duration * 1e3);
  }
  function greet() {
    previous = null;
    timeline = { reaction: "greet", start: now(), angle: REST_ANGLE };
    scheduleEnd();
  }
  function paintLayer(layer, tl, t) {
    const lctx = layer.getContext("2d");
    lctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawPose(lctx, size, pose(tl, t), colors);
  }
  function frame() {
    if (!running) return;
    const t = now();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    let fade = 1;
    if (previous) {
      const p = clamp01((t - previous.fadeStart) / CROSSFADE);
      fade = easeInOutSine(p);
      if (p >= 1) previous = null;
    }
    if (previous) {
      paintLayer(layers[1], previous.timeline, t);
      ctx.globalAlpha = 1 - fade;
      ctx.drawImage(layers[1], 0, 0);
    }
    paintLayer(layers[0], timeline, t);
    ctx.globalAlpha = fade;
    ctx.drawImage(layers[0], 0, 0);
    ctx.globalAlpha = 1;
    if (!reduceMotion || previous) requestAnimationFrame(frame);
    else running = false;
  }
  function start() {
    if (running) return;
    running = true;
    requestAnimationFrame(frame);
  }
  function select(action) {
    selected = action;
    for (const b of buttons) b.setAttribute("aria-pressed", String(b.dataset.action === action));
    show(reactingTo(active()));
    start();
  }
  for (const button of buttons) {
    const action = button.dataset.action;
    button.addEventListener("pointerenter", (e) => {
      if (e.pointerType !== "mouse") return;
      hovered = action;
      show(reactingTo(active()));
      start();
    });
    button.addEventListener("pointerleave", (e) => {
      if (e.pointerType !== "mouse" || hovered !== action) return;
      hovered = null;
      show(reactingTo(active()));
      start();
    });
    button.addEventListener("click", () => select(action));
  }
  panel.addEventListener("keydown", (e) => {
    const step = { ArrowDown: 1, ArrowUp: -1 }[e.key];
    if (!step) return;
    e.preventDefault();
    const index = selected ? ORDER.indexOf(selected) : step > 0 ? -1 : ORDER.length;
    const next = ORDER[Math.min(ORDER.length - 1, Math.max(0, index + step))];
    select(next);
    buttons.find((b) => b.dataset.action === next).focus();
  });
  resize();
  addEventListener("resize", () => {
    resize();
    start();
  });
  const seen = new IntersectionObserver(
    ([entry]) => {
      if (entry.isIntersecting) {
        panel.classList.add("is-open");
        hovered = null;
        if (!reduceMotion) greet();
        else timeline = { reaction: restingFor(selected), start: 0, angle: REST_ANGLE };
        start();
      } else {
        panel.classList.remove("is-open");
        running = false;
        clearTimeout(endTimer);
      }
    },
    { threshold: 0.5 }
  );
  seen.observe(root);
}
document.querySelectorAll("[data-session]").forEach(setupMenu);
