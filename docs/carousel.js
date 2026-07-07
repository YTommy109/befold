(function () {
  'use strict';

  function initCarousel(root) {
    var track = root.querySelector('.carousel-track');
    var slides = Array.prototype.slice.call(root.querySelectorAll('.carousel-slide'));
    var dotsContainer = root.querySelector('.carousel-dots');
    var prevButton = root.querySelector('.carousel-prev');
    var nextButton = root.querySelector('.carousel-next');
    var currentIndex = 0;
    var autoplayTimer = null;
    var autoplayIntervalMs = 4000;
    var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    var dots = slides.map(function (_, index) {
      var dot = document.createElement('button');
      dot.className = 'carousel-dot';
      dot.type = 'button';
      dot.setAttribute('aria-label', 'Slide ' + (index + 1));
      dot.addEventListener('click', function () {
        goToSlide(index);
      });
      dotsContainer.appendChild(dot);
      return dot;
    });

    function render() {
      track.style.transform = 'translateX(-' + (currentIndex * 100) + '%)';
      dots.forEach(function (dot, index) {
        dot.classList.toggle('active', index === currentIndex);
      });
    }

    function goToSlide(index) {
      currentIndex = (index + slides.length) % slides.length;
      render();
    }

    function nextSlide() {
      goToSlide(currentIndex + 1);
    }

    function prevSlide() {
      goToSlide(currentIndex - 1);
    }

    function startAutoplay() {
      if (prefersReducedMotion) return;
      stopAutoplay();
      autoplayTimer = window.setInterval(nextSlide, autoplayIntervalMs);
    }

    function stopAutoplay() {
      if (autoplayTimer !== null) {
        window.clearInterval(autoplayTimer);
        autoplayTimer = null;
      }
    }

    if (prevButton) prevButton.addEventListener('click', prevSlide);
    if (nextButton) nextButton.addEventListener('click', nextSlide);
    root.addEventListener('mouseenter', stopAutoplay);
    root.addEventListener('mouseleave', startAutoplay);

    render();
    startAutoplay();
  }

  document.addEventListener('DOMContentLoaded', function () {
    var root = document.querySelector('.carousel');
    if (root) initCarousel(root);
  });
})();
