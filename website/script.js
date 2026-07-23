/* OurMynd site - the only behaviours the page needs.
   Kept deliberately small: no framework, no build step, no dependencies, so the
   whole site is four files you can drop on any static host. */

// 1. The nav lifts off the page once you leave the hero.
const nav = document.getElementById('nav');
const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 24);
onScroll();
addEventListener('scroll', onScroll, { passive: true });

// 2. Sections rise in as they arrive, staggered so a row of cards arrives as a
//    row rather than all at once. Matches the app's springy easing.
const io = new IntersectionObserver((entries) => {
  entries.forEach((e, i) => {
    if (!e.isIntersecting) return;
    setTimeout(() => e.target.classList.add('in'), i * 90);
    io.unobserve(e.target);
  });
}, { threshold: 0.12, rootMargin: '0px 0px -60px' });

document.querySelectorAll('.rise').forEach((el) => io.observe(el));

// 3. Smooth anchor scrolling that respects a reduced-motion preference, offset
//    so the fixed nav never covers a section heading it just scrolled to.
const smooth = !matchMedia('(prefers-reduced-motion: reduce)').matches;
document.querySelectorAll('a[href^="#"]').forEach((a) => {
  a.addEventListener('click', (ev) => {
    const target = document.querySelector(a.getAttribute('href'));
    if (!target) return;
    ev.preventDefault();
    const y = target.getBoundingClientRect().top + scrollY - 88;
    scrollTo({ top: Math.max(0, y), behavior: smooth ? 'smooth' : 'auto' });
  });
});
