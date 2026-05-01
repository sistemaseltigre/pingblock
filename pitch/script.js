const slides = Array.from(document.querySelectorAll('.slide'));
const nextBtn = document.getElementById('next');
const prevBtn = document.getElementById('prev');
const counter = document.getElementById('counter');
const progressBar = document.getElementById('progressBar');
const tabs = document.getElementById('tabs');
let current = 0;

slides.forEach((slide, index) => {
  const tab = document.createElement('button');
  tab.type = 'button';
  tab.setAttribute('aria-label', `Ir a slide ${index + 1}: ${slide.dataset.title}`);
  tab.addEventListener('click', () => goTo(index));
  tabs.appendChild(tab);
});

const tabButtons = Array.from(tabs.children);

document.querySelectorAll('[data-next]').forEach((button) => {
  button.addEventListener('click', () => goTo(current + 1));
});

function goTo(nextIndex) {
  const bounded = Math.max(0, Math.min(slides.length - 1, nextIndex));
  if (bounded === current) return;

  slides[current].classList.remove('is-active');
  slides[current].classList.toggle('exit-left', bounded > current);
  current = bounded;
  slides[current].classList.remove('exit-left');
  slides[current].classList.add('is-active');
  updateUi();
}

function updateUi() {
  counter.textContent = `${current + 1} / ${slides.length}`;
  progressBar.style.width = `${((current + 1) / slides.length) * 100}%`;
  tabButtons.forEach((tab, index) => tab.classList.toggle('is-active', index === current));
  prevBtn.disabled = current === 0;
  nextBtn.disabled = current === slides.length - 1;
  document.title = `PingBlock Pitch | ${slides[current].dataset.title}`;
}

nextBtn.addEventListener('click', () => goTo(current + 1));
prevBtn.addEventListener('click', () => goTo(current - 1));

window.addEventListener('keydown', (event) => {
  const key = event.key;
  if (['ArrowRight', ' ', 'PageDown'].includes(key)) {
    event.preventDefault();
    goTo(current + 1);
  }
  if (['ArrowLeft', 'PageUp'].includes(key)) {
    event.preventDefault();
    goTo(current - 1);
  }
  if (key === 'Home') goTo(0);
  if (key === 'End') goTo(slides.length - 1);
});

let touchStartX = null;
window.addEventListener('touchstart', (event) => {
  touchStartX = event.touches[0].clientX;
}, { passive: true });
window.addEventListener('touchend', (event) => {
  if (touchStartX === null) return;
  const delta = event.changedTouches[0].clientX - touchStartX;
  if (Math.abs(delta) > 60) goTo(current + (delta < 0 ? 1 : -1));
  touchStartX = null;
}, { passive: true });

updateUi();
