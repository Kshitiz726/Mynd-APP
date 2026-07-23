/* ===========================================================================
   The walkthrough.
   ---------------------------------------------------------------------------
   "Walk through it" plays the product as a short film: one phone, captions
   underneath, screens changing on a timeline. Two decisions worth knowing:

   1. The scenes are not written here. Each one names a screen already on the
      page (data-wt="...") and the player clones it. So the film can never
      drift out of sync with the site - fix a screen once, it is fixed in both.

   2. The music is synthesised, not a file. A slow four-chord pad built from
      oscillators costs nothing to download, loops forever without a seam, and
      keeps the site to files you can drop on any static host. It only ever
      starts from a click, which is also what browsers require.
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
    chord(idx);          // the pad moves with the cut
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
  /* Four voices over a lowpass: root, fifth, and two detuned upper tones that
     beat slowly against each other. Quiet enough to sit under speech, which is
     what a walkthrough soundtrack is for. */
  let ac = null, master = null, voices = [], wantSound = true;
  const CHORDS = [
    [146.83, 220.00, 293.66, 369.99],  // D minor-ish
    [130.81, 196.00, 261.63, 329.63],  // C
    [174.61, 261.63, 349.23, 440.00],  // F
    [110.00, 164.81, 220.00, 277.18],  // A minor
  ];

  function audio() {
    if (ac) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    ac = new AC();

    const filter = ac.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 900;

    master = ac.createGain();
    master.gain.value = 0;
    filter.connect(master).connect(ac.destination);

    voices = [0, 1, 2, 3].map((n) => {
      const osc = ac.createOscillator();
      osc.type = n < 2 ? 'sine' : 'triangle';
      osc.detune.value = n === 3 ? 6 : n === 2 ? -5 : 0;   // slow beating
      const g = ac.createGain();
      g.gain.value = n < 2 ? 0.30 : 0.16;
      osc.connect(g).connect(filter);
      osc.start();
      return osc;
    });

    // A breath on the whole pad so it never sits perfectly still.
    const lfo = ac.createOscillator();
    const lfoGain = ac.createGain();
    lfo.frequency.value = 0.07;
    lfoGain.gain.value = 0.018;
    lfo.connect(lfoGain).connect(master.gain);
    lfo.start();
  }

  function chord(i) {
    if (!ac || !voices.length) return;
    const notes = CHORDS[i % CHORDS.length];
    voices.forEach((osc, n) => {
      // Glide rather than jump: a stepped frequency clicks.
      osc.frequency.cancelScheduledValues(ac.currentTime);
      osc.frequency.setTargetAtTime(notes[n], ac.currentTime, 0.9);
    });
  }

  function fade(to, secs) {
    if (!ac || !master) return;
    master.gain.cancelScheduledValues(ac.currentTime);
    master.gain.setValueAtTime(master.gain.value, ac.currentTime);
    master.gain.linearRampToValueAtTime(to, ac.currentTime + secs);
  }

  const LEVEL = 0.055;

  bSound.addEventListener('click', () => {
    wantSound = !wantSound;
    bSound.setAttribute('aria-pressed', String(wantSound));
    bSound.classList.toggle('off', !wantSound);
    bSound.querySelector('use').setAttribute('href', wantSound ? '#ic-vol' : '#ic-mute');
    bSound.querySelector('span').textContent = wantSound ? 'Sound on' : 'Sound off';
    fade(wantSound ? LEVEL : 0, 0.5);
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

    audio();
    if (ac && ac.state === 'suspended') ac.resume();
    if (wantSound) fade(LEVEL, 2.2);

    const at = key ? SCENES.findIndex(([k]) => k === key) : 0;
    go(at < 0 ? 0 : at);
    play();
    bClose.focus();
  }

  function close() {
    pause();
    fade(0, 0.6);
    root.classList.remove('on');
    document.documentElement.classList.remove('wt-open');
    setTimeout(() => { root.hidden = true; if (ac) ac.suspend(); }, 480);
  }

  document.querySelectorAll('[data-walkthrough]').forEach((el) =>
    el.addEventListener('click', (e) => { e.preventDefault(); open(el.dataset.walkthrough); })
  );

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
