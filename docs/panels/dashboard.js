import { fit, whenVisible, mount, reduceMotion, cubicBezier } from "./shared.js";
const ICON = {
  "grid": '<path d="M4 5a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4"/> <path d="M14 5a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4"/> <path d="M4 15a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4"/> <path d="M14 15a1 1 0 0 1 1 -1h4a1 1 0 0 1 1 1v4a1 1 0 0 1 -1 1h-4a1 1 0 0 1 -1 -1l0 -4"/>',
  "gridFill": '<path d="M9 3a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z"/> <path d="M19 3a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z"/> <path d="M9 13a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z"/> <path d="M19 13a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z"/>',
  "playlist": '<path d="M11 17a3 3 0 1 0 6 0a3 3 0 1 0 -6 0"/> <path d="M17 17v-13h4"/> <path d="M13 5h-10"/> <path d="M3 9l10 0"/> <path d="M9 13h-6"/>',
  "gauge": '<path d="M3 12a9 9 0 1 0 18 0a9 9 0 1 0 -18 0"/> <path d="M11 12a1 1 0 1 0 2 0a1 1 0 1 0 -2 0"/> <path d="M13.41 10.59l2.59 -2.59"/> <path d="M7 12a5 5 0 0 1 5 -5"/>',
  "cloud": '<path d="M6.657 18c-2.572 0 -4.657 -2.007 -4.657 -4.483c0 -2.475 2.085 -4.482 4.657 -4.482c.393 -1.762 1.794 -3.2 3.675 -3.773c1.88 -.572 3.956 -.193 5.444 1c1.488 1.19 2.162 3.007 1.77 4.769h.99c1.913 0 3.464 1.56 3.464 3.486c0 1.927 -1.551 3.487 -3.465 3.487h-11.878"/>',
  "cloudFill": '<path d="M10.04 4.305c2.195 -.667 4.615 -.224 6.36 1.176c1.386 1.108 2.188 2.686 2.252 4.34l.003 .212l.091 .003c2.3 .107 4.143 1.961 4.25 4.27l.004 .211c0 2.407 -1.885 4.372 -4.255 4.482l-.21 .005h-11.878l-.222 -.008c-2.94 -.11 -5.317 -2.399 -5.43 -5.263l-.005 -.216c0 -2.747 2.08 -5.01 4.784 -5.417l.114 -.016l.07 -.181c.663 -1.62 2.056 -2.906 3.829 -3.518l.244 -.08z"/>',
  "sunFill": '<path d="M12 19a1 1 0 0 1 .993 .883l.007 .117v1a1 1 0 0 1 -1.993 .117l-.007 -.117v-1a1 1 0 0 1 1 -1z"/> <path d="M18.313 16.91l.094 .083l.7 .7a1 1 0 0 1 -1.32 1.497l-.094 -.083l-.7 -.7a1 1 0 0 1 1.218 -1.567l.102 .07z"/> <path d="M7.007 16.993a1 1 0 0 1 .083 1.32l-.083 .094l-.7 .7a1 1 0 0 1 -1.497 -1.32l.083 -.094l.7 -.7a1 1 0 0 1 1.414 0z"/> <path d="M4 11a1 1 0 0 1 .117 1.993l-.117 .007h-1a1 1 0 0 1 -.117 -1.993l.117 -.007h1z"/> <path d="M21 11a1 1 0 0 1 .117 1.993l-.117 .007h-1a1 1 0 0 1 -.117 -1.993l.117 -.007h1z"/> <path d="M6.213 4.81l.094 .083l.7 .7a1 1 0 0 1 -1.32 1.497l-.094 -.083l-.7 -.7a1 1 0 0 1 1.217 -1.567l.102 .07z"/> <path d="M19.107 4.893a1 1 0 0 1 .083 1.32l-.083 .094l-.7 .7a1 1 0 0 1 -1.497 -1.32l.083 -.094l.7 -.7a1 1 0 0 1 1.414 0z"/> <path d="M12 2a1 1 0 0 1 .993 .883l.007 .117v1a1 1 0 0 1 -1.993 .117l-.007 -.117v-1a1 1 0 0 1 1 -1z"/> <path d="M12 7a5 5 0 1 1 -4.995 5.217l-.005 -.217l.005 -.217a5 5 0 0 1 4.995 -4.783z"/>',
  "moonFill": '<path d="M12 1.992a10 10 0 1 0 9.236 13.838c.341 -.82 -.476 -1.644 -1.298 -1.31a6.5 6.5 0 0 1 -6.864 -10.787l.077 -.08c.551 -.63 .113 -1.653 -.758 -1.653h-.266l-.068 -.006l-.06 -.002z"/>',
  "moonStars": '<path d="M12 3c.132 0 .263 0 .393 0a7.5 7.5 0 0 0 7.92 12.446a9 9 0 1 1 -8.313 -12.454l0 .008"/> <path d="M17 4a2 2 0 0 0 2 2a2 2 0 0 0 -2 2a2 2 0 0 0 -2 -2a2 2 0 0 0 2 -2"/> <path d="M19 11h2m-1 -1v2"/>',
  "rain": '<path d="M7 18a4.6 4.4 0 0 1 0 -9a5 4.5 0 0 1 11 2h1a3.5 3.5 0 0 1 0 7"/> <path d="M11 13v2m0 3v2m4 -5v2m0 3v2"/>',
  "apple": '<path d="M15.079 5.999l.239 .012c1.43 .097 3.434 1.013 4.508 2.586a1 1 0 0 1 -.344 1.44c-.05 .028 -.372 .158 -.497 .217a4.15 4.15 0 0 0 -.722 .431c-.614 .461 -.948 1.009 -.942 1.694c.01 .885 .339 1.454 .907 1.846c.208 .143 .436 .253 .666 .33c.126 .043 .426 .116 .444 .122a1 1 0 0 1 .662 .942c0 2.621 -3.04 6.381 -5.286 6.381c-.79 0 -1.272 -.091 -1.983 -.315l-.098 -.031c-.463 -.146 -.702 -.192 -1.133 -.192c-.52 0 -.863 .06 -1.518 .237l-.197 .053c-.575 .153 -.964 .226 -1.5 .248c-2.749 0 -5.285 -5.093 -5.285 -9.072c0 -3.87 1.786 -6.92 5.286 -6.92c.297 0 .598 .045 .909 .128c.403 .107 .774 .26 1.296 .508c.787 .374 .948 .44 1.009 .44h.016c.03 -.003 .128 -.047 1.056 -.457c1.061 -.467 1.864 -.685 2.746 -.616l-.24 -.012z"/> <path d="M14 1a1 1 0 0 1 1 1a3 3 0 0 1 -3 3a1 1 0 0 1 -1 -1a3 3 0 0 1 3 -3z"/>',
  "history": '<path d="M12 8l0 4l2 2"/> <path d="M3.05 11a9 9 0 1 1 .5 4m-.5 5v-5h5"/>',
  "chevronLeft": '<path d="M15 6l-6 6l6 6"/>',
  "chevronRight": '<path d="M9 6l6 6l-6 6"/>',
  "cpu": '<path d="M5 6a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v12a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1l0 -12"/> <path d="M9 9h6v6h-6l0 -6"/> <path d="M3 10h2"/> <path d="M3 14h2"/> <path d="M10 3v2"/> <path d="M14 3v2"/> <path d="M21 10h-2"/> <path d="M21 14h-2"/> <path d="M14 21v-2"/> <path d="M10 21v-2"/>',
  "memory": '<path d="M5 6a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v12a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1l0 -12"/> <path d="M8 10v-2h2m6 6v2h-2m-4 0h-2v-2m8 -4v-2h-2"/> <path d="M3 10h2"/> <path d="M3 14h2"/> <path d="M10 3v2"/> <path d="M14 3v2"/> <path d="M21 10h-2"/> <path d="M21 14h-2"/> <path d="M14 21v-2"/> <path d="M10 21v-2"/>',
  "drive": '<path d="M3 7a3 3 0 0 1 3 -3h12a3 3 0 0 1 3 3v2a3 3 0 0 1 -3 3h-12a3 3 0 0 1 -3 -3v-2"/> <path d="M3 15a3 3 0 0 1 3 -3h12a3 3 0 0 1 3 3v2a3 3 0 0 1 -3 3h-12a3 3 0 0 1 -3 -3l0 -2"/> <path d="M7 8l0 .01"/> <path d="M7 16l0 .01"/>',
  "stack": '<path d="M12 4l-8 4l8 4l8 -4l-8 -4"/> <path d="M4 12l8 4l8 -4"/> <path d="M4 16l8 4l8 -4"/>',
  "battery": '<path d="M17 6a3 3 0 0 1 2.995 2.824l.005 .176v.086l.052 .019a1.5 1.5 0 0 1 .941 1.25l.007 .145v3a1.5 1.5 0 0 1 -.948 1.395l-.052 .018v.087a3 3 0 0 1 -2.824 2.995l-.176 .005h-11a3 3 0 0 1 -2.995 -2.824l-.005 -.176v-6a3 3 0 0 1 2.824 -2.995l.176 -.005h11zm-10 3a1 1 0 0 0 -1 1v4l.007 .117a1 1 0 0 0 1.993 -.117v-4l-.007 -.117a1 1 0 0 0 -.993 -.883zm3 0a1 1 0 0 0 -1 1v4l.007 .117a1 1 0 0 0 1.993 -.117v-4l-.007 -.117a1 1 0 0 0 -.993 -.883zm3 0a1 1 0 0 0 -1 1v4l.007 .117a1 1 0 0 0 1.993 -.117v-4l-.007 -.117a1 1 0 0 0 -.993 -.883z"/>',
  "play": '<path d="M6 4v16a1 1 0 0 0 1.524 .852l13 -8a1 1 0 0 0 0 -1.704l-13 -8a1 1 0 0 0 -1.524 .852z"/>',
  "pause": '<path d="M9 4h-2a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h2a2 2 0 0 0 2 -2v-12a2 2 0 0 0 -2 -2z"/> <path d="M17 4h-2a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h2a2 2 0 0 0 2 -2v-12a2 2 0 0 0 -2 -2z"/>',
  "next": '<path d="M2 5v14c0 .86 1.012 1.318 1.659 .753l8 -7a1 1 0 0 0 0 -1.506l-8 -7c-.647 -.565 -1.659 -.106 -1.659 .753z"/> <path d="M13 5v14c0 .86 1.012 1.318 1.659 .753l8 -7a1 1 0 0 0 0 -1.506l-8 -7c-.647 -.565 -1.659 -.106 -1.659 .753z"/>',
  "prev": '<path d="M20.341 4.247l-8 7a1 1 0 0 0 0 1.506l8 7c.647 .565 1.659 .106 1.659 -.753v-14c0 -.86 -1.012 -1.318 -1.659 -.753z"/> <path d="M9.341 4.247l-8 7a1 1 0 0 0 0 1.506l8 7c.647 .565 1.659 .106 1.659 -.753v-14c0 -.86 -1.012 -1.318 -1.659 -.753z"/>',
  "appDashed": '<path d="M3 5a2 2 0 0 1 2 -2h14a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-14a2 2 0 0 1 -2 -2l0 -14"/>',
  "speaker": '<path d="M17 2a3 3 0 0 1 3 3v14a3 3 0 0 1 -3 3h-10a3 3 0 0 1 -3 -3v-14a3 3 0 0 1 3 -3zm-5 9a4 4 0 0 0 -3.995 3.8l-.005 .2a4 4 0 1 0 4 -4m0 -5a1 1 0 0 0 -1 1v.01a1 1 0 0 0 2 0v-.01a1 1 0 0 0 -1 -1"/>',
  "arrowsUpDown": '<path d="M7 3l0 18"/> <path d="M10 6l-3 -3l-3 3"/> <path d="M20 18l-3 3l-3 -3"/> <path d="M17 21l0 -18"/>',
  "arrowDown": '<path d="M12 5l0 14"/> <path d="M18 13l-6 6"/> <path d="M6 13l6 6"/>',
  "arrowUp": '<path d="M12 5l0 14"/> <path d="M18 11l-6 -6"/> <path d="M6 11l6 -6"/>',
  "droplet": '<path d="M7.502 19.423c2.602 2.105 6.395 2.105 8.996 0c2.602 -2.105 3.262 -5.708 1.566 -8.546l-4.89 -7.26c-.42 -.625 -1.287 -.803 -1.936 -.397a1.376 1.376 0 0 0 -.41 .397l-4.893 7.26c-1.695 2.838 -1.035 6.441 1.567 8.546"/>',
  "wind": '<path d="M5 8h8.5a2.5 2.5 0 1 0 -2.34 -3.24"/> <path d="M3 12h15.5a2.5 2.5 0 1 1 -2.34 3.24"/> <path d="M4 16h5.5a2.5 2.5 0 1 1 -2.34 3.24"/>',
  "sunrise": '<path d="M4 16a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/> <path d="M12 12a5 5 0 0 1 5 5a1 1 0 0 1 -1 1h-8a1 1 0 0 1 -1 -1a5 5 0 0 1 5 -5"/> <path d="M21 16a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/> <path d="M6.307 9.893l.7 .7a1 1 0 0 1 -1.414 1.414l-.7 -.7a1 1 0 0 1 1.414 -1.414"/> <path d="M19.107 9.893a1 1 0 0 1 0 1.414l-.7 .7a1 1 0 0 1 -1.414 -1.414l.7 -.7a1 1 0 0 1 1.414 0"/> <path d="M12.707 2.293l3 3a1 1 0 1 1 -1.414 1.414l-1.293 -1.292v3.585a1 1 0 0 1 -.883 .993l-.117 .007a1 1 0 0 1 -1 -1v-3.586l-1.293 1.293a1 1 0 0 1 -1.414 -1.414l2.958 -2.96a1 1 0 0 1 .15 -.135l.127 -.08l.068 -.033l.11 -.041l.12 -.029c.3 -.055 .627 .024 .881 .278"/> <path d="M3 20h18a1 1 0 0 1 0 2h-18a1 1 0 0 1 0 -2"/> <path d="M12 12a5 5 0 0 1 4.583 7.002h-9.166a5 5 0 0 1 4.583 -7.002"/>',
  "sunset": '<path d="M4 12a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/> <path d="M21 12a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/> <path d="M6.307 5.893l.7 .7a1 1 0 0 1 -1.414 1.414l-.7 -.7a1 1 0 0 1 1.414 -1.414"/> <path d="M19.107 5.893a1 1 0 0 1 0 1.414l-.7 .7a1 1 0 0 1 -1.414 -1.414l.7 -.7a1 1 0 0 1 1.414 0"/> <path d="M12 3a1 1 0 0 1 1 1v1a1 1 0 0 1 -2 0v-1a1 1 0 0 1 1 -1"/> <path d="M3 16h18a1 1 0 0 1 0 2h-18a1 1 0 0 1 0 -2"/> <path d="M12 8a5 5 0 0 1 4.583 7.002h-9.166a5 5 0 0 1 4.583 -7.002"/> <path d="M12 19a1 1 0 0 1 0 2h-5a1 1 0 0 1 0 -2z"/> <path d="M17 19a1 1 0 0 1 0 2h-1a1 1 0 0 1 0 -2z"/>',
  "sunHigh": '<path d="M14.828 14.828a4 4 0 1 0 -5.656 -5.656a4 4 0 0 0 5.656 5.656"/> <path d="M6.343 17.657l-1.414 1.414"/> <path d="M6.343 6.343l-1.414 -1.414"/> <path d="M17.657 6.343l1.414 -1.414"/> <path d="M17.657 17.657l1.414 1.414"/> <path d="M4 12h-2"/> <path d="M12 4v-2"/> <path d="M20 12h2"/> <path d="M12 20v2"/>'
};
const FILLED = new Set(["gridFill", "cloudFill", "sunFill", "moonFill", "apple", "battery", "play", "pause", "next", "prev", "speaker", "sunrise", "sunset"]);
const SVGNS = "http://www.w3.org/2000/svg";
const PAD = 16;
const GRID_W = 839;
const GRID_H = 392;
const TABS_H = 59;
const WIDTH = GRID_W + 2 * PAD;
const HEIGHT = TABS_H + 1 + GRID_H + 2 * PAD;
const SPATIAL = "cubic-bezier(0.38, 1.21, 0.22, 1)";
const spatial = (x) => cubicBezier(x, 0.38, 1.21, 0.22, 1);
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
function svg(inner, size, cls = "", view = "0 0 24 24") {
  const s = document.createElementNS(SVGNS, "svg");
  s.setAttribute("viewBox", view);
  s.setAttribute("width", size);
  s.setAttribute("height", size);
  s.setAttribute("aria-hidden", "true");
  s.setAttribute("class", `ic ${cls}`);
  s.innerHTML = inner;
  return s;
}
const icon = (name, size, cls = "") => svg(ICON[name], size, `${FILLED.has(name) ? "ic-fill" : "ic-line"} ${cls}`);
let maskId = 0;
function weatherKind(code, isDay) {
  if (code <= 1) return isDay ? "sun" : "moon";
  if (code === 2) return isDay ? "cloudSun" : "cloudMoon";
  if (code === 61 || code === 63 || code === 65) return "rain";
  if (code === 80 || code === 81) return isDay ? "sunRain" : "rain";
  return "cloud";
}
function weatherGlyph(kind, size, mono = false) {
  const sun = mono ? "currentColor" : "var(--w-sun)";
  const cloud = mono ? "currentColor" : "var(--w-cloud)";
  const rain = mono ? "currentColor" : "var(--w-rain)";
  const star = (x, y, r) => `<path d="M${x} ${y - r}Q${x + r * 0.16} ${y - r * 0.16} ${x + r} ${y}Q${x + r * 0.16} ${y + r * 0.16} ${x} ${y + r}Q${x - r * 0.16} ${y + r * 0.16} ${x - r} ${y}Q${x - r * 0.16} ${y - r * 0.16} ${x} ${y - r}Z"/>`;
  const withBehind = (behind, cloudT) => {
    const id = `dw${++maskId}`;
    return `<defs><mask id="${id}"><rect width="24" height="24" fill="#fff"/><g transform="${cloudT}" fill="#000" stroke="#000" stroke-width="3">${ICON.cloudFill}</g></mask></defs><g mask="url(#${id})">${behind}</g><g transform="${cloudT}" fill="${cloud}">${ICON.cloudFill}</g>`;
  };
  const sunSmall = `<g fill="${sun}" transform="translate(9 -1) scale(.62)">${ICON.sunFill}</g>`;
  const moonSmall = `<g fill="${cloud}" transform="translate(10 0) scale(.55)">${ICON.moonFill}</g>`;
  const drops = `<path fill="none" stroke="${rain}" stroke-width="1.7" stroke-linecap="round" d="M7.6 17.6l-1 2.4M11.1 17.6l-1 2.4M14.6 17.6l-1 2.4M18.1 17.6l-1 2.4"/>`;
  let inner;
  switch (kind) {
    case "sun":
      inner = `<g fill="${sun}">${ICON.sunFill}</g>`;
      break;
    case "moon":
      inner = `<g fill="${cloud}"><g transform="translate(1 3) scale(.84)">${ICON.moonFill}</g>${star(17.5, 5, 2.6)}${star(21, 10, 1.7)}</g>`;
      break;
    case "cloudSun":
      inner = withBehind(sunSmall, "translate(-1 5) scale(.8)");
      break;
    case "cloudMoon":
      inner = withBehind(moonSmall, "translate(-1 5) scale(.8)");
      break;
    case "rain":
      inner = `<g fill="${cloud}" transform="translate(1.5 -2.2) scale(.86)">${ICON.cloudFill}</g>${drops}`;
      break;
    case "sunRain":
      inner = withBehind(sunSmall, "translate(-1 3) scale(.78)") + drops;
      break;
    default:
      inner = `<g fill="${cloud}">${ICON.cloudFill}</g>`;
  }
  return svg(inner, size, "ic-weather");
}
function weatherTabGlyph(filled, size) {
  const id = `dw${++maskId}`;
  const cloudT = "translate(-0.5 5) scale(.8)";
  const cloudShape = filled ? `<g fill="currentColor">${ICON.cloudFill}</g>` : `<g fill="none" stroke="currentColor" stroke-width="2.2">${ICON.cloud}</g>`;
  const sun = filled ? `<g fill="currentColor" transform="translate(9 -1) scale(.62)">${ICON.sunFill}</g>` : `<g fill="none" stroke="currentColor" stroke-width="2.9" stroke-linecap="round" transform="translate(9.5 0) scale(.6)">${ICON.sunHigh}</g>`;
  return svg(
    `<defs><mask id="${id}"><rect width="24" height="24" fill="#fff"/><g transform="${cloudT}" fill="#000" stroke="#000" stroke-width="3">${ICON.cloudFill}</g></mask></defs><g mask="url(#${id})">${sun}</g><g transform="${cloudT}">${cloudShape}</g>`,
    size,
    "ic-weather"
  );
}
function rollText(node, text, up = true) {
  const old = node.dataset.v ?? "";
  if (old === text) return;
  node.dataset.v = text;
  const chars = (s) => [...s].map((c) => el("span", { class: "roll-ch" }, el("span", { class: "roll-in", text: c })));
  if (reduceMotion || old.length !== text.length || !node.childElementCount) {
    node.replaceChildren(...chars(text));
    return;
  }
  [...text].forEach((c, i) => {
    const slot = node.children[i];
    const inner = slot.firstChild;
    if (inner.textContent === c) return;
    slot.querySelectorAll(".roll-ghost").forEach((g) => g.remove());
    const ghost = el("span", { class: "roll-ghost", text: inner.textContent, "aria-hidden": "true" });
    inner.textContent = c;
    slot.append(ghost);
    const dir = up ? -1 : 1;
    const opts = { duration: 500, easing: SPATIAL };
    inner.animate([{ transform: `translateY(${-dir * 55}%)`, opacity: 0 }, { transform: "none", opacity: 1 }], opts);
    ghost.animate([{ transform: "none", opacity: 1 }, { transform: `translateY(${dir * 55}%)`, opacity: 0 }], { ...opts, fill: "forwards" }).onfinish = () => ghost.remove();
  });
}
const UNITS = ["B", "KB", "MB", "GB", "TB", "PB"];
function bytes(value, binary = false) {
  const base = binary ? 1024 : 1e3;
  let amount = Math.max(value, 0);
  let unit = 0;
  const shown = (a, u) => u === 0 || a >= 9.95 ? Math.round(a) : Math.round(a * 10) / 10;
  while (unit < UNITS.length - 1 && shown(amount, unit) >= 1e3) {
    amount /= base;
    unit++;
  }
  if (unit === 0) return `${Math.round(amount)} B`;
  const tenths = Math.round(amount * 10);
  return tenths < 100 ? `${Math.floor(tenths / 10)}.${tenths % 10} ${UNITS[unit]}` : `${Math.round(amount)} ${UNITS[unit]}`;
}
const rate = (v) => `${bytes(v)}/s`;
const percent = (f) => `${Math.round(Math.min(Math.max(f, 0), 1) * 100)} %`;
function uptime(seconds) {
  const m = Math.floor(seconds / 60);
  const d = Math.floor(m / 1440), hr = Math.floor(m / 60) % 24, mi = m % 60;
  if (d > 0) return `${d}d ${hr}h`;
  if (hr > 0) return `${hr}h ${mi}m`;
  return `${mi}m`;
}
const two = (n) => String(n).padStart(2, "0");
const temp = (c) => `${Math.round(c)}°`;
const clockTime = (s) => {
  const t = Math.max(0, Math.floor(s));
  return `${Math.floor(t / 60)}:${two(t % 60)}`;
};
function trimDash(r, from, to) {
  const c = 2 * Math.PI * r;
  const len = Math.max(0, to - from) * c;
  return { dasharray: `0 ${from * c} ${len} ${c}`, empty: len <= 0.01 };
}
function circleEl(size, r, cls, rotate) {
  const s = document.createElementNS(SVGNS, "svg");
  s.setAttribute("viewBox", `0 0 ${size} ${size}`);
  s.setAttribute("width", size);
  s.setAttribute("height", size);
  s.setAttribute("aria-hidden", "true");
  s.setAttribute("class", `ring ${cls}`);
  const make = (c) => {
    const n = document.createElementNS(SVGNS, "circle");
    n.setAttribute("cx", size / 2);
    n.setAttribute("cy", size / 2);
    n.setAttribute("r", r);
    n.setAttribute("class", c);
    n.setAttribute("transform", `rotate(${rotate} ${size / 2} ${size / 2})`);
    s.append(n);
    return n;
  };
  return { svg: s, track: make("ring-track"), value: make("ring-value") };
}
function setTrim(node, r, from, to) {
  const { dasharray, empty } = trimDash(r, from, to);
  node.style.strokeDasharray = dasharray;
  node.style.opacity = empty ? 0 : 1;
}
const TRACKS = [
  { title: "Northern Lights", artist: "Sample Artist", album: "Example Album", duration: 242, cover: "northern-lights" },
  { title: "Slow Tide", artist: "Sample Artist", album: "Example Album", duration: 208, cover: "slow-tide" },
  { title: "Paper Moon", artist: "Sample Artist", album: "Example Album", duration: 231, cover: "paper-moon" }
];
const coverURL = (name) => new URL(`media/${name}.svg`, import.meta.url).href;
const WEATHER = {
  city: "Berlin",
  temp: 19.4,
  feels: 18.6,
  humidity: 58,
  wind: 11,
  code: 2,
  hourCodes: [1, 1, 2, 2, 2, 3, 3, 3, 61, 61, 3, 2, 1, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 2],
  dayCodes: [2, 61, 3, 1, 0, 80, 2],
  highs: [20, 17, 18, 21, 23, 19, 20],
  lows: [11, 10, 9, 10, 12, 13, 11]
};
const card = (cls, radius, style, ...kids) => el("div", { class: `card ${cls}`, style: `border-radius:${radius}px;${style}` }, ...kids);
function smallWeatherCard() {
  const today = { max: WEATHER.highs[0], min: WEATHER.lows[0] };
  return card(
    "wx-small",
    42,
    "left:0;top:0;width:275px;height:130px",
    el(
      "div",
      { class: "row", style: "gap:16px;padding:0 26px", title: `Weather in ${WEATHER.city}` },
      weatherGlyph("cloudSun", 54),
      el(
        "div",
        { class: "col", style: "gap:1px" },
        el("span", { class: "rounded", style: "font-size:34px;font-weight:600;line-height:40px", text: temp(WEATHER.temp) }),
        el("span", { style: "font-size:13px;font-weight:500", text: "Partly Cloudy" }),
        el("span", { class: "sec", style: "font-size:11px", text: `H:${temp(today.max)} L:${temp(today.min)}` })
      )
    )
  );
}
function badge(name, text) {
  const t = el("span", { text });
  return [el("span", { class: "badge" }, icon(name, 11), t), t];
}
function userCard(state) {
  const [system] = badge("apple", "macOS 26.6.2");
  const [up, upText] = badge("history", "");
  state.uptimeText = upText;
  return card(
    "user",
    28,
    "left:287px;top:0;width:340px;height:130px",
    el(
      "div",
      { class: "row", style: "gap:14px;padding:0 18px;width:100%" },
      el("div", { class: "avatar rounded", "aria-hidden": "true", text: "A" }),
      el(
        "div",
        { class: "col", style: "gap:6px;align-items:flex-start;min-width:0" },
        el("span", { style: "font-size:17px;font-weight:600", text: "Alex" }),
        system,
        up
      )
    )
  );
}
function clockCard(state) {
  state.hour = el("span");
  state.minute = el("span");
  return card(
    "clock",
    16,
    "left:0;top:142px;width:110px;height:250px",
    el(
      "div",
      { class: "col rounded", style: "gap:6px;font-size:30px;font-weight:600;line-height:36px", role: "timer", "aria-live": "off" },
      state.hour,
      el("span", { class: "sec", style: "font-size:14px;font-weight:700;line-height:17px;letter-spacing:1px", "aria-hidden": "true", text: "•••" }),
      state.minute
    )
  );
}
function calendarCard(state) {
  const title = el("span", { style: "font-size:14px;font-weight:600", "aria-live": "polite" });
  const grid = el("div", { class: "cal-grid", role: "grid" });
  const shown = new Date();
  shown.setDate(1);
  const render = () => {
    const now = new Date();
    title.textContent = shown.toLocaleDateString("en-US", { month: "long", year: "numeric" });
    const rows = [el(
      "div",
      { class: "cal-row", role: "row" },
      ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"].map((d) => el("span", { class: "cal-wd sec", role: "columnheader", text: d }))
    )];
    const offset = (shown.getDay() + 6) % 7;
    const days = new Date(shown.getFullYear(), shown.getMonth() + 1, 0).getDate();
    const weeks = Math.ceil((offset + days) / 7);
    for (let w = 0; w < weeks; w++) {
      const cells = [];
      for (let i = 0; i < 7; i++) {
        const d = new Date(shown.getFullYear(), shown.getMonth(), 1 - offset + w * 7 + i);
        const inMonth = d.getMonth() === shown.getMonth();
        const isToday = d.toDateString() === now.toDateString();
        cells.push(el(
          "span",
          { class: "cal-cell", role: "gridcell", "aria-current": isToday ? "date" : null },
          el("span", { class: `cal-day${isToday ? " today" : ""}${inMonth ? "" : " out"}`, text: String(d.getDate()) })
        ));
      }
      rows.push(el("div", { class: "cal-row", role: "row" }, cells));
    }
    grid.replaceChildren(...rows);
    state.calendarDay = now.toDateString();
  };
  const step = (n) => () => {
    shown.setMonth(shown.getMonth() + n);
    render();
  };
  state.renderCalendar = render;
  state.resetCalendar = () => {
    const n = new Date();
    shown.setFullYear(n.getFullYear(), n.getMonth(), 1);
    render();
  };
  render();
  return card(
    "calendar",
    28,
    "left:122px;top:142px;width:403px;height:250px;align-items:stretch;justify-content:flex-start",
    el(
      "div",
      { class: "col", style: "gap:8px;padding:14px;align-items:stretch" },
      el(
        "div",
        { class: "row sec", style: "justify-content:space-between" },
        el("button", { type: "button", class: "plain chev", "aria-label": "Previous month", onclick: step(-1) }, icon("chevronLeft", 15)),
        title,
        el("button", { type: "button", class: "plain chev", "aria-label": "Next month", onclick: step(1) }, icon("chevronRight", 15))
      ),
      grid
    )
  );
}
function resourceRing(name, label) {
  const r = circleEl(56, 28, "res-ring", -90);
  const wrap = el("div", { class: "res", role: "img" }, r.svg, icon(name, 17));
  setTrim(r.track, 28, 0, 1);
  return {
    wrap,
    set(v) {
      setTrim(r.value, 28, 0, v);
      const p = Math.round(v * 100);
      wrap.setAttribute("aria-label", `${label} ${p} percent`);
      wrap.title = `${label} ${p} %`;
    }
  };
}
function resourcesCard(state) {
  state.rings = { cpu: resourceRing("cpu", "CPU"), memory: resourceRing("memory", "Memory"), storage: resourceRing("drive", "Storage") };
  return card(
    "resources",
    16,
    "left:537px;top:142px;width:90px;height:250px",
    el("div", { class: "col", style: "gap:14px" }, state.rings.cpu.wrap, state.rings.memory.wrap, state.rings.storage.wrap)
  );
}
function artwork(radius, cls = "") {
  const box = el("div", { class: `art ${cls}`, style: `border-radius:${radius}`, "aria-hidden": "true" });
  return box;
}
function setArtwork(box, url, animate) {
  const img = el("img", { src: url, alt: "", draggable: "false" });
  const old = [...box.children];
  box.append(img);
  if (animate && !reduceMotion) {
    img.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 300, easing: "cubic-bezier(0.34, 0.88, 0.34, 1)" }).onfinish = () => old.forEach((o) => o.remove());
  } else old.forEach((o) => o.remove());
}
function waveform(size) {
  const bars = [0.42, 0.78, 1, 0.66, 0.4];
  const w = el(
    "span",
    { class: "wave", style: `height:${size}px;width:${size * 1.1}px`, "aria-hidden": "true" },
    bars.map((h, i) => el("i", { style: `height:${h * 100}%;animation-delay:${i * 0.12}s` }))
  );
  return w;
}
function playState(size, withText) {
  const pause = icon("pause", size * 0.95, "ps-pause");
  const node = el("span", { class: "play-state" }, el("span", { class: "ps-glyph" }, waveform(size), pause), withText ? el("span", { class: "ps-text" }) : null);
  return node;
}
function controls(state, height, symbol, spacing) {
  const prev = el("button", { type: "button", class: "m-round", style: `width:${height}px;height:${height}px`, "aria-label": "Previous Track", title: "Previous Track", onclick: () => state.skip(-1) }, icon("prev", symbol * 1.05));
  const next = el("button", { type: "button", class: "m-round", style: `width:${height}px;height:${height}px`, "aria-label": "Next Track", title: "Next Track", onclick: () => state.skip(1) }, icon("next", symbol * 1.05));
  const play = el(
    "button",
    { type: "button", class: "m-play", style: `height:${height}px;--h:${height}px`, onclick: () => state.toggle() },
    el("span", { class: "swap" }, icon("pause", symbol + 5, "sw-pause"), icon("play", symbol + 3, "sw-play"))
  );
  state.playButtons.push(play);
  return el("div", { class: "m-controls", style: `gap:${spacing}px` }, prev, play, next);
}
function mediaArc(state, size, line) {
  const r = size / 2 - line / 2;
  const c = circleEl(size, r, "m-arc", 180);
  c.svg.style.setProperty("--line", `${line}px`);
  state.arcs.push({ ...c, r });
  return c.svg;
}
function mediaDashCard(state) {
  const cover = artwork("50%", "m-cover");
  state.covers.push(cover);
  const title = el("span", { class: "accent", style: "font-size:14px;font-weight:600" });
  const album = el("span", { class: "ter", style: "font-size:12px" });
  const artist = el("span", { class: "sec", style: "font-size:12px" });
  state.texts.push({ title, album, artist });
  const chipState = playState(11, false);
  state.playStates.push(chipState);
  return card(
    "media",
    56,
    "left:639px;top:0;width:200px;height:392px;justify-content:flex-start",
    el("div", { class: "m-arcbox", style: "margin-top:22px" }, mediaArc(state, 164, 6), el("div", { style: "position:absolute;inset:10px" }, cover)),
    el("div", { class: "col m-texts", style: "gap:4px;width:168px;margin-top:14px" }, title, album, artist),
    el("div", { style: "margin:14px 16px 0;align-self:stretch" }, controls(state, 40, 15, 4)),
    el("div", { style: "flex:1" }),
    el(
      "span",
      { class: "chip", style: "margin-bottom:22px", title: "Playing in Music" },
      el("span", { class: "app-icon", style: "width:18px;height:18px" }, icon("appDashed", 13)),
      el("span", { style: "font-size:11px;font-weight:500", text: "Music" }),
      chipState
    )
  );
}
function mediaTab(state) {
  const ambient = artwork("28px", "m-ambient");
  const cover = artwork("28px", "m-bigcover");
  state.covers.push(ambient, cover);
  const title = el("span", { style: "font-size:22px;font-weight:600;line-height:27px" });
  const artist = el("span", { class: "sec", style: "font-size:16px;font-weight:500" });
  const album = el("span", { class: "accent", style: "font-size:16px;font-weight:500" });
  state.texts.push({ title, artist, album });
  const elapsed = el("span", { class: "m-time" });
  const remain = el("span", { class: "m-time" });
  const bar = el("div", { class: "m-bar" }, el("i"));
  state.timelines.push({ elapsed, remain, bar });
  const panelState = playState(12, true);
  state.playStates.push(panelState);
  return el(
    "div",
    { class: "m-tab" },
    ambient,
    el(
      "div",
      { class: "row", style: "position:relative;gap:24px;height:100%;padding:20px 20px 20px 18px" },
      el("div", { style: "width:252px;display:flex;justify-content:center" }, el("div", { style: "width:244px;height:244px" }, cover)),
      el(
        "div",
        { class: "col m-details", style: "flex:1;align-items:stretch;gap:4px;min-width:0" },
        title,
        artist,
        album,
        el("div", { class: "row sec", style: "gap:10px;margin-top:26px", role: "group", "aria-label": "Playback position" }, elapsed, bar, remain),
        el("div", { style: "margin-top:18px" }, controls(state, 52, 20, 6))
      ),
      el(
        "div",
        { class: "col", style: "width:200px;height:244px;gap:10px;align-items:stretch" },
        el("div", { class: "row", style: "gap:8px;padding-left:6px;justify-content:flex-start" }, icon("speaker", 16), el("span", { style: "font-size:16px;font-weight:500", text: "Source" })),
        el(
          "div",
          { class: "card col", style: "position:relative;flex:1;border-radius:24px;gap:8px" },
          el("span", { class: "app-icon", style: "width:64px;height:64px" }, icon("appDashed", 46)),
          el("span", { style: "font-size:15px;font-weight:600", text: "Music" }),
          el("span", { class: "sec", style: "font-size:12px;font-weight:500" }, panelState)
        )
      )
    )
  );
}
function setupMedia(state, root) {
  let index = 0;
  let playing = true;
  let base = 97;
  let since = performance.now();
  const elapsedNow = () => Math.min(base + (playing ? (performance.now() - since) / 1e3 : 0), TRACKS[index].duration);
  const showTrack = (animate) => {
    const t = TRACKS[index];
    for (const c of state.covers) setArtwork(c, coverURL(t.cover), animate);
    for (const set of state.texts) {
      for (const [k, node] of Object.entries(set)) {
        node.textContent = t[k];
        if (animate && !reduceMotion) node.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: "cubic-bezier(0.34, 0.8, 0.34, 1)" });
      }
    }
  };
  const showPlaying = () => {
    root.classList.toggle("is-playing", playing);
    for (const b of state.playButtons) {
      b.setAttribute("aria-label", playing ? "Pause" : "Play");
      b.title = playing ? "Pause" : "Play";
    }
    for (const s of state.playStates) {
      const text = s.querySelector(".ps-text");
      if (text) text.textContent = playing ? "Playing" : "Paused";
    }
  };
  state.tickMedia = () => {
    const t = TRACKS[index];
    const e = elapsedNow();
    if (playing && e >= t.duration) {
      state.skip(1);
      return;
    }
    const p = e / t.duration;
    for (const a of state.arcs) {
      const played = 0.5 * p;
      setTrim(a.value, a.r, 0, played);
      setTrim(a.track, a.r, Math.min(played + 0.03, 0.5), 0.5);
    }
    const template = clockTime(t.duration).replace(/\d/g, "0");
    for (const tl of state.timelines) {
      tl.elapsed.textContent = clockTime(e);
      tl.remain.textContent = `-${clockTime(Math.ceil(t.duration - e))}`;
      tl.elapsed.style.minWidth = tl.remain.style.minWidth = `${(template.length + 1) * 7.2}px`;
      tl.bar.firstChild.style.width = `max(6px, ${p * 100}%)`;
      tl.bar.setAttribute("aria-label", `${clockTime(e)} elapsed`);
    }
  };
  state.toggle = () => {
    base = elapsedNow();
    since = performance.now();
    playing = !playing;
    showPlaying();
    state.tickMedia();
  };
  state.skip = (step) => {
    index = (index + step + TRACKS.length) % TRACKS.length;
    base = 0;
    since = performance.now();
    showTrack(true);
    state.tickMedia();
  };
  state.isPlaying = () => playing;
  showTrack(false);
  showPlaying();
  state.tickMedia();
}
function scallopPath(size, usage) {
  const lobes = usage >= 0.8 ? 12 : usage >= 0.4 ? 8 : 4;
  const depth = usage >= 0.8 ? 0.11 : usage >= 0.4 ? 0.07 : 0.12;
  const c = size / 2;
  let d = "";
  for (let s = 0; s <= 180; s++) {
    const a = s / 180 * 2 * Math.PI;
    const r = c * (1 - depth * (1 - Math.cos(lobes * a)) / 2);
    d += `${s ? "L" : "M"}${(c + r * Math.cos(a - Math.PI / 2)).toFixed(2)} ${(c + r * Math.sin(a - Math.PI / 2)).toFixed(2)}`;
  }
  return `${d}Z`;
}
function sparkPath(values, capacity, scale, w, h, closed) {
  const shown = values.slice(-capacity);
  if (shown.length < 2) return "";
  const step = 1 / (capacity - 1);
  const offset = capacity - shown.length;
  const pts = shown.map((v, i) => [(offset + i) * step * w, 1 + (h - 1) - Math.min(Math.max(v / scale, 0), 1) * (h - 1)]);
  let d = `M${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
  for (let i = 1; i < pts.length; i++) {
    const [px, py] = pts[i - 1];
    d += `Q${px.toFixed(2)} ${py.toFixed(2)} ${((px + pts[i][0]) / 2).toFixed(2)} ${((py + pts[i][1]) / 2).toFixed(2)}`;
  }
  const last = pts[pts.length - 1];
  d += `L${last[0].toFixed(2)} ${last[1].toFixed(2)}`;
  if (closed) d += `L${last[0].toFixed(2)} ${h}L${pts[0][0].toFixed(2)} ${h}Z`;
  return d;
}
function sparkline(w, h, color, fillOpacity) {
  const s = document.createElementNS(SVGNS, "svg");
  s.setAttribute("viewBox", `0 0 ${w} ${h}`);
  s.setAttribute("width", w);
  s.setAttribute("height", h);
  s.setAttribute("aria-hidden", "true");
  s.setAttribute("class", "spark");
  const fill = document.createElementNS(SVGNS, "path");
  fill.setAttribute("fill", color);
  fill.setAttribute("fill-opacity", fillOpacity);
  const line = document.createElementNS(SVGNS, "path");
  line.setAttribute("fill", "none");
  line.setAttribute("stroke", color);
  line.setAttribute("stroke-width", "1.5");
  line.setAttribute("stroke-linecap", "round");
  line.setAttribute("stroke-linejoin", "round");
  s.append(fill, line);
  return { svg: s, draw(values, scale) {
    fill.setAttribute("d", sparkPath(values, 30, scale, w, h, true));
    line.setAttribute("d", sparkPath(values, 30, scale, w, h, false));
  } };
}
function heroCard(ui, key, name, title, x) {
  const ring = circleEl(46, 21, "usage-ring", -90);
  setTrim(ring.track, 21, 0, 1);
  const shape = document.createElementNS(SVGNS, "path");
  const badgeSvg = svg("", 92, "scallop", "0 0 92 92");
  badgeSvg.append(shape);
  const value = el("span", { class: "rounded roll", style: "font-size:24px;font-weight:600" });
  const spark = sparkline(209, 40, "var(--accent)", 0.18);
  const node = card(
    "hero",
    24,
    `left:${x}px;top:0;width:343px;height:191px;align-items:stretch`,
    el(
      "div",
      { class: "col", style: "padding:14px;align-items:stretch;height:100%;gap:0" },
      el(
        "div",
        { class: "row", style: "gap:12px;justify-content:flex-start" },
        el("div", { class: "ring-wrap", style: "width:46px;height:46px" }, ring.svg, icon(name, 20)),
        el(
          "div",
          { class: "col", style: "gap:2px;align-items:flex-start" },
          el("span", { class: "accent", style: "font-size:19px;font-weight:600", text: title }),
          el("span", { class: "sec", style: "font-size:12px", text: "Apple silicon · 10 Cores" })
        )
      ),
      el("div", { style: "flex:1;min-height:8px" }),
      el(
        "div",
        { class: "row", style: "gap:14px;align-items:flex-end" },
        el(
          "div",
          { class: "col", style: "flex:1;gap:4px;align-items:flex-start" },
          el("span", { class: "ter", style: "font-size:10px;font-weight:500", text: "Last 30s" }),
          el("div", { class: "baseline" }, spark.svg)
        ),
        el("div", { class: "badge-shape" }, badgeSvg, value)
      )
    )
  );
  node.setAttribute("role", "img");
  ui[key] = {
    set(v, history) {
      setTrim(ring.value, 21, 0, v);
      shape.setAttribute("d", scallopPath(92, v));
      rollText(value, percent(v), v >= (ui[key].last ?? 0));
      ui[key].last = v;
      spark.draw(history, 1);
      node.setAttribute("aria-label", `${title} ${percent(v)}`);
    }
  };
  return node;
}
function arcGauge(size, labelKids) {
  const r = size / 2 - 4;
  const g = circleEl(size, r, "arc-gauge", 135);
  setTrim(g.track, r, 0, 0.75);
  const wrap = el(
    "div",
    { class: "gauge", style: `width:${size}px;height:${size}px` },
    g.svg,
    el("div", { class: "col gauge-label" }, labelKids),
    el("span", { class: "sec gauge-cap", text: "Used" })
  );
  return { wrap, set: (v) => setTrim(g.value, r, 0, 0.75 * v) };
}
function performanceTab(ui) {
  const storageValue = el("span", { class: "rounded roll", style: "font-size:28px;font-weight:600;line-height:33px" });
  const storage = arcGauge(122, [el("span", { class: "accent", style: "display:flex;margin-top:-2px" }, icon("drive", 17, "ic-bold")), storageValue]);
  const storageText = el("span", { class: "sec", style: "font-size:11px" });
  const memValue = el("span", { class: "rounded roll", style: "font-size:28px;font-weight:600;line-height:33px" });
  const memory = arcGauge(110, [memValue]);
  const memText = el("span", { class: "sec", style: "font-size:11px" });
  const down = el("span", { class: "rate" });
  const upEl = el("span", { class: "rate" });
  const total = el("span", { class: "rate" });
  const maxText = el("span", { class: "ter", style: "font-size:10px;font-weight:500;margin-left:auto" });
  const downSpark = sparkline(307, 70, "var(--accent)", 0.2);
  const upSpark = sparkline(307, 70, "var(--upload)", 0.15);
  const rateRow = (name, color, title, value, tip) => el(
    "div",
    { class: "row", style: "gap:6px", title: tip },
    el("span", { style: `color:${color};width:14px;display:flex;justify-content:center` }, icon(name, 13, "ic-bold")),
    el("span", { class: "sec", style: "font-size:12px", text: title }),
    el("span", { style: "flex:1" }),
    value
  );
  ui.storage = { set(u) {
    storage.set(u.used / u.total);
    rollText(storageValue, percent(u.used / u.total));
    storageText.textContent = `${bytes(u.used)} of ${bytes(u.total)}`;
  } };
  ui.memory = { set(u) {
    memory.set(u.used / u.total);
    rollText(memValue, percent(u.used / u.total));
    memText.textContent = `${bytes(u.used, true)} of ${bytes(u.total, true)}`;
  } };
  ui.network = {
    scale: 1e4,
    drawn: 1e4,
    anim: 0,
    set(n) {
      down.textContent = rate(n.down);
      upEl.textContent = rate(n.up);
      total.textContent = `↓ ${bytes(n.totalDown)}   ↑ ${bytes(n.totalUp)}`;
      const target = Math.max(Math.max(...n.downHistory, ...n.upHistory, 0), 1e4);
      const draw = (s) => {
        downSpark.draw(n.downHistory, s);
        upSpark.draw(n.upHistory, s);
      };
      maxText.textContent = `max ${rate(target)}`;
      if (target === this.scale || reduceMotion) {
        this.scale = this.drawn = target;
        draw(target);
        return;
      }
      const from = this.drawn, start = performance.now();
      this.scale = target;
      cancelAnimationFrame(this.anim);
      const step = (now) => {
        const p = Math.min((now - start) / 500, 1);
        this.drawn = from + (target - from) * spatial(p);
        draw(this.drawn);
        if (p < 1) this.anim = requestAnimationFrame(step);
      };
      this.anim = requestAnimationFrame(step);
    }
  };
  const tankContent = (inverted) => el(
    "div",
    { class: `tank-content${inverted ? " inv" : ""}`, "aria-hidden": inverted ? "true" : null },
    el("div", { class: "row tank-head", style: "gap:6px;justify-content:flex-start" }, icon("battery", 18), el("span", { style: "font-size:15px;font-weight:600", text: "Battery" })),
    el("div", { style: "flex:1" }),
    el("span", { class: "rounded", style: "font-size:30px;font-weight:600;line-height:36px", text: "82 %" }),
    el("span", { class: "tank-status", style: "font-size:12px", text: "7h 11m Left" })
  );
  return el(
    "div",
    { class: "perf" },
    heroCard(ui, "cpu", "cpu", "CPU", 0),
    heroCard(ui, "gpu", "stack", "GPU", 355),
    card("storage", 41, "left:0;top:203px;width:169.5px;height:189px;gap:6px", storage.wrap, storageText),
    card(
      "network",
      24,
      "left:181.5px;top:203px;width:335px;height:189px;align-items:stretch",
      el(
        "div",
        { class: "col", style: "padding:14px;height:100%;align-items:stretch;gap:0" },
        el(
          "div",
          { class: "row", style: "gap:6px;justify-content:flex-start" },
          el("span", { class: "accent", style: "display:flex" }, icon("arrowsUpDown", 15, "ic-bold")),
          el("span", { style: "font-size:15px;font-weight:600", text: "Network" }),
          maxText
        ),
        el("div", { class: "net-graph baseline" }, upSpark.svg, downSpark.svg),
        el(
          "div",
          { class: "col", style: "gap:4px;align-items:stretch" },
          rateRow("arrowDown", "var(--accent)", "Download", down),
          rateRow("arrowUp", "var(--upload)", "Upload", upEl),
          rateRow("history", "var(--sec)", "Total", total, "Since this tab was first opened")
        )
      )
    ),
    card(
      "memory",
      10,
      "left:528.5px;top:203px;width:169.5px;height:189px;gap:6px",
      el("div", { class: "row", style: "gap:6px" }, el("span", { class: "accent", style: "display:flex" }, icon("memory", 15, "ic-bold")), el("span", { style: "font-size:13px;font-weight:600", text: "Memory" })),
      memory.wrap,
      memText
    ),
    el(
      "div",
      { class: "tank", role: "img", "aria-label": "Battery 82 percent, 7h 11m left", style: "left:710px;top:0;width:129px;height:392px;--fill:82%" },
      tankContent(false),
      el("div", { class: "tank-fill" }),
      tankContent(true)
    )
  );
}
function setupPerformance(ui) {
  const cpuHistory = [], gpuHistory = [], downHistory = [], upHistory = [];
  const push = (list, v) => {
    list.push(v);
    if (list.length > 30) list.shift();
  };
  let t = 0, totalDown = 0, totalUp = 0, memUsed = 98e8;
  let last = null;
  const sample = (live) => {
    const busy = Math.floor(24 + 14 * Math.sin(t / 2.5) + t % 3 * 3 + (live ? Math.random() * 6 - 3 : 0));
    const cpu = Math.min(Math.max(busy, 1), 99) / 100;
    const gpu = 0.21 + 0.12 * Math.sin(t / 4) + (live ? Math.random() * 0.03 : 0);
    const down = Math.max(11e5 + 8e5 * Math.sin(t / 3) + (t % 23 === 22 ? 22e5 : 0), 0);
    const up = Math.max(16e4 + 11e4 * Math.cos(t / 4), 0);
    if (live) memUsed = Math.min(Math.max(memUsed + (Math.random() - 0.5) * 6e7, 94e8), 104e8);
    if (t > 0) {
      push(cpuHistory, cpu);
      totalDown += down;
      totalUp += up;
      push(downHistory, down);
      push(upHistory, up);
      last = { cpu, down, up };
    }
    push(gpuHistory, gpu);
    t++;
    return { gpu };
  };
  for (let i = 0; i < 34; i++) sample(false);
  const apply = () => {
    ui.cpu.set(last.cpu, cpuHistory);
    ui.gpu.set(gpuHistory[gpuHistory.length - 1], gpuHistory);
    ui.memory.set({ used: memUsed, total: 16 * 2 ** 30 });
    ui.storage.set({ used: 212e9, total: 494e9 });
    ui.network.set({ down: last.down, up: last.up, totalDown, totalUp, downHistory, upHistory });
  };
  apply();
  return () => {
    sample(true);
    apply();
  };
}
function weatherTab() {
  const now = new Date();
  const stat = (glyph, label, value) => el(
    "div",
    { class: "row", style: "gap:8px;justify-content:flex-start" },
    el("span", { class: "wx-stat-ic" }, glyph),
    el(
      "div",
      { class: "col", style: "align-items:flex-start;gap:0" },
      el("span", { class: "sec", style: "font-size:11px", text: label }),
      el("span", { style: "font-size:14px;font-weight:600", text: value })
    )
  );
  const sunGlyph = (name) => {
    const g = icon(name, 20);
    g.classList.add("wx-sunicon");
    return g;
  };
  const hero = card(
    "wx-hero",
    28,
    "left:0;top:0;width:839px;height:116px;justify-content:flex-start",
    el(
      "div",
      { class: "row", style: "gap:18px;padding:0 28px 0 22px;width:100%" },
      el("div", { style: "width:72px;display:flex;justify-content:center" }, weatherGlyph("cloudSun", 70)),
      el("span", { class: "rounded", style: "font-size:60px;font-weight:500;line-height:72px", text: temp(WEATHER.temp) }),
      el(
        "div",
        { class: "col", style: "gap:3px;align-items:flex-start" },
        el("span", { style: "font-size:19px;font-weight:600", text: "Partly Cloudy" }),
        el("span", { class: "sec", style: "font-size:13px", text: `Feels like ${temp(WEATHER.feels)} · H:${temp(WEATHER.highs[0])} L:${temp(WEATHER.lows[0])}` })
      ),
      el("div", { style: "flex:1;min-width:12px" }),
      el(
        "div",
        { class: "wx-stats" },
        stat(icon("droplet", 18, "wx-drop"), "Humidity", `${WEATHER.humidity} %`),
        stat(sunGlyph("sunrise"), "Sunrise", "06:36"),
        stat(icon("wind", 19), "Wind", `${WEATHER.wind} km/h`),
        stat(sunGlyph("sunset"), "Sunset", "19:17")
      )
    ),
    el("span", { class: "ter wx-attr", text: "Weather data: Open-Meteo" })
  );
  const slots = [];
  for (let k = 0; k < 24; k += 2) {
    const d = new Date(now.getTime() + k * 36e5);
    const hour = d.getHours();
    const code = k === 0 ? WEATHER.code : WEATHER.hourCodes[(k + 2) % 24];
    const isDay = hour >= 7 && hour < 19;
    const precip = code >= 61 ? 60 : code === 3 ? 20 : 5;
    const t = k === 0 ? WEATHER.temp : 14.5 + 5.5 * Math.sin((hour - 9) / 24 * 2 * Math.PI);
    slots.push(el(
      "div",
      { class: "col wx-slot", role: "listitem" },
      el("span", { class: k === 0 ? "" : "sec", style: `font-size:12px;font-weight:${k === 0 ? 600 : 500}`, text: k === 0 ? "Now" : `${hour}:00` }),
      el("div", { style: "height:26px;display:flex;align-items:center" }, weatherGlyph(weatherKind(code, isDay), 25)),
      el("span", { class: "precip", text: precip >= 20 ? `${precip} %` : " " }),
      el("span", { class: "rounded", style: "font-size:15px;font-weight:600", text: temp(t) })
    ));
  }
  const hourly = card(
    "wx-hourly",
    24,
    "left:0;top:128px;width:839px;height:108px",
    el("div", { class: "row", role: "list", "aria-label": "Next 24 hours", style: "width:100%;padding:0 10px" }, slots)
  );
  const days = [];
  for (let i = 0; i < 7; i++) {
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
    const code = WEATHER.dayCodes[i];
    const label = i === 0 ? "Today" : d.toLocaleDateString("en-US", { weekday: "short" }).slice(0, 2);
    const precip = code >= 61 ? 65 : 10;
    days.push(card(
      "wx-day",
      20,
      `left:${i * (111 + 1 / 7 + 12)}px;top:248px;width:${111 + 1 / 7}px;height:144px`,
      el(
        "div",
        { class: "col", style: "gap:4px" },
        el("span", { class: `wx-dayname${i === 0 ? " today" : ""}`, text: label }),
        el("span", { class: "sec", style: "font-size:11px", text: `${d.getMonth() + 1}/${d.getDate()}` }),
        el("div", { style: "height:32px;margin-top:2px;display:flex;align-items:center" }, weatherGlyph(weatherKind(code, true), 30)),
        el("span", { class: "precip", text: precip >= 20 ? `${precip} %` : " " }),
        el(
          "span",
          { class: "rounded", style: "font-size:14px;font-weight:600;display:flex;gap:6px" },
          el("span", { text: temp(WEATHER.highs[i]) }),
          el("span", { class: "sec", text: temp(WEATHER.lows[i]) })
        )
      )
    ));
  }
  return el("div", { class: "wx-tab", title: `Weather in ${WEATHER.city}` }, hero, hourly, days);
}
const TAB_LIST = [
  { id: "dashboard", title: "Dashboard" },
  { id: "media", title: "Media" },
  { id: "performance", title: "Performance" },
  { id: "weather", title: "Weather" }
];
function tabGlyph(id, selected) {
  if (id === "dashboard") return icon(selected ? "gridFill" : "grid", 19);
  if (id === "media") return icon("playlist", 20);
  if (id === "performance") return icon("gauge", 20);
  return weatherTabGlyph(selected, 22);
}
function build(host2) {
  const state = { covers: [], texts: [], timelines: [], arcs: [], playButtons: [], playStates: [] };
  const perfUI = {};
  const stage = el("div", { class: "panel-stage dash" });
  const tabsEl = el("div", { class: "dash-tabs", role: "tablist", "aria-label": "Dashboard tabs" });
  const indicator = el("span", { class: "dash-indicator", "aria-hidden": "true" });
  const body = el("div", { class: "dash-body" });
  const panes = {
    dashboard: el("div", { class: "dash-grid" }, smallWeatherCard(), userCard(state), clockCard(state), calendarCard(state), resourcesCard(state), mediaDashCard(state)),
    media: mediaTab(state),
    performance: performanceTab(perfUI),
    weather: weatherTab()
  };
  const buttons = {};
  const tabW = GRID_W / TAB_LIST.length;
  let current = "dashboard";
  TAB_LIST.forEach((t, i) => {
    const glyph = el("span", { class: "tab-glyph" });
    const b = el(
      "button",
      { type: "button", class: "dash-tab", role: "tab", id: `dash-tab-${t.id}`, "aria-controls": `dash-pane-${t.id}`, onclick: () => select(t.id) },
      glyph,
      el("span", { class: "tab-title", text: t.title })
    );
    b.glyph = glyph;
    buttons[t.id] = b;
    tabsEl.append(b);
    const pane = el("div", { class: "dash-pane", role: "tabpanel", id: `dash-pane-${t.id}`, "aria-labelledby": `dash-tab-${t.id}` }, panes[t.id]);
    panes[t.id].pane = pane;
    body.append(pane);
    b.index = i;
  });
  tabsEl.append(indicator);
  tabsEl.addEventListener("keydown", (e) => {
    const step = { ArrowRight: 1, ArrowLeft: -1 }[e.key];
    if (!step) return;
    e.preventDefault();
    const i = (TAB_LIST.findIndex((t) => t.id === current) + step + TAB_LIST.length) % TAB_LIST.length;
    select(TAB_LIST[i].id);
    buttons[TAB_LIST[i].id].focus();
  });
  let perfTick = null;
  function select(id) {
    current = id;
    for (const t of TAB_LIST) {
      const on = t.id === id;
      const b = buttons[t.id];
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
      b.glyph.replaceChildren(tabGlyph(t.id, on));
      const pane = panes[t.id].pane;
      pane.classList.toggle("is-active", on);
      pane.inert = !on;
    }
    indicator.style.transform = `translateX(${PAD + buttons[id].index * tabW + tabW / 2 - 22}px)`;
    if (id === "performance" && !perfTick) perfTick = setupPerformance(perfUI);
  }
  select("dashboard");
  const slide = el(
    "div",
    { class: "dash-slide" },
    el("div", { class: "glass dash-glass", "aria-hidden": "true" }),
    tabsEl,
    el("div", { class: "dash-divider", "aria-hidden": "true" }),
    body
  );
  stage.append(el("div", { class: "dash-clip" }, slide));
  setupMedia(state, stage);
  let cpu = 0.18, mem = 0.54;
  const bootAt = Date.now() - (3 * 3600 + 25 * 60) * 1e3;
  const second = (animate) => {
    const now = new Date();
    state.hour.textContent = two(now.getHours());
    state.minute.textContent = two(now.getMinutes());
    state.uptimeText.textContent = `running since ${uptime((Date.now() - bootAt) / 1e3)}`;
    if (state.calendarDay !== now.toDateString()) state.renderCalendar();
    if (animate) {
      cpu = Math.min(Math.max(cpu + (Math.random() - 0.5) * 0.08, 0.08), 0.42);
      mem = Math.min(Math.max(mem + (Math.random() - 0.5) * 0.01, 0.5), 0.58);
    }
    state.rings.cpu.set(cpu);
    state.rings.memory.set(mem);
    state.rings.storage.set(0.41);
    if (animate && current === "performance" && perfTick) perfTick();
  };
  second(false);
  let timer = 0;
  let count = 0;
  const run = (on) => {
    clearInterval(timer);
    if (!on) return;
    timer = setInterval(() => {
      count++;
      if (!reduceMotion && state.isPlaying()) state.tickMedia();
      if (count % 2 === 0) second(!reduceMotion);
    }, 500);
  };
  fit(host2, stage, WIDTH, HEIGHT);
  mount(host2, stage);
  whenVisible(host2, (visible) => {
    stage.classList.toggle("is-visible", visible);
    if (visible) {
      if (!stage.classList.contains("is-open")) {
        if (!reduceMotion) {
          slide.classList.add("no-anim");
          select(current);
          void slide.offsetHeight;
          slide.classList.remove("no-anim");
        }
        state.resetCalendar();
        stage.classList.add("is-open");
      }
      second(false);
      run(true);
    } else {
      run(false);
      stage.classList.remove("is-open");
    }
  });
}
const host = document.querySelector('.panel-host[data-panel="dashboard"]');
if (host) build(host);
