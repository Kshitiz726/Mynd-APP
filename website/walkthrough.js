/* ===========================================================================
   The walkthrough.
   ---------------------------------------------------------------------------
   "Walk through it" plays the product as a short film: one phone, captions
   underneath, screens changing on a timeline. Two decisions worth knowing:

   1. The scenes are not written here. Each one names a screen already on the
      page (data-wt="...") and the player clones it. So the film can never
      drift out of sync with the site - fix a screen once, it is fixed in both.

   2. There is no soundtrack. Two went in - a synthesised pad, then a licensed
      recording - and both were noise over a page nobody asked to play sound at.
      The screens carry it on their own.
   ======================================================================== */

(() => {
  const root = document.getElementById('wt');
  if (!root) return;

  const stage  = document.getElementById('wt-stage');
  const capBox = document.getElementById('wt-cap');
  const ticks  = document.getElementById('wt-ticks');
  const bPlay  = document.getElementById('wt-play');
  const bClose = document.getElementById('wt-close');

  // The script. Durations are reading times, not screen times: a caption you
  // finish before the cut feels slow, one you don't finish feels rushed.
  const SCENES = [
    ['home',     'Open it. That is the whole setup.',
                 'No inbox to sort, no project to name, no empty checklist waiting to be filled in. Home is the orb, and the orb is a microphone.', 4600],
    ['speak',    'Say it the way it is in your head',
                 'Out loud, in one breath, in the wrong order. It transcribes while you talk and never interrupts to ask what you meant.', 6800],
    ['found',    'That sentence just became three tasks',
                 'It reads what you said, pulls out the things that are actually work, and tags each one with the energy it will cost. You typed nothing.', 6600],
    ['sched',    'One tap, and they land in real hours',
                 'Auto-Schedule knows when you wake and when you sleep. The hard ones get your good hours, the easy one waits for tomorrow, and nothing lands at 2am.', 7200],
    ['backlog',  'Whatever has no time yet waits in the backlog',
                 'Filter it by what you have left in you. A brain-dead evening still has something in it you can actually do, and any gap in the day offers to be filled.', 6600],
    ['dump',     'It works typed, too',
                 'Same engine, different door. Paste the mess, hit Process, and it comes back scheduled exactly the way the voice does.', 7400],
    ['mood',     'It asks how you are, once',
                 'Drag the dial. No wrong answer, and it never argues with the one you gave it.', 4600],
    ['moodchat', 'And then it plans around that answer',
                 'Log low and Mynd stops pushing the hard thing. It opens the conversation already knowing your mood, your day and the time, so you never explain yourself twice.', 7200],
    ['setup',    'When it is time, it starts the work for you',
                 'Focus already knows what is up next, because that is the task your sentence turned into. One tap and the session is running.', 4800],
    ['presets',  'Pick a length, a scene, and whether you want company',
                 'Sprint, pomodoro, deep work, flow. Turn body doubling on and it starts looking for someone to sit with you.', 6400],
    ['together', 'Someone quietly on the other end of it',
                 'You get paired with another person working right now. Nobody speaks. That is the point.', 4600],
    ['live',     'The session holds you',
                 'A timer, one task, and a scene you can change without leaving. Forest to rain, mid-session, no menu.', 5600],
    ['rain',     'A thought arrives. Park it.',
                 'Two seconds to write it down, then straight back. It joins the pile you can go through later.', 5200],
    ['memory',   'It remembers, and you can correct it',
                 'Mynd writes up what it has learned about you after every session. Open it, edit it, and the next plan is built on your version.', 7400],
    ['rem',      'Then it sets the reminders itself',
                 'You never switch these on. Scheduling a block is what schedules its reminder, one for each, with its own tone and its own time.', 6400],
    ['notif',    'And it reaches you with the app closed',
                 'The reminder arrives knowing what the task is, what it costs you, and why you said it mattered.', 5400],
    ['coach',    'It has read all of it before you type',
                 'Every chat, every parked thought, every time you moved something. It tells you the pattern you cannot see and offers to fix your schedule for you.', 7400],
    ['done',     'And the day closes',
                 'Everything ticked, the streak alive, and nothing still circling in your head.', 4600],
    ['paywall',  'Free covers the whole loop',
                 'Talk, schedule, remind, focus, remember. Plus and Pro raise the limits when you want more room to think.', 4600],
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
