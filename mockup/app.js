// Design mockup only: all metrics below are simulated.
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const rnd = (a, b) => a + Math.random() * (b - a);
const SVG = 'http://www.w3.org/2000/svg';
const svgEl = (tag, attrs = {}) => { const e = document.createElementNS(SVG, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); return e; };

const CORES = 18, HISTORY = 60, FAN_MAX = 6400, T_MIN = 40, T_MAX = 100;
const state = {
  open: false, fanMode: 'auto', lightMode: 'auto', procSort: 'cpu',
  cores: Array.from({ length: CORES }, () => rnd(0.05, 0.3)), load: 0.25,
  gpu: Array.from({ length: HISTORY }, (_, i) => 0.25 + 0.15 * Math.sin(i / 6) + rnd(0, 0.08)),
  down: Array.from({ length: HISTORY }, (_, i) => (i % 17 < 4 ? rnd(0.4, 0.9) : rnd(0.02, 0.2))), up: Array.from({ length: HISTORY }, () => rnd(0.02, 0.4)),
  temps: { cpu: 52, gpu: 48, ssd: 39, batt: 33, shell: 31 }, rpm: [0, 0], angle: [0, 0],
  curve: [[40, 0], [60, 1800], [80, 4200], [95, 6400]], level: 0, nextKick: 0,
};
const PROCS = [['Xcode', 38, 6.2], ['WindowServer', 12, 1.4], ['Google Chrome Helper', 21, 4.8], ['python3.12', 64, 11.3], ['Devin', 6, 0.9], ['mds_stores', 9, 0.6], ['Music', 3, 0.7]];

/* ── static builders ── */
function buildStatic() {
  for (const g of $$('.blades')) for (let i = 0; i < 13; i++) g.append(svgEl('path', { d: 'M0 -7 Q9 -13 5 -24', transform: `rotate(${i * 360 / 13})` }));
  $('#cores').innerHTML = '<div><i></i></div>'.repeat(CORES);
  $('#wave').innerHTML = '<i></i>'.repeat(9);
  const today = (new Date().getDay() + 6) % 7, cells = [];
  for (let w = 0; w < 26; w++) for (let d = 0; d < 7; d++) {
    if (w === 25 && d > today) { cells.push('<i class="future"></i>'); continue; }
    const base = d > 4 ? 0.9 : 2.4, l = clamp(Math.round(base + rnd(-1.6, 1.6)), 0, 4);
    cells.push(`<i data-l="${l}"></i>`);
  }
  $('#heatmap').innerHTML = cells.join('');
  const disk = [816, 818, 823, 822, 829, 834, 833, 840, 846, 845, 851, 854];
  spark($('#diskSpark'), disk.map(v => (v - 800) / 70), 24);
  const grid = $('#curve .grid');
  for (let i = 1; i < 4; i++) grid.append(svgEl('line', { x1: 0, x2: 400, y1: 6 + i * 21.5, y2: 6 + i * 21.5 }));
}

/* ── drawing helpers ── */
function linePath(data, h, x0 = 0, w = 100) { return data.map((v, i) => `${i ? 'L' : 'M'}${(x0 + i / (data.length - 1) * w).toFixed(1)} ${(h - 1 - clamp(v, 0, 1) * (h - 2)).toFixed(1)}`).join(''); }
function spark(svg, data, h) {
  const d = linePath(data, h);
  $('.line', svg).setAttribute('d', d);
  $('.area', svg).setAttribute('d', `${d}L100 ${h}L0 ${h}Z`);
}
function netChart() {
  const [a, b] = $$('#netSpark .area'), mid = 26, n = HISTORY - 1;
  const path = (data, dir, amp) => `M0 ${mid}` + data.map((v, i) => `L${(i / n * 100).toFixed(1)} ${(mid - dir * clamp(v, 0, 1) * amp).toFixed(1)}`).join('') + `L100 ${mid}Z`;
  a.setAttribute('d', path(state.down, 1, 25)); b.setAttribute('d', path(state.up, -1, 13));
}
const fmtRate = v => v >= 1 ? `${v.toFixed(1)} MB/s` : `${Math.round(v * 1000)} KB/s`;

