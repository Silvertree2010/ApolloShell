const root = document.documentElement;
const canvas = document.querySelector(".statue canvas");
const ctx = canvas.getContext("2d");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const frames = [];
let ratio = 2 / 3;
let drawn = -1;
function ready(img) {
  return img && img.complete && img.naturalWidth > 0;
}
function resize() {
  let h = innerHeight;
  let w = h * ratio;
  if (w > innerWidth) {
    w = innerWidth;
    h = w / ratio;
  }
  const dpr = Math.min(devicePixelRatio || 1, 2);
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  drawn = -1;
}
function progress() {
  const range = root.scrollHeight - innerHeight;
  if (range <= 0) return 0;
  return Math.min(1, Math.max(0, scrollY / range));
}
function nearest(i, dir) {
  for (let j = i; j >= 0 && j < frames.length; j += dir) {
    if (ready(frames[j])) return j;
  }
  return -1;
}
function draw(position) {
  let a = nearest(Math.floor(position), -1);
  let b = nearest(Math.min(Math.floor(position) + 1, frames.length - 1), 1);
  if (a < 0 && b < 0) return;
  if (a < 0) a = b;
  if (b < 0) b = a;
  ctx.globalAlpha = 1;
  ctx.drawImage(frames[a], 0, 0, canvas.width, canvas.height);
  const mix = b === a ? 0 : Math.min(1, Math.max(0, (position - a) / (b - a)));
  if (mix > 1e-3) {
    ctx.globalAlpha = mix;
    ctx.drawImage(frames[b], 0, 0, canvas.width, canvas.height);
  }
  drawn = position;
}
function render() {
  const position = progress() * (frames.length - 1);
  if (Math.abs(position - drawn) > 5e-4) draw(position);
}
function loadOrder(count) {
  const order = [0, count - 1];
  const seen = new Set(order);
  for (let step = 2 ** Math.floor(Math.log2(count)); step >= 1; step /= 2) {
    for (let i = 0; i < count; i += step) {
      if (!seen.has(i)) {
        seen.add(i);
        order.push(i);
      }
    }
  }
  return order;
}
function loadFrames() {
  const count = reduceMotion ? 1 : Number(canvas.dataset.frames);
  const ext = canvas.dataset.ext || "webp";
  frames.length = count;
  for (const i of loadOrder(count)) {
    const img = new Image();
    img.decoding = "async";
    if (i === 0) img.fetchPriority = "high";
    img.onload = () => {
      if (i === 0) {
        ratio = img.naturalWidth / img.naturalHeight;
        resize();
      }
      drawn = -1;
      if (reduceMotion) draw(0);
    };
    img.src = `frames/${String(i).padStart(3, "0")}.${ext}`;
    frames[i] = img;
  }
}
loadFrames();
resize();
addEventListener("resize", resize);
if (!reduceMotion) {
  const lenis = new Lenis({ lerp: 0.08, wheelMultiplier: 0.9, anchors: true });
  const frame = (time) => {
    lenis.raf(time);
    render();
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}
for (const room of document.querySelectorAll(".room, .close")) {
  room.querySelectorAll(".lit").forEach((el, i) => el.style.setProperty("--i", i));
}
const lights = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add("is-lit");
      lights.unobserve(entry.target);
    }
  },
  { rootMargin: "0px 0px -12% 0px", threshold: 0.15 }
);
document.querySelectorAll(".lit").forEach((el) => lights.observe(el));
for (const box of document.querySelectorAll("[data-copy]")) {
  const button = box.querySelector("button");
  let timer;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(box.dataset.copy);
      button.textContent = "Copied";
      button.dataset.state = "done";
    } catch {
      button.textContent = "Select it";
      button.dataset.state = "";
    }
    clearTimeout(timer);
    timer = setTimeout(() => {
      button.textContent = "Copy";
      button.dataset.state = "";
    }, 1600);
  });
}
