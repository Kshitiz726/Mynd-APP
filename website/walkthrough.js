/* ===========================================================================
   The walkthrough.
   ---------------------------------------------------------------------------
   "Walk through it" plays the product as a short film: one phone, captions
   underneath, screens changing on a timeline. Two decisions worth knowing:

   1. The scenes are not written here. Each one names a screen already on the
      page (data-wt="...") and the player clones it. So the film can never
      drift out of sync with the site - fix a screen once, it is fixed in both.

   2. The music is a real recording, licensed CC BY 3.0 and trimmed to a clean
      100-second loop. An earlier version synthesised a pad from oscillators;
      it was cheaper but it read as a drone, not as music. It only ever starts
      from a click, which is also what browsers require.
   ======================================================================== */

(() => {
  const root = document.getElementById('wt');
  if (!root) return;

  const stage  = document.getElementById('wt-stage');
  const capBox = document.getElementById('wt-cap');
  const ticks  = document.getElementById('wt-ticks');
  const bPlay  = document.getElementById('wt-play');
  const bSound = document.getElementById('wt-sound');
  const bClose = document.getElementById('wt-close');

  // The script. Durations are reading times, not screen times: a caption you
  // finish before the cut feels slow, one you don't finish feels rushed.
  const SCENES = [
    ['home',     'This is your whole day',        'One screen. What is done, what is next, and the orb that listens.', 4400],
    ['mood',     'It starts with how you are',    'Drag the dial. Mynd plans around your energy instead of against it.', 4400],
    ['dump',     'Empty your head',               'Type the mess exactly as it arrives. No structure, no order, no effort.', 4600],
    ['voice',    'Or just talk',                  'Hold the orb and ramble. It listens all the way through, then finds the tasks hiding in it.', 5400],
    ['sched',    'It comes back as a day',        'Each thought becomes a real task, tagged by the energy it costs and laid across the hours you actually have.', 5800],
    ['rem',      'And it taps you when it is time', 'Every block gets its own reminder, its own tone, its own switch.', 4400],
    ['setup',    'Then it starts the work for you', 'Up next is already loaded. One tap and the session is running.', 4400],
    ['presets',  'Pick a length and a place',     'Sprint, pomodoro, deep work, flow. Forest, rain, or a room with other people in it.', 4800],
    ['together', 'Or sit with someone',           'Body doubling pairs you with another person working right now. Nobody speaks. That is the point.', 4600],
    ['live',     'The session holds you',         'A timer, a scene, and nothing else on the screen to fall into.', 4200],
    ['rain',     'A thought arrives. Park it.',   'Two seconds to write it down, then straight back. It will still be there afterwards.', 4800],
    ['coach',    'Something to talk to',          'Mynd already knows your day, your energy and your history before you say a word.', 4800],
    ['memory',   'It remembers so you do not',    'Written back after every session: what you finished, what you parked, what actually mattered.', 4800],
    ['done',     'And the day closes',            'Everything ticked, the streak alive, and nothing left circling in your head.', 4600],
    ['paywall',  'Free covers the whole loop',    'Plus and Pro raise the limits when you want more room to think.', 4400],
  ];

  let built = false;
  let idx = 0;
  let timer = null;
  let startedAt = 0;
  let remaining = 0;
  let playing = false;

  /* ---- Scenes ----------------------------------------------------------- */
  function build() {
    SCENES.forEach(([key]) => {
      const src = document.querySelector(`.phone[data-wt="${key}"]`);
      if (!src) return;
      const scene = document.createElement('div');
      scene.className = 'wt-scene';
      scene.dataset.key = key;
      const clone = src.cloneNode(true);
      // Clones inherit the reveal animation's starting state from the page.
      clone.querySelectorAll('.rise').forEach((el) => el.classList.add('in'));
      scene.appendChild(clone);
      stage.appendChild(scene);
      if (window.OrbInit) clone.querySelectorAll('.orb canvas').forEach(window.OrbInit);
    });

    SCENES.forEach((_, i) => {
      const b = document.createElement('button');
      b.innerHTML = '<i></i>';
      b.setAttribute('aria-label', `Scene ${i + 1}`);
      b.addEventListener('click', () => { go(i); play(); });
      ticks.appendChild(b);
    });

    built = true;
  }

  /* The phones are a fixed 300px wide and each one is a different height, so on
     a short window the tallest would run over the captions. Scale the stage
     down to whatever actually fits, per scene. */
  const bar  = root.querySelector('.wt-bar');
  const foot = root.querySelector('.wt-foot');

  function fit() {
    const avail = innerHeight - bar.offsetHeight - foot.offsetHeight - 36;
    const wide  = innerWidth - 56;
    // Every phone gets its own factor. They are different heights, so a single
    // shared one would clip the tall screens or shrink the short ones for no
    // reason - and an off-screen phone that overflows still drags the stage's
    // centring into a start-aligned fallback, which is what cut the frame off.
    stage.querySelectorAll('.wt-scene .phone').forEach((phone) => {
      const h = phone.offsetHeight, w = phone.offsetWidth;
      if (!h || !w) return;
      const s = Math.max(0.4, Math.min(1, avail / h, wide / w));
      phone.style.transform = `scale(${s.toFixed(4)})`;
      // A transform does not change the layout box, so an unscaled 625px phone
      // still counted as overflowing a shorter stage - and an overflowing item
      // makes the browser abandon centring for start alignment, which pushed
      // the frame down until its bottom was clipped. Negative margins shrink
      // the box to what the scale actually paints, symmetrically, so it
      // centres on what you can see.
      phone.style.margin = `${(-h * (1 - s)) / 2}px ${(-w * (1 - s)) / 2}px`;
    });
  }
  // Twice: once now, once after the browser has laid the new caption out.
  const refit = () => { fit(); requestAnimationFrame(fit); };
  addEventListener('resize', refit);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(refit);

  function go(i) {
    idx = (i + SCENES.length) % SCENES.length;
    const [, title, body, dur] = SCENES[idx];

    stage.querySelectorAll('.wt-scene').forEach((s, n) => s.classList.toggle('live', n === idx));

    // Retrigger the caption animation by removing the class and reflowing.
    capBox.classList.remove('swap');
    void capBox.offsetWidth;
    capBox.querySelector('h4').textContent = title;
    capBox.querySelector('p').textContent = body;
    capBox.classList.add('swap');

    [...ticks.children].forEach((b, n) => {
      b.classList.toggle('done', n < idx);
      b.classList.remove('now');
      b.querySelector('i').style.animationDuration = '';
      if (n === idx) {
        b.querySelector('i').style.animationDuration = dur + 'ms';
        void b.offsetWidth;
        b.classList.add('now');
      }
    });

    remaining = dur;
    refit();
  }

  function schedule(ms) {
    clearTimeout(timer);
    startedAt = performance.now();
    timer = setTimeout(() => {
      if (idx === SCENES.length - 1) { pause(); return; }   // hold on the last card
      go(idx + 1);
      schedule(remaining);
    }, ms);
  }

  function play() {
    playing = true;
    root.querySelectorAll('.wt-ticks .now i').forEach((i) => (i.style.animationPlayState = 'running'));
    bPlay.querySelector('use').setAttribute('href', '#ic-pause');
    bPlay.querySelector('span').textContent = 'Pause';
    schedule(remaining);
  }

  function pause() {
    playing = false;
    clearTimeout(timer);
    remaining = Math.max(0, remaining - (performance.now() - startedAt));
    root.querySelectorAll('.wt-ticks .now i').forEach((i) => (i.style.animationPlayState = 'paused'));
    bPlay.querySelector('use').setAttribute('href', '#ic-play');
    bPlay.querySelector('span').textContent = 'Play';
  }

  /* ---- Music ------------------------------------------------------------ */
  /* A real recording, not a synth: the oscillator pad read as a drone rather
     than as music. This is a 100s excerpt of "In the Flow" by Softspace
     (Room With A View, mt012), CC BY 3.0, trimmed and faded at both ends so it
     loops without a seam. Credited in the footer, as the licence requires. */
  const LEVEL = 0.34;
  let wantSound = true;

  const track = new Audio('assets/audio/walkthrough.mp3');
  track.loop = true;
  track.preload = 'auto';
  track.volume = 0;

  let fadeTimer = null;
  function fade(to, ms) {
    clearInterval(fadeTimer);
    const from = track.volume;
    const t0 = performance.now();
    fadeTimer = setInterval(() => {
      const k = Math.min(1, (performance.now() - t0) / ms);
      track.volume = Math.max(0, Math.min(1, from + (to - from) * k));
      if (k === 1) clearInterval(fadeTimer);
    }, 40);
  }

  bSound.addEventListener('click', () => {
    wantSound = !wantSound;
    bSound.setAttribute('aria-pressed', String(wantSound));
    bSound.classList.toggle('off', !wantSound);
    bSound.querySelector('use').setAttribute('href', wantSound ? '#ic-vol' : '#ic-mute');
    bSound.querySelector('span').textContent = wantSound ? 'Sound on' : 'Sound off';
    fade(wantSound ? LEVEL : 0, 500);
  });

  /* ---- Open / close ----------------------------------------------------- */
  // data-walkthrough="" plays the whole film; data-walkthrough="focus" drops
  // you straight into that chapter, so a section can offer its own clip.
  function open(key) {
    if (!built) build();
    root.hidden = false;
    void root.offsetWidth;
    root.classList.add('on');
    document.documentElement.classList.add('wt-open');

    // Autoplay is allowed here because open() only ever runs from a click.
    track.play().catch(() => {});
    if (wantSound) fade(LEVEL, 2200);

    const at = key ? SCENES.findIndex(([k]) => k === key) : 0;
    go(at < 0 ? 0 : at);
    refit();
    play();
    bClose.focus();
  }

  function close() {
    pause();
    fade(0, 600);
    root.classList.remove('on');
    document.documentElement.classList.remove('wt-open');
    setTimeout(() => { root.hidden = true; track.pause(); track.currentTime = 0; }, 640);
  }

  document.querySelectorAll('[data-walkthrough]').forEach((el) =>
    el.addEventListener('click', (e) => { e.preventDefault(); open(el.dataset.walkthrough); })
  );

  // #walkthrough opens the film straight away, so the link can be shared.
  if (location.hash.startsWith('#walkthrough')) {
    addEventListener('load', () => open(location.hash.split('=')[1] || ''));
  }


  /* ---- The same film, playing in the hero ------------------------------- */
  /* One timeline, two surfaces: the landing page runs the sequence inline, and
     clicking it lifts the very same thing into the full-screen player at the
     scene you were on. */
  const film = document.getElementById('hero-film');
  if (film) {
    const cap   = document.getElementById('hero-cap');
    const hTick = document.getElementById('hero-ticks');
    let hIdx = 0, hTimer = null, hVisible = true;

    SCENES.forEach(([key], i) => {
      const src = document.querySelector(`.phone[data-wt="${key}"]`);
      if (!src) return;
      const sc = document.createElement('div');
      sc.className = 'hero-scene';
      const clone = src.cloneNode(true);
      sc.appendChild(clone);
      film.appendChild(sc);
      if (window.OrbInit) clone.querySelectorAll('.orb canvas').forEach(window.OrbInit);

      const b = document.createElement('button');
      b.innerHTML = '<i></i>';
      b.setAttribute('aria-label', `Step ${i + 1}`);
      b.addEventListener('click', () => hGo(i));
      hTick.appendChild(b);
    });

    function hGo(i) {
      hIdx = (i + SCENES.length) % SCENES.length;
      const [, title, body, dur] = SCENES[hIdx];

      [...film.children].forEach((sc, n) => sc.classList.toggle('live', n === hIdx));

      cap.classList.remove('swap');
      void cap.offsetWidth;
      cap.querySelector('.n').textContent = hIdx + 1;
      cap.querySelector('.of').textContent = `of ${SCENES.length}`;
      cap.querySelector('h2').textContent = title;
      cap.querySelector('p').textContent = body;
      cap.classList.add('swap');

      [...hTick.children].forEach((b, n) => {
        b.classList.toggle('done', n < hIdx);
        b.classList.remove('now');
        const i2 = b.querySelector('i');
        i2.style.animationDuration = '';
        if (n === hIdx) {
          i2.style.animationDuration = dur + 'ms';
          void b.offsetWidth;
          b.classList.add('now');
        }
      });

      clearTimeout(hTimer);
      // Loops, unlike the full-screen film: a hero that stops on a still frame
      // looks broken to anyone who arrives late.
      hTimer = setTimeout(() => { if (hVisible) hGo(hIdx + 1); }, dur);
    }

    // Only runs while it is on screen. Fifteen live orbs scrolling past is a
    // waste of a laptop battery.
    new IntersectionObserver(([e]) => {
      hVisible = e.isIntersecting;
      if (hVisible) hGo(hIdx); else clearTimeout(hTimer);
    }, { threshold: 0.15 }).observe(film);

    film.addEventListener('click', () => open(SCENES[hIdx][0]));
    hGo(0);
  }

  bPlay.addEventListener('click', () => (playing ? pause() : play()));
  bClose.addEventListener('click', close);

  addEventListener('keydown', (e) => {
    if (root.hidden) return;
    if (e.key === 'Escape') close();
    if (e.key === ' ') { e.preventDefault(); playing ? pause() : play(); }
    if (e.key === 'ArrowRight') { go(idx + 1); play(); }
    if (e.key === 'ArrowLeft') { go(idx - 1); play(); }
  });
})();