/* ── 1 Hz data tick (the real app samples at 1–2 s as well) ── */
function tick() {
  const s = state;
  s.load = clamp(s.load + rnd(-0.12, 0.13), 0.06, 0.95);
  s.cores = s.cores.map((c, i) => clamp(c * 0.5 + (s.load * (i < 6 ? 1.25 : 0.8) + rnd(-0.25, 0.25)) * 0.5, 0.01, 1));
  const total = s.cores.reduce((a, b) => a + b) / CORES;
  $$('#cores i').forEach((el, i) => { el.style.transform = `scaleY(${s.cores[i].toFixed(3)})`; el.style.background = s.cores[i] > 0.85 ? 'var(--heat)' : ''; });
  $('#cpuTotal').textContent = `${Math.round(total * 100)}%`;
  $('#cpuSub').textContent = `用户 ${Math.round(total * 72)}% · 系统 ${Math.round(total * 28)}% · 负载 ${(total * 9).toFixed(2)} ·`;

  const gpu = clamp(s.gpu.at(-1) + rnd(-0.1, 0.1), 0.02, 0.9);
  s.gpu = [...s.gpu.slice(1), gpu]; spark($('#gpuSpark'), s.gpu, 24);
  $('#gpuTotal').textContent = `${Math.round(gpu * 100)}%`; $('#gpuMem').textContent = `${Math.round(18 + gpu * 30)}%`; $('#gpuTemp').textContent = `${Math.round(s.temps.gpu)}°`; $('#gpuFps').textContent = Math.round(gpu > 0.08 ? 120 - gpu * 40 : 0);
  $('#gpuFreq').textContent = (0.34 + gpu * 1.1).toFixed(2); $('#gpuW').textContent = (1 + gpu * 28).toFixed(1);

  const app = 24 + total * 14, wired = 6.1, comp = 3.4;
  [app, wired, comp].forEach((v, i) => { $$('#memBar i')[i].style.width = `${v / 64 * 100}%`; });
  $('#memUsed').textContent = (app + wired + comp).toFixed(1);

  const down = Math.random() < 0.15 ? rnd(0.5, 1) : clamp(s.down.at(-1) * 0.7 + rnd(0, 0.15), 0.01, 1), up = clamp(s.up.at(-1) * 0.6 + rnd(0, 0.2), 0.01, 1);
  s.down = [...s.down.slice(1), down]; s.up = [...s.up.slice(1), up]; netChart();
  $('#netDown').textContent = fmtRate(down * 42); $('#netUp').textContent = fmtRate(up * 6);
  $('#ping').textContent = `${Math.round(rnd(26, 33))} ms`; $('#diskIO').textContent = `读 ${Math.round(rnd(0, 40))} 写 ${Math.round(rnd(0, 12))} MB/s`;

  const cool = (s.rpm[0] / FAN_MAX) * 22;
  const target = { cpu: 44 + total * 62 - cool, gpu: 42 + gpu * 45 - cool * 0.8, ssd: 37 + total * 10, batt: 31 + total * 6, shell: 29 + total * 9 };
  for (const k in target) s.temps[k] += (target[k] - s.temps[k]) * 0.25;
  renderTemps(); renderProcs(total);
}
function renderTemps() {
  const names = { cpu: 'CPU', gpu: 'GPU', ssd: 'SSD', batt: '电池', shell: '外壳' };
  for (const k in names) {
    const t = state.temps[k], heat = $(`.heat[data-k=${k}]`);
    heat.style.opacity = clamp((t - 30) / 55, 0.05, 1); heat.classList.toggle('hot', t > 85);
    $(`#tlabels [data-k=${k}]`).textContent = `${names[k]} ${Math.round(t)}°`;
  }
  $('#curve .now').setAttribute('x1', tx(state.temps.cpu)); $('#curve .now').setAttribute('x2', tx(state.temps.cpu));
  $('#curveRead').textContent = `CPU ${Math.round(state.temps.cpu)}° → ${Math.round(curveRpm(state.temps.cpu))} rpm`;
}
function renderProcs(total) {
  const mem = state.procSort === 'mem', idx = mem ? 2 : 1;
  const rows = PROCS.map(p => [p[0], p[1] * (0.4 + total * 1.6) * rnd(0.9, 1.1), p[2]]).sort((a, b) => b[idx] - a[idx]).slice(0, 4);
  const max = rows[0][idx];
  $('#procs').innerHTML = rows.map(r => `<li><span>${r[0]}</span><u><i style="width:${r[idx] / max * 100}%"></i></u><em>${mem ? r[2].toFixed(1) + ' GB' : r[1].toFixed(1) + '%'}</em></li>`).join('');
}

