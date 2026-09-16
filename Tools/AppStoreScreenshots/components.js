// Builds the pieces every frame uses: the record, the iPhone, the Mac window, and breakouts.
// Each page describes its frames as data and calls these to draw them.

const SVG_NS = "http://www.w3.org/2000/svg";

function el(tag, style = {}, attrs = {}) {
  const node = document.createElement(tag);
  Object.assign(node.style, style);
  for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
  return node;
}

const px = (n) => `${n}px`;

// The icon's record, from AppIcon.icon/Assets, in its own 1024-unit space.
// `played` is how much of the ring the white arc covers, in degrees. The icon uses 265.
function record({ cx, cy, r, played = 265, rotate = 0 }) {
  const box = el("div", {
    left: px(cx - r),
    top: px(cy - r),
    width: px(r * 2),
    height: px(r * 2),
    transform: rotate ? `rotate(${rotate}deg)` : "",
  });
  box.className = "record";

  let fine = "";
  for (let radius = 160; radius <= 328; radius += 4.5) {
    const alpha = radius % 9 < 4.5 ? 0.05 : 0.025;
    fine += `<circle cx="512" cy="512" r="${radius}" fill="none" stroke="#fff" stroke-width="0.9" opacity="${alpha}"/>`;
  }

  const arc = (() => {
    if (played >= 359.5) {
      return `<circle cx="512" cy="512" r="226" fill="none" stroke="#fff" stroke-width="66"/>`;
    }
    const end = ((-90 + played) * Math.PI) / 180;
    const x = 512 + 226 * Math.cos(end);
    const y = 512 + 226 * Math.sin(end);
    const large = played > 180 ? 1 : 0;
    return `<path d="M512,286 A226,226 0 ${large} 1 ${x.toFixed(2)},${y.toFixed(2)}" fill="none" stroke="#fff" stroke-width="66" stroke-linecap="round"/>`;
  })();

  box.innerHTML = `
    <svg viewBox="178 178 668 668" xmlns="${SVG_NS}">
      <defs>
        <radialGradient id="vinylShade" cx="0.5" cy="0.42" r="0.6">
          <stop offset="0" stop-color="#2a262c"/>
          <stop offset="1" stop-color="#141216"/>
        </radialGradient>
        <filter id="soften" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="9"/></filter>
        <clipPath id="disc"><circle cx="512" cy="512" r="332"/></clipPath>
        <linearGradient id="labelShade" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#ff6a7f"/>
          <stop offset="1" stop-color="#f23a55"/>
        </linearGradient>
      </defs>
      <circle cx="512" cy="512" r="334" fill="url(#vinylShade)"/>
      ${fine}
      <circle cx="512" cy="512" r="302" fill="none" stroke="#fff" stroke-width="5" opacity="0.22"/>
      <circle cx="512" cy="512" r="150" fill="none" stroke="#fff" stroke-width="5" opacity="0.22"/>
      <path d="M512.0,512.0 L665.99,222.39 A328,328 0 0 1 801.61,358.01 ZM512.0,512.0 L358.01,801.61 A328,328 0 0 1 222.39,665.99 ZM394.00,512.00 a118.00,118.00 0 1,0 236.00,0 a118.00,118.00 0 1,0 -236.00,0 Z" fill="#fff" fill-rule="evenodd" opacity="0.11" filter="url(#soften)" clip-path="url(#disc)"/>
      <circle cx="512" cy="512" r="226" fill="none" stroke="#fff" stroke-width="66" opacity="0.12"/>
      ${arc}
      <path d="M398,512 a114,114 0 1,0 228,0 a114,114 0 1,0 -228,0 ZM492,512 a20,20 0 1,0 40,0 a20,20 0 1,0 -40,0 Z" fill="url(#labelShade)" fill-rule="evenodd"/>
      <circle cx="512" cy="512" r="333" fill="none" stroke="#fff" stroke-width="1.2" opacity="0.18"/>
    </svg>`;
  return box;
}

