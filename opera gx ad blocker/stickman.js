// Your desktop stick figure (DesktopStickman/stickman.ps1), redrawn for the browser as the
// pop-up fighter. Shared by content.js (on web pages) and the sidebar panel.
//
// Poses use the desktop script's design units: a 44 x 68 box, body centre line x = 22,
// feet on y = 62, a 13-unit head, 3-unit ink lines inside a 6.5-unit white halo.
// walk, idle, leap, fall, cheer and wave are ported straight from Draw-Figure; run, punch,
// kick, flykick and stomp are new, built the same way.
globalThis.Stickman = (() => {
  const INK = 'rgb(24, 24, 28)';
  const HALO = '#fff';
  const ACCENT = '#fa1e4e';
  const WORDS = ['POW!', 'BAM!', 'WHAM!', 'SMASH!', 'KO!'];

  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const rand = (lo, hi) => lo + Math.random() * (hi - lo);

  // Line segments [ax, ay, bx, by] and head centre for a pose. ph is the animation clock,
  // d the facing (1 right, -1 left), k the 0..1 progress through a one-shot move.
  function pose(name, ph, d, k) {
    const sin = Math.sin(ph);
    let headX = 22;
    let headY = 14;
    let lift = 0;
    let segs;
    switch (name) {
      case 'fall':
        headY = 15;
        segs = [[22, 22, 22, 40], [22, 26, 11, 15], [22, 26, 33, 17], [22, 40, 13, 60], [22, 40, 30, 62]];
        break;
      case 'idle': {
        const bob = sin * 1.2;
        headY = 14 + bob;
        segs = [[22, 21 + bob, 22, 40 + bob], [22, 26 + bob, 16, 38 + bob], [22, 26 + bob, 28, 38 + bob],
          [22, 40 + bob, 17, 62], [22, 40 + bob, 27, 62]];
        break;
      }
      case 'leap':
        headY = 16;
        segs = [[22, 23, 22, 41], [22, 26, 22 - d * 6, 9], [22, 26, 22 + d * 9, 11],
          [22, 41, 22 - d * 7, 56], [22 - d * 7, 56, 22 - d * 12, 62], [22, 41, 22 - d * 2, 60]];
        break;
      case 'cheer': {
        const sw = Math.sin(ph * 1.4);
        lift = -Math.abs(sw) * 9;
        segs = [[22, 21, 22, 40], [22, 26, 12, 13 - sw * 3], [22, 26, 32, 13 + sw * 3],
          [22, 40, 22 - 5 - sw * 3, 62], [22, 40, 22 + 5 + sw * 3, 62]];
        break;
      }
      case 'wave':
        headX = 22 + d * 1.5;
        segs = [[22, 21, 22, 40], [22, 26, 22 - d * 7, 38], [22, 26, 22 + d * 10, 15 + sin * 5],
          [22, 40, 17, 62], [22, 40, 27, 62]];
        break;
      case 'stomp': {
        // hop up, slam down on the target, squat into the landing (his button stamp, harder)
        const hop = k < 0.5 ? Math.sin((k / 0.5) * Math.PI) : 0;
        const c = k < 0.5 ? hop * 0.3 : Math.sin(((k - 0.5) / 0.5) * Math.PI);
        lift = -14 * hop;
        headY = 14 + 11 * c;
        segs = [[22, 21 + 11 * c, 22, 40 + 6 * c],
          [22, 26 + 10 * c, 22 - d * 8, 30 + 14 * c - hop * 14], [22, 26 + 10 * c, 22 + d * 8, 30 + 14 * c - hop * 14],
          [22, 40 + 6 * c, 22 - 6 - 5 * c, 52 + 2 * c], [22 - 6 - 5 * c, 52 + 2 * c, 22 - 6, 62],
          [22, 40 + 6 * c, 22 + 6 + 5 * c, 52 + 2 * c], [22 + 6 + 5 * c, 52 + 2 * c, 22 + 6, 62]];
        break;
      }
      case 'punch': {
        const r = Math.sin(k * Math.PI);
        const lean = d * 3 * r;
        headX = 22 + lean;
        headY = 14 + r;
        segs = [[22 + lean * 0.7, 21 + r, 22, 40],
          [22 + lean * 0.5, 26, 22 + d * (3 + 6 * r), 30 - 4 * r], [22 + d * (3 + 6 * r), 30 - 4 * r, 22 + d * (6 + 12 * r), 25 - r],
          [22 + lean * 0.5, 26, 22 + d * 3, 34], [22 + d * 3, 34, 22 + d * 7, 28],
          [22, 40, 22 - d * 8, 62], [22, 40, 22 + d * 7, 62]];
        break;
      }
      case 'kick': {
        const r = Math.sin(k * Math.PI);
        const lean = -d * 4 * r;
        headX = 22 + lean;
        headY = 14 + r * 2;
        segs = [[22 + lean, 21 + r * 2, 22, 40],
          [22 + lean * 0.6, 26 + r, 22 - d * (7 + 3 * r), 32 - 6 * r], [22 + lean * 0.6, 26 + r, 22 + d * (6 - 2 * r), 36 - 6 * r],
          [22, 40, 22 - d * 3, 62],
          [22, 40, 22 + d * (5 + 9 * r), 50 - 12 * r], [22 + d * (5 + 9 * r), 50 - 12 * r, 22 + d * (6 + 20 * r), 62 - 26 * r]];
        break;
      }
      case 'flykick':
        headX = 22 - d * 3;
        headY = 16;
        segs = [[22 - d * 2, 22, 22, 40],
          [22 - d, 26, 22 - d * 11, 20], [22 - d, 26, 22 + d * 5, 31],
          [22, 40, 22 + d * 21, 43],
          [22, 40, 22 - d * 4, 50], [22 - d * 4, 50, 22 - d * 11, 46]];
        break;
      default: { // walk, run
        const run = name === 'run';
        const lean = d * (run ? 4 : 2);
        const swing = sin * (run ? 9 : 7);
        const armY = 37 - Math.abs(sin) * 2;
        headX = 22 + lean * 0.9;
        if (run) lift = -Math.abs(Math.cos(ph)) * 2;
        segs = [[22 + lean * 0.7, 21, 22, 40], [22 + lean * 0.4, 26, 22 - swing, armY], [22 + lean * 0.4, 26, 22 + swing, armY],
          [22, 40, 22 + swing, 62], [22, 40, 22 - swing, 62]];
      }
    }
    return { segs, headX, headY, lift };
  }

  // Draw him with his feet at (x, y) in canvas pixels.
  function draw(ctx, { x, y, scale = 1, name = 'idle', phase = 0, dir = 1, k = 0, ink = INK, alpha = 1 }) {
    const p = pose(name, phase, dir, k);
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.translate(x - 22 * scale, y + (p.lift - 62) * scale);
    ctx.scale(scale, scale);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    const body = (color, width) => {
      ctx.strokeStyle = color;
      ctx.lineWidth = width;
      ctx.beginPath();
      for (const [ax, ay, bx, by] of p.segs) {
        ctx.moveTo(ax, ay);
        ctx.lineTo(bx, by);
      }
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(p.headX, p.headY, 6.5, 0, Math.PI * 2);
      ctx.stroke();
    };
    body(HALO, 6.5);
    ctx.fillStyle = '#fff';
    ctx.fill();
    body(ink, 3);
    ctx.restore();
  }

  // A pretend pop-up window drawn on the canvas, for things that were blocked before they
  // ever showed up (pop-up tabs, alert boxes...), so he has something to smash.
  function ghost({ x, y, w, h, title, body }) {
    const born = performance.now();
    let shake = 0;
    let gone = false;
    return {
      rect: () => (gone ? null : { left: x, top: y, right: x + w, bottom: y + h }),
      hit() {
        shake = 0.2;
      },
      destroy() {
        gone = true;
      },
      draw(ctx, now, dt) {
        shake = Math.max(0, shake - dt);
        const t = Math.min(1, (now - born) / 220);
        const pop = 1 + 2.7 * (t - 1) ** 3 + 1.7 * (t - 1) ** 2; // ease-out-back: pops in with a little overshoot
        const sx = shake ? Math.sin(now / 16) * 5 * (shake / 0.2) : 0;
        const tb = Math.max(12, Math.round(h * 0.2));
        const radius = Math.max(3, h * 0.07);
        ctx.save();
        ctx.translate(x + w / 2 + sx, y + h / 2);
        ctx.scale(pop, pop);
        ctx.translate(-w / 2, -h / 2);
        ctx.fillStyle = 'rgba(0, 0, 0, .28)';
        ctx.beginPath();
        ctx.roundRect(3, 4, w, h, radius);
        ctx.fill();
        ctx.beginPath();
        ctx.roundRect(0, 0, w, h, radius);
        ctx.fillStyle = '#fff';
        ctx.fill();
        ctx.save();
        ctx.clip();
        ctx.fillStyle = ACCENT;
        ctx.fillRect(0, 0, w, tb);
        ctx.fillStyle = '#e4e1ea';
        ctx.fillRect(w * 0.18, tb + (h - tb) * 0.68, w * 0.64, Math.max(2, h * 0.05));
        ctx.fillRect(w * 0.3, tb + (h - tb) * 0.82, w * 0.4, Math.max(2, h * 0.05));
        ctx.restore();
        ctx.strokeStyle = INK;
        ctx.lineWidth = 1.5;
        ctx.stroke();
        ctx.fillStyle = '#fff';
        ctx.font = `600 ${Math.round(tb * 0.62)}px "Segoe UI", system-ui, sans-serif`;
        ctx.textBaseline = 'middle';
        ctx.textAlign = 'left';
        ctx.fillText(fit(ctx, title, w - tb * 1.8), tb * 0.4, tb / 2 + 0.5);
        ctx.textAlign = 'center';
        ctx.fillText('×', w - tb * 0.6, tb / 2);
        ctx.fillStyle = INK;
        ctx.font = `800 ${Math.round((h - tb) * 0.26)}px "Segoe UI", system-ui, sans-serif`;
        ctx.fillText(fit(ctx, body, w * 0.9), w / 2, tb + (h - tb) * 0.38);
        ctx.restore();
      },
    };
  }

  function fit(ctx, text, max) {
    if (ctx.measureText(text).width <= max) return text;
    let s = text;
    while (s.length > 1 && ctx.measureText(s + '…').width > max) s = s.slice(0, -1);
    return s + '…';
  }

  // --- the fighter ---
  //
  // Targets are { rect(), hit(), destroy(), abandon?(), draw?(ctx, now, dt) }. rect() gives
  // viewport/canvas coordinates, or null once the target is gone or out of sight.
  //
  // How he takes each one on depends on where it sits:
  //   within reach from the ground -> runs up to its side: punch, punch, kick
  //   room to stand on its top     -> leaps onto it and stomps it three times
  //   otherwise (e.g. top banner)  -> flying kick into its side
  const STOMP = 0.34;
  const COMBO = [['punch', 0.22], ['punch', 0.22], ['kick', 0.34]];

  class Fighter {
    constructor(canvas, { scale = 1.3, stay = false, floor = 3, onGone = null } = {}) {
      this.canvas = canvas;
      this.ctx = canvas.getContext('2d');
      this.s = scale;
      this.stay = stay; // lives here (the panel) instead of running off when done
      this.floor = floor;
      this.onGone = onGone;
      this.enabled = true;
      this.targets = [];
      this.target = null;
      this.effects = [];
      this.state = stay ? 'idle' : 'offscreen';
      this.x = 40;
      this.y = 0;
      this.vx = 0;
      this.vy = 0;
      this.dir = 1;
      this.phase = 0;
      this.t = 0;
      this.wait = 2;
      this.raf = 0;
      this.w = 0;
      this.h = 0;
    }

    get ground() {
      return this.h - this.floor;
    }

    get busy() {
      return this.state !== 'offscreen' || this.targets.length > 0;
    }

    setEnabled(enabled) {
      this.enabled = enabled;
      if (!enabled) {
        for (const t of this.targets) t.abandon?.();
        this.targets = [];
        if (this.target) this.lose();
      }
    }

    add(target, { priority = false } = {}) {
      if (!this.enabled) {
        target.abandon?.();
        return;
      }
      target.priority = priority;
      this.targets.push(target);
      this.start();
      if (this.state === 'offscreen') this.enter(target.rect());
    }

    // Come in from the side nearest to what he's after and have a look around.
    enter(r) {
      this.fit();
      const fromLeft = !r || (r.left + r.right) / 2 < this.w / 2;
      this.x = fromLeft ? -30 * this.s : this.w + 30 * this.s;
      this.y = this.ground;
      this.dir = fromLeft ? 1 : -1;
      this.go('idle');
    }

    // Walk on, find nothing, wave, walk off.
    visit() {
      this.start();
      if (this.state === 'offscreen') this.enter(null);
      this.goal = clamp(this.w * rand(0.3, 0.7), 20, this.w - 20);
      this.go('stroll');
    }

    start() {
      if (this.raf) return;
      let last = performance.now();
      const tick = now => {
        const dt = Math.min(0.05, (now - last) / 1000);
        last = now;
        this.fit();
        this.step(dt);
        this.render(now, dt);
        if (!this.stay && this.state === 'offscreen' && !this.targets.length && !this.effects.length) {
          this.raf = 0;
          this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
          this.onGone?.();
          return;
        }
        this.raf = requestAnimationFrame(tick);
      };
      this.raf = requestAnimationFrame(tick);
    }

    fit() {
      const dpr = globalThis.devicePixelRatio || 1;
      const w = this.canvas.clientWidth;
      const h = this.canvas.clientHeight;
      if (this.canvas.width !== Math.round(w * dpr) || this.canvas.height !== Math.round(h * dpr)) {
        this.canvas.width = Math.round(w * dpr);
        this.canvas.height = Math.round(h * dpr);
      }
      this.w = w;
      this.h = h;
      this.dpr = dpr;
      if (['idle', 'stroll', 'wave', 'cheer', 'run', 'combo', 'leave'].includes(this.state)) this.y = this.ground; // viewport resized
    }

    go(state) {
      this.state = state;
      this.t = 0;
    }

    // --- choosing and planning ---

    engage() {
      while (this.targets.length) {
        const cx = t => {
          const r = t.rect();
          return r ? Math.abs((r.left + r.right) / 2 - this.x) : Infinity;
        };
        this.targets.sort((a, b) => (b.priority - a.priority) || cx(a) - cx(b));
        const next = this.targets.shift();
        const r = next.rect();
        if (!r) {
          next.abandon?.();
          continue;
        }
        this.target = next;
        this.plan(r);
        return true;
      }
      return false;
    }

    plan(r) {
      const s = this.s;
      const cx = (r.left + r.right) / 2;
      this.side = this.x <= cx ? -1 : 1; // which side of the target he attacks from
      if (r.bottom >= this.ground - 50 * s && r.top <= this.ground) this.mode = 'combo';
      else if (r.top > 58 * s + 6 && r.right - r.left >= 24 * s) this.mode = 'stomp';
      else this.mode = 'flykick';
      this.go('run');
    }

    goalFor(r) {
      const s = this.s;
      const edge = x => clamp(x, 14 * s, this.w - 14 * s);
      switch (this.mode) {
        case 'combo':
          return { x: edge(this.side < 0 ? r.left - 15 * s : r.right + 15 * s), y: this.ground };
        case 'stomp':
          return { x: clamp(this.x, r.left + 12 * s, r.right - 12 * s), y: r.top };
        default:
          return {
            x: edge(this.side < 0 ? r.left - 22 * s : r.right + 22 * s),
            y: clamp((r.top + r.bottom) / 2 + 24 * s, 64 * s, this.ground),
          };
      }
    }

    // The target vanished or scrolled away mid-fight.
    lose() {
      this.target?.abandon?.();
      this.target = null;
      if (this.y < this.ground - 1) {
        this.vx = 0;
        this.vy = 0;
        this.go('fall');
      } else {
        this.go('idle');
      }
    }

    strike(final, x, y) {
      const t = this.target;
      if (!t) return;
      const r = t.rect();
      this.spark(x, y);
      if (!final) {
        t.hit();
        return;
      }
      t.destroy();
      this.target = null;
      this.effects.push({ type: 'word', text: WORDS[Math.floor(Math.random() * WORDS.length)], x, y: y - 10 * this.s, age: 0, life: 0.75 });
      if (r) this.shatter(r);
    }

    // --- moving ---

    step(dt) {
      const s = this.s;
      this.t += dt;
      if (!this.enabled && this.stay) {
        this.state = 'idle';
        this.phase += dt * 2;
        return;
      }
      const r = this.target ? this.target.rect() : null;
      if (this.target && !r) this.lose();

      switch (this.state) {
        case 'offscreen': // add() and visit() bring him back
          break;

        case 'idle':
          this.phase += dt * 3;
          if (this.engage()) break;
          if (this.stay) {
            if (this.t > this.wait) {
              this.goal = clamp(this.x + rand(-1, 1) * this.w * 0.4, 20 * s, this.w - 20 * s);
              this.go('stroll');
            }
          } else if (this.t > 1.4) {
            this.goal = this.x < this.w / 2 ? -40 * s : this.w + 40 * s;
            this.go('leave');
          }
          break;

        case 'stroll': // pottering about, like on the desktop
        case 'leave': {
          if (this.engage()) break;
          const fast = this.state === 'leave';
          const dx = this.goal - this.x;
          const stepX = (fast ? 300 : 60) * s * dt;
          this.dir = Math.sign(dx) || this.dir;
          this.phase += dt * (fast ? 16 : 7);
          if (Math.abs(dx) <= stepX) {
            this.x = this.goal;
            if (fast) this.go('offscreen');
            else if (!this.stay && this.t > 0) this.go('wave');
            else {
              this.wait = rand(2, 5);
              this.go(Math.random() < 0.3 ? 'wave' : 'idle');
            }
          } else {
            this.x += Math.sign(dx) * stepX;
          }
          break;
        }

        case 'run': {
          if (!r) break;
          const goal = this.goalFor(r);
          const dx = goal.x - this.x;
          const stepX = 330 * s * dt;
          this.dir = Math.sign(dx) || this.dir;
          this.phase += dt * 16;
          if (this.mode !== 'combo' && Math.abs(dx) <= 200 * s) {
            this.leap = { x0: this.x, y0: this.y, x1: goal.x, u: 0 };
            const dist = Math.hypot(goal.x - this.x, goal.y - this.y);
            this.leap.dur = clamp(dist / 850, 0.3, 0.7);
            this.leap.arc = 30 * s + Math.max(0, this.y - goal.y) * 0.15;
            this.go('leap');
          } else if (Math.abs(dx) <= stepX) {
            this.x = goal.x;
            this.dir = -this.side;
            this.combo = 0;
            this.struck = false;
            this.go('combo');
          } else {
            this.x += Math.sign(dx) * stepX;
          }
          break;
        }

        case 'leap': {
          if (!r) break;
          const L = this.leap;
          const goal = this.goalFor(r);
          L.u = Math.min(1, L.u + dt / L.dur);
          const u = L.u;
          this.x = L.x0 + (L.x1 - L.x0) * u;
          this.y = L.y0 + (goal.y - L.y0) * u - 4 * L.arc * u * (1 - u);
          this.dir = this.mode === 'flykick' ? -this.side : (Math.sign(L.x1 - L.x0) || this.dir);
          if (u >= 1) {
            if (this.mode === 'stomp') {
              this.hits = 0;
              this.go('stomp');
            } else {
              this.strike(true, this.x + this.dir * 22 * s, this.y - 20 * s);
              this.vx = -this.dir * 150 * s;
              this.vy = -260 * s;
              this.go('fall');
            }
          }
          break;
        }

        case 'stomp': {
          if (!r) break;
          this.y = r.top;
          this.x = clamp(this.x, r.left + 6 * s, r.right - 6 * s);
          if (this.t >= (this.hits + 0.5) * STOMP) {
            this.hits++;
            const final = this.hits === 3;
            this.strike(final, this.x, this.y);
            if (final) {
              this.vx = 0;
              this.vy = -160 * s;
              this.go('fall');
            }
          }
          break;
        }

        case 'combo': { // keeps going after the last hit so the kick finishes
          const [, dur] = COMBO[this.combo];
          if (this.t >= dur / 2 && !this.struck) {
            this.struck = true;
            const final = this.combo === COMBO.length - 1;
            const kick = COMBO[this.combo][0] === 'kick';
            this.strike(final, this.x + this.dir * (kick ? 26 : 20) * s, this.y - (kick ? 26 : 38) * s);
          }
          if (this.t >= dur) {
            this.struck = false;
            this.combo++;
            if (!this.target || this.combo >= COMBO.length) this.go('cheer');
            else this.t = 0;
          }
          break;
        }

        case 'fall':
          this.vy += 2400 * s * dt;
          this.y += this.vy * dt;
          this.x = clamp(this.x + this.vx * dt, 12 * s, this.w - 12 * s);
          if (this.y >= this.ground) {
            this.y = this.ground;
            this.vx = 0;
            this.go('cheer');
          }
          break;

        case 'cheer': // shorter when there is more to smash
          this.phase += dt * 9;
          if (this.t > (this.targets.length ? 0.45 : 0.9)) {
            this.wait = rand(1.5, 4);
            this.go('idle');
          }
          break;

        case 'wave':
          this.phase += dt * 10;
          if (this.engage()) break;
          if (this.t > 1.3) {
            this.wait = rand(2, 5);
            this.go('idle');
          }
          break;
      }
    }

    // --- effects ---

    spark(x, y) {
      this.effects.push({ type: 'spark', x, y, age: 0, life: 0.28, turn: Math.random() });
    }

    shatter(r) {
      const colors = [INK, ACCENT, '#ffffff', '#b9b4c6'];
      const n = 16;
      for (let i = 0; i < n; i++) {
        this.effects.push({
          type: 'shard',
          x: rand(r.left, r.right),
          y: rand(Math.max(r.top, 0), Math.min(r.bottom, this.h)),
          vx: rand(-260, 260) * this.s,
          vy: rand(-420, -80) * this.s,
          rot: rand(0, Math.PI),
          vr: rand(-12, 12),
          len: rand(5, 13) * this.s,
          color: colors[i % colors.length],
          age: 0,
          life: rand(0.5, 0.8),
        });
      }
    }

    renderEffects(ctx, dt) {
      const s = this.s;
      this.effects = this.effects.filter(e => (e.age += dt) < e.life);
      for (const e of this.effects) {
        const t = e.age / e.life;
        ctx.save();
        ctx.globalAlpha = 1 - t;
        if (e.type === 'spark') {
          ctx.strokeStyle = ACCENT;
          ctx.lineWidth = 2.5 * s;
          ctx.lineCap = 'round';
          ctx.beginPath();
          for (let i = 0; i < 7; i++) {
            const a = (i / 7 + e.turn) * Math.PI * 2;
            const r0 = (4 + 10 * t) * s;
            const r1 = (9 + 16 * t) * s;
            ctx.moveTo(e.x + Math.cos(a) * r0, e.y + Math.sin(a) * r0);
            ctx.lineTo(e.x + Math.cos(a) * r1, e.y + Math.sin(a) * r1);
          }
          ctx.stroke();
        } else if (e.type === 'shard') {
          e.vy += 1300 * s * dt;
          e.x += e.vx * dt;
          e.y += e.vy * dt;
          e.rot += e.vr * dt;
          ctx.translate(e.x, e.y);
          ctx.rotate(e.rot);
          ctx.strokeStyle = e.color === '#ffffff' ? INK : HALO;
          ctx.lineWidth = 4 * s;
          ctx.lineCap = 'round';
          ctx.beginPath();
          ctx.moveTo(-e.len / 2, 0);
          ctx.lineTo(e.len / 2, 0);
          ctx.stroke();
          ctx.strokeStyle = e.color;
          ctx.lineWidth = 2 * s;
          ctx.stroke();
        } else if (e.type === 'word') {
          const pop = t < 0.2 ? 0.6 + 2.5 * t : 1.1 - 0.1 * t;
          ctx.translate(e.x, e.y - 18 * s * t);
          ctx.scale(pop, pop);
          ctx.font = `900 ${Math.round(20 * s)}px "Segoe UI", system-ui, sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.lineJoin = 'round';
          ctx.lineWidth = 5 * s;
          ctx.strokeStyle = INK;
          ctx.strokeText(e.text, 0, 0);
          ctx.fillStyle = '#ffd23f';
          ctx.fillText(e.text, 0, 0);
        }
        ctx.restore();
      }
    }

    render(now, dt) {
      const ctx = this.ctx;
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      ctx.clearRect(0, 0, this.w, this.h);
      for (const t of [this.target, ...this.targets]) t?.draw?.(ctx, now, dt);
      if (this.state !== 'offscreen') {
        const name = {
          run: 'run', leave: 'run', stroll: 'walk', fall: 'fall', cheer: 'cheer', wave: 'wave', stomp: 'stomp',
          leap: this.mode === 'flykick' && this.leap?.u > 0.5 ? 'flykick' : 'leap',
          combo: COMBO[Math.min(this.combo ?? 0, COMBO.length - 1)][0],
        }[this.state] || 'idle';
        const k = this.state === 'stomp' ? (this.t % STOMP) / STOMP
          : this.state === 'combo' ? Math.min(1, this.t / COMBO[Math.min(this.combo, COMBO.length - 1)][1]) : 0;
        draw(ctx, { x: this.x, y: this.y, scale: this.s, name, phase: this.phase, dir: this.dir, k, alpha: this.enabled ? 1 : 0.45 });
      }
      this.renderEffects(ctx, dt);
    }
  }

  return { draw, ghost, Fighter };
})();
