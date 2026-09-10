(() => {
  document.documentElement.classList.add("js-ready");

  const year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const anims = document.querySelectorAll(".anim");

  if (reduced || !("IntersectionObserver" in window)) {
    anims.forEach((el) => el.classList.add("is-in"));
  } else {
    document.querySelectorAll(".hero .anim").forEach((el, i) => {
      window.setTimeout(() => el.classList.add("is-in"), 60 + i * 80);
    });

    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-in");
            io.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -6% 0px", threshold: 0.1 }
    );

    document.querySelectorAll("section .anim").forEach((el) => io.observe(el));
    window.setTimeout(() => anims.forEach((el) => el.classList.add("is-in")), 2200);
  }

  document.querySelectorAll('a[href^="#"]').forEach((a) => {
    a.addEventListener("click", (e) => {
      const id = a.getAttribute("href");
      const target = id && document.querySelector(id);
      if (!target) return;
      e.preventDefault();
      target.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "start" });
    });
  });

  // ——— Space grid inside the glow circle ———
  const canvas = document.getElementById("space-grid");
  const orbit = document.getElementById("orbit");
  if (!canvas || !orbit || reduced) return;

  const ctx = canvas.getContext("2d", { alpha: true });
  if (!ctx) return;

  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  let size = 0;
  let points = [];
  let mouse = { x: 0.5, y: 0.5, tx: 0.5, ty: 0.5, active: false };

  const COLS = 16;
  const ROWS = 16;
  const WARP = 22;

  function resize() {
    const rect = orbit.getBoundingClientRect();
    size = Math.max(1, Math.floor(Math.min(rect.width, rect.height)));
    canvas.width = Math.floor(size * dpr);
    canvas.height = Math.floor(size * dpr);
    canvas.style.width = `${size}px`;
    canvas.style.height = `${size}px`;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    points = [];
    for (let row = 0; row <= ROWS; row++) {
      for (let col = 0; col <= COLS; col++) {
        points.push({
          x: (col / COLS) * size,
          y: (row / ROWS) * size,
        });
      }
    }
  }

  function warped(p, mx, my, influence) {
    const dx = p.x - mx;
    const dy = p.y - my;
    const dist = Math.sqrt(dx * dx + dy * dy) || 1;
    const t = Math.max(0, 1 - dist / influence);
    const strength = t * t * (3 - 2 * t);
    const push = WARP * strength;
    return {
      x: p.x + (dx / dist) * push,
      y: p.y + (dy / dist) * push,
      heat: strength,
    };
  }

  function edgeFade(dist, radius) {
    // Full opacity until ~55%, then smooth fade to 0 at the rim
    const start = radius * 0.52;
    const end = radius * 0.96;
    if (dist <= start) return 1;
    if (dist >= end) return 0;
    const t = (dist - start) / (end - start);
    return 1 - t * t * (3 - 2 * t);
  }

  function draw() {
    mouse.x += (mouse.tx - mouse.x) * 0.14;
    mouse.y += (mouse.ty - mouse.y) * 0.14;

    const cx = size * 0.5;
    const cy = size * 0.5;
    const radius = size * 0.5;
    const mx = mouse.x * size;
    const my = mouse.y * size;
    const influence = size * 0.42;

    ctx.clearRect(0, 0, size, size);
    ctx.save();

    // Soft fill wash (already fades)
    const wash = ctx.createRadialGradient(cx, cy, radius * 0.12, cx, cy, radius * 0.92);
    wash.addColorStop(0, "rgba(41, 151, 255, 0.08)");
    wash.addColorStop(0.45, "rgba(41, 151, 255, 0.035)");
    wash.addColorStop(1, "rgba(41, 151, 255, 0)");
    ctx.fillStyle = wash;
    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fill();

    if (mouse.active) {
      const g = ctx.createRadialGradient(mx, my, 0, mx, my, influence);
      g.addColorStop(0, "rgba(0, 113, 227, 0.14)");
      g.addColorStop(0.5, "rgba(0, 113, 227, 0.04)");
      g.addColorStop(1, "rgba(0, 113, 227, 0)");
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(cx, cy, radius * 0.95, 0, Math.PI * 2);
      ctx.fill();
    }

    const warpedPts = points.map((p) => warped(p, mx, my, influence));
    const stride = COLS + 1;

    ctx.lineWidth = 1;
    ctx.lineCap = "round";

    function strokeSeg(a, b) {
      const midX = (a.x + b.x) * 0.5;
      const midY = (a.y + b.y) * 0.5;
      const dist = Math.hypot(midX - cx, midY - cy);
      const fade = edgeFade(dist, radius);
      if (fade < 0.02) return;

      const heat = (a.heat + b.heat) * 0.5;
      const base = mouse.active
        ? 0.1 + heat * 0.48
        : 0.09 + heat * 0.18;
      ctx.beginPath();
      ctx.strokeStyle = mouse.active
        ? `rgba(0, 113, 227, ${base * fade})`
        : `rgba(29, 29, 31, ${base * fade})`;
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.stroke();
    }

    for (let row = 0; row <= ROWS; row++) {
      for (let col = 0; col < COLS; col++) {
        strokeSeg(warpedPts[row * stride + col], warpedPts[row * stride + col + 1]);
      }
    }

    for (let col = 0; col <= COLS; col++) {
      for (let row = 0; row < ROWS; row++) {
        strokeSeg(warpedPts[row * stride + col], warpedPts[(row + 1) * stride + col]);
      }
    }

    for (const p of warpedPts) {
      if (p.heat < 0.12) continue;
      const dist = Math.hypot(p.x - cx, p.y - cy);
      const fade = edgeFade(dist, radius);
      if (fade < 0.05) continue;
      ctx.beginPath();
      ctx.fillStyle = `rgba(0, 113, 227, ${(0.2 + p.heat * 0.55) * fade})`;
      ctx.arc(p.x, p.y, 1 + p.heat * 2, 0, Math.PI * 2);
      ctx.fill();
    }

    // Final soft mask so nothing hard-clips at the rim
    ctx.globalCompositeOperation = "destination-in";
    const mask = ctx.createRadialGradient(cx, cy, radius * 0.4, cx, cy, radius);
    mask.addColorStop(0, "rgba(0,0,0,1)");
    mask.addColorStop(0.62, "rgba(0,0,0,0.85)");
    mask.addColorStop(0.82, "rgba(0,0,0,0.35)");
    mask.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = mask;
    ctx.fillRect(0, 0, size, size);
    ctx.globalCompositeOperation = "source-over";

    ctx.restore();
    requestAnimationFrame(draw);
  }

  function onMove(e) {
    const rect = orbit.getBoundingClientRect();
    mouse.tx = (e.clientX - rect.left) / rect.width;
    mouse.ty = (e.clientY - rect.top) / rect.height;
    mouse.active = true;
  }

  function onLeave() {
    mouse.active = false;
    mouse.tx = 0.5;
    mouse.ty = 0.5;
  }

  resize();
  draw();

  window.addEventListener("resize", resize);
  orbit.addEventListener("pointermove", onMove, { passive: true });
  orbit.addEventListener("pointerleave", onLeave);
})();