/* ── fan curve editor ── */
const tx = t => (clamp(t, T_MIN, T_MAX) - T_MIN) / (T_MAX - T_MIN) * 400, ry = r => 92 - r / FAN_MAX * 86;
function curveRpm(t) {
  const c = state.curve; if (t <= c[0][0]) return c[0][1]; if (t >= c.at(-1)[0]) return c.at(-1)[1];
  const i = c.findIndex(p => p[0] > t), [a, b] = [c[i - 1], c[i]];
  return a[1] + (b[1] - a[1]) * (t - a[0]) / (b[0] - a[0]);
}
function drawCurve() {
  const c = state.curve, d = `M0 ${ry(c[0][1])}` + c.map(p => `L${tx(p[0])} ${ry(p[1])}`).join('') + `L400 ${ry(c.at(-1)[1])}`;
  $('#curve .line').setAttribute('d', d); $('#curve .area').setAttribute('d', `${d}L400 92L0 92Z`);
  const pts = $('#curve .pts');
  if (!pts.children.length) c.forEach((_, i) => { const dot = svgEl('circle', { r: 5 }); dot.dataset.i = i; pts.append(dot); });
  c.forEach((p, i) => { pts.children[i].setAttribute('cx', tx(p[0])); pts.children[i].setAttribute('cy', ry(p[1])); });
}
function bindCurve() {
  const svg = $('#curve'); let drag = -1;
  svg.addEventListener('pointerdown', e => { if (e.target.dataset.i === undefined) return; drag = +e.target.dataset.i; svg.setPointerCapture(e.pointerId); });
  svg.addEventListener('pointermove', e => {
    if (drag < 0) return;
    const r = svg.getBoundingClientRect(), c = state.curve, x = (e.clientX - r.left) / r.width * 400, y = (e.clientY - r.top) / r.height * 110;
    const lo = drag ? c[drag - 1][0] + 2 : T_MIN, hi = drag < c.length - 1 ? c[drag + 1][0] - 2 : T_MAX;
    c[drag] = [clamp(T_MIN + x / 400 * (T_MAX - T_MIN), lo, hi), clamp((92 - y) / 86 * FAN_MAX, 0, FAN_MAX)];
    drawCurve();
  });
  const end = () => { drag = -1; }; svg.addEventListener('pointerup', end); svg.addEventListener('pointercancel', end);
}