// Faint rings centred on a point, like the grooves of a record too big to fit the set.
function grooves({ cx, cy, from, to, step, opacity = 0.07, width = 3, fade }) {
  const size = to * 2 + 20;
  const box = el("div", { position: "absolute", left: px(cx - size / 2), top: px(cy - size / 2), width: px(size), height: px(size) });
  if (fade) {
    const mask = `radial-gradient(circle at center, transparent ${fade[0]}px, #000 ${fade[1]}px, #000 ${fade[2]}px, transparent ${fade[3]}px)`;
    box.style.maskImage = mask;
    box.style.webkitMaskImage = mask;
  }
  let rings = "";
  for (let radius = from; radius <= to; radius += step) {
    rings += `<circle cx="${size / 2}" cy="${size / 2}" r="${radius}" fill="none" stroke="#fff" stroke-width="${width}" opacity="${opacity}"/>`;
  }
  box.innerHTML = `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" xmlns="${SVG_NS}">${rings}</svg>`;
  return box;
}

// An iPhone 6.9" at `s` pixels per point. The screen is 440 × 956 pt, like the captures.
function iphone({ src, left, top, s }) {
  const phone = el("div", { left: px(left), top: px(top) });
  phone.className = "iphone";
  phone.style.setProperty("--s", s);

  const buttons = [
    { side: "left", top: 172, height: 30 },
    { side: "left", top: 232, height: 60 },
    { side: "left", top: 306, height: 60 },
    { side: "right", top: 262, height: 96 },
    { side: "right", top: 560, height: 62 },
  ];
  for (const b of buttons) {
    const button = el("div", {
      top: px(b.top * s),
      height: px(b.height * s),
      [b.side]: px(-2.6 * s),
    });
    button.className = "button";
    phone.append(button);
  }

  const bezel = el("div");
  bezel.className = "bezel";
  const screen = el("div");
  screen.className = "screen";
  const img = el("img", {}, { src });
  const island = el("div");
  island.className = "island";
  screen.append(img, island);
  bezel.append(screen);
  phone.append(bezel);
  return phone;
}

// Where a point in a 1320 × 2868 capture lands on a phone drawn by iphone().
function onPhone(phone, x, y) {
  const k = (440 * phone.s) / 1320;
  const inset = 11 * phone.s;
  return { x: phone.left + inset + x * k, y: phone.top + inset + y * k, k };
}

// A Mac window capture (2360 × 1600, the window at 1180 × 800 pt), drawn `width` pixels wide.
function macWindow({ src, left, top, width, natural = [2360, 1600] }) {
  const height = (width * natural[1]) / natural[0];
  const box = el("div", { left: px(left), top: px(top), width: px(width), height: px(height) });
  box.className = "window";
  box.append(el("img", {}, { src }));
  return box;
}

// A rectangle of a capture, scaled by `k` and centred on (cx, cy).
function breakout({ src, natural, crop, k, cx, cy, radius }) {
  const [x, y, w, h] = crop;
  const box = el("div", {
    left: px(cx - (w * k) / 2),
    top: px(cy - (h * k) / 2),
    width: px(w * k),
    height: px(h * k),
    borderRadius: px(radius),
    backgroundImage: `url("${src}")`,
    backgroundSize: `${natural[0] * k}px ${natural[1] * k}px`,
    backgroundPosition: `${-x * k}px ${-y * k}px`,
  });
  box.className = "breakout";
  return box;
}

function copy({ top, headline, sub, size, subSize, subWidth, align = "center", left = 0, right = 0 }) {
  const block = el("div", { top: px(top), left: px(left), right: px(right), textAlign: align });
  block.className = "copy";
  const h = el("h1", { fontSize: px(size) });
  h.className = "headline";
  h.textContent = headline;
  block.append(h);
  if (sub) {
    const p = el("p", { fontSize: px(subSize), maxWidth: px(subWidth), marginTop: px(subSize * 0.62), lineHeight: 1.26 });
    if (align !== "center") p.style.marginLeft = "0";
    p.className = "sub";
    p.textContent = sub;
    block.append(p);
  }
  return block;
}

function pills({ top, items, size, gap, width, left = 0 }) {
  const row = el("div", { position: "absolute", top: px(top), left: px(left), width: px(width), gap: px(gap) });
  row.className = "pills";
  for (const text of items) {
    const pill = el("span", { fontSize: px(size), padding: `${size * 0.42}px ${size * 0.78}px` });
    pill.className = "pill";
    pill.textContent = text;
    row.append(pill);
  }
  return row;
}

function frame(index, width, height) {
  const node = el("section", { left: px(index * width), width: px(width), height: px(height) });
  node.className = "frame";
  node.dataset.index = index;
  return node;
}
