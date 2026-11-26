/* Kanal — front page motion. First-party, no dependencies, no network.

   It does three small things and holds no layout knowledge of its own:
     1. writes scroll progress into CSS custom properties (--p, --v, --in),
        which home.css turns into every transform on the page;
     2. tilts glass cards toward a mouse pointer;
     3. marks elements `.seen` the first time they are on screen.

   If this file never runs, or the visitor asked for reduced motion, the page
   stays in its settled, fully readable state. */
(() => {
  'use strict';

  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  const root = document.documentElement;
  root.classList.add('js');

  const stage = document.querySelector('[data-scene]');
  const views = Array.from(document.querySelectorAll('[data-v]'));
  const clamp = (n) => (n < 0 ? 0 : n > 1 ? 1 : n);

  let vh = window.innerHeight;
  let queued = false;

  function frame() {
    queued = false;

    if (stage) {
      const r = stage.getBoundingClientRect();
      const span = r.height - vh;
      const p = span > 0 ? clamp(-r.top / span) : 0;
      stage.style.setProperty('--p', p.toFixed(4));
      stage.classList.toggle('deep', p > 0.085);
    }

    for (const el of views) {
      const r = el.getBoundingClientRect();
      if (r.bottom < -300 || r.top > vh + 300) continue;
      el.style.setProperty('--v', clamp((vh - r.top) / (vh + r.height)).toFixed(4));
      el.style.setProperty('--in', clamp((vh - r.top) / (vh * 0.5)).toFixed(4));
    }
  }

  function queue() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(frame);
  }

  addEventListener('scroll', queue, { passive: true });
  addEventListener('resize', () => { vh = window.innerHeight; queue(); }, { passive: true });
  addEventListener('pageshow', queue);
  frame();

  // Pointer tilt — only where there is a pointer that hovers.
  if (matchMedia('(hover: hover) and (pointer: fine)').matches) {
    for (const card of document.querySelectorAll('.tilt')) {
      card.addEventListener('pointermove', (e) => {
        const r = card.getBoundingClientRect();
        const x = (e.clientX - r.left) / r.width;
        const y = (e.clientY - r.top) / r.height;
        card.classList.remove('settle');
        card.style.setProperty('--ry', ((x - 0.5) * 14).toFixed(2) + 'deg');
        card.style.setProperty('--rx', ((0.5 - y) * 12).toFixed(2) + 'deg');
        card.style.setProperty('--gx', (x * 100).toFixed(1) + '%');
        card.style.setProperty('--gy', (y * 100).toFixed(1) + '%');
        card.style.setProperty('--g', '1');
      });
      card.addEventListener('pointerleave', () => {
        card.classList.add('settle');
        card.style.setProperty('--ry', '0deg');
        card.style.setProperty('--rx', '0deg');
        card.style.setProperty('--g', '0');
      });
    }
  }

  // One-shot entrances (the search demonstration types itself once).
  const seen = document.querySelectorAll('[data-seen]');
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add('seen');
        io.unobserve(entry.target);
      }
    }, { threshold: 0.2 });
    seen.forEach((el) => io.observe(el));
  } else {
    seen.forEach((el) => el.classList.add('seen'));
  }
})();
