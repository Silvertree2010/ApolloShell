export const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
export function fit(host, stage, width, height) {
  const origin = host.dataset.origin === "right" ? "right top" : host.dataset.origin === "center" ? "center top" : "left top";
  stage.style.width = `${width}px`;
  stage.style.height = `${height}px`;
  stage.style.transformOrigin = origin;
  const apply = () => {
    const scale = Math.min(1, host.clientWidth / width);
    stage.style.transform = scale < 1 ? `scale(${scale})` : "";
    host.style.height = `${Math.ceil(height * scale)}px`;
    host.style.setProperty("--fit", scale);
  };
  new ResizeObserver(apply).observe(host);
  apply();
}
export function whenVisible(host, onChange, threshold = 0.2) {
  const io = new IntersectionObserver(([entry]) => onChange(entry.isIntersecting), { threshold });
  io.observe(host);
  return io;
}
export function mount(host, stage) {
  host.querySelector(".panel-fallback")?.remove();
  host.append(stage);
  host.classList.add("is-live");
}
export const clamp01 = (x) => Math.min(Math.max(x, 0), 1);
export const easeOutCubic = (x) => 1 - (1 - x) ** 3;
export const easeInOutSine = (x) => (1 - Math.cos(Math.PI * x)) / 2;
export function cubicBezier(x, x1, y1, x2, y2) {
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