/* ── per-frame animation: fans + logo light (paused while the card is closed) ── */
function lightGlow(t) {
  const s = state;
  if (s.lightMode === 'auto') return 0.85;
  if (s.lightMode === 'breathe') return 0.12 + 0.88 * Math.pow(Math.sin(t / 4500 * Math.PI) ** 2, 1.6);
  if (t > s.nextKick) { s.level = rnd(0.6, 1); s.nextKick = t + rnd(260, 620); s.kickAt = t; }
  s.level *= 0.94;
  return 0.2 + 0.8 * s.level;
}
let last = 0;
function frame(t) {
  if (!state.open) return;
  const dt = clamp(t - last, 0, 50) / 1000; last = t;
  const s = state, auto = clamp((s.temps.cpu - 48) * 95, 0, FAN_MAX);
  const target = s.fanMode === 'max' ? FAN_MAX : s.fanMode === 'curve' ? curveRpm(s.temps.cpu) : auto;
  ['#fanL', '#fanR'].forEach((id, i) => {
    s.rpm[i] += ((target && target * (i ? 1.04 : 1)) - s.rpm[i]) * Math.min(1, dt * 1.6);
    s.angle[i] = (s.angle[i] + s.rpm[i] * 0.22 * dt) % 360;
    $(`${id} .blades`).setAttribute('transform', `rotate(${s.angle[i].toFixed(1)})`);
    const k = s.rpm[i] / FAN_MAX; $(`${id} .fan-ring`).style.stroke = `hsl(${(205 - k * 190).toFixed(0)} 90% ${(55 + k * 10).toFixed(0)}% / ${(0.3 + k * 0.7).toFixed(2)})`;
  });
  $('#fanRead').textContent = `${Math.round(s.rpm[0] / 10) * 10} · ${Math.round(s.rpm[1] / 10) * 10} rpm`;
  const glow = lightGlow(t), audio = s.lightMode === 'audio';
  $('#logo').style.opacity = 0.18 + 0.82 * glow; $('#halo').style.opacity = glow * 0.75;
  $$('#rings circle').forEach((c, i) => {
    const p = audio ? ((t - (s.kickAt || 0)) / 700 - i * 0.22) : -1, on = p > 0 && p < 1;
    c.setAttribute('cx', 170); c.setAttribute('cy', 111); c.setAttribute('r', on ? 20 + p * 46 : 0); c.style.opacity = on ? (1 - p) * 0.5 : 0;
  });
  $$('#wave i').forEach((b, i) => { b.style.transform = `scaleY(${audio ? clamp(s.level * (0.5 + 0.5 * Math.sin(t / 90 + i * 1.7)) + 0.12, 0.12, 1) : 0.12})`; });
  requestAnimationFrame(frame);
}

/* ── interactions ── */
const SUBS = {
  fanMode: { auto: '跟随 macOS 温控策略', max: '全速运行 · 离开高负载后记得切回', curve: '按下方自定义温度曲线' },
  lightMode: { auto: '跟随 macOS 默认行为', breathe: '预设呼吸曲线 · 4.5 秒一次', audio: '随系统声音（含提示音）律动' },
};
function setOpen(open) {
  state.open = open;
  $('.desktop').classList.toggle('open', open); $('#card').setAttribute('aria-hidden', !open);
  $('#shadow').style.height = `${$('#card').offsetHeight}px`;
  if (open) { last = performance.now(); requestAnimationFrame(frame); }
}
function bind() {
  $('#notch').addEventListener('click', e => { e.stopPropagation(); setOpen(!state.open); });
  $('#card').addEventListener('click', e => e.stopPropagation());
  document.addEventListener('click', () => setOpen(false));
  document.addEventListener('keydown', e => { if (e.key === 'Escape') setOpen(false); });
  $('#tempToggle').addEventListener('click', e => { e.currentTarget.classList.toggle('on'); $('#model').classList.toggle('no-temp'); });
  for (const seg of $$('.seg')) seg.addEventListener('click', e => {
    const btn = e.target.closest('button'); if (!btn) return;
    const key = seg.dataset.key, btns = $$('button', seg);
    btns.forEach(b => b.classList.toggle('on', b === btn)); seg.style.setProperty('--i', btns.indexOf(btn));
    state[key] = btn.dataset.v;
    if (SUBS[key]) $(`#${key === 'fanMode' ? 'fanSub' : 'lightSub'}`).textContent = SUBS[key][btn.dataset.v];
    if (key === 'fanMode') { $('#curveFold').classList.toggle('show', state.fanMode === 'curve'); setTimeout(() => setOpen(state.open), 420); }
    if (key === 'procSort') renderProcs(state.cores.reduce((a, b) => a + b) / CORES);
  });
}

buildStatic(); drawCurve(); bindCurve(); bind(); tick(); setInterval(tick, 1000);
const q = new URLSearchParams(location.search);
if (q.get('fan')) $(`.seg[data-key=fanMode] [data-v=${q.get('fan')}]`).click();
if (q.get('light')) $(`.seg[data-key=lightMode] [data-v=${q.get('light')}]`).click();
if (q.has('open')) setOpen(true);
