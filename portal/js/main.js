/**
 * iSmart Messenger - Official Branch Portal JS
 * High-performance, vanilla JavaScript for interactive portal features
 */

document.addEventListener('DOMContentLoaded', () => {
  // Mobile Navigation Toggle
  const mobileToggle = document.getElementById('mobileToggle');
  const navMenu = document.getElementById('navMenu');

  if (mobileToggle && navMenu) {
    mobileToggle.addEventListener('click', () => {
      navMenu.classList.toggle('open');
      const isOpen = navMenu.classList.contains('open');
      mobileToggle.innerHTML = isOpen ? '&#10005;' : '&#9776;';
    });
  }

  // Copy Server Address Feature
  const copyBtn = document.getElementById('copyServerBtn');
  const serverIpCode = document.getElementById('serverIpCode');

  if (copyBtn && serverIpCode) {
    copyBtn.addEventListener('click', () => {
      const textToCopy = serverIpCode.innerText.trim();
      navigator.clipboard.writeText(textToCopy).then(() => {
        showToast('تم نسخ عنوان السيرفر بنجاح!');
      }).catch(() => {
        showToast('تعذر النسخ تلقائياً، يرجى نسخه يدوياً');
      });
    });
  }

  // Video Chapter Seeking
  document.querySelectorAll('.timeline-chip').forEach(chip => {
    chip.addEventListener('click', (e) => {
      const targetTime = parseFloat(chip.getAttribute('data-time'));
      const videoId = chip.getAttribute('data-video');
      const videoElement = document.getElementById(videoId);

      if (videoElement && !isNaN(targetTime)) {
        videoElement.currentTime = targetTime;
        videoElement.play();
        videoElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
        showToast(`تم الانتقال إلى الدقيقة ${chip.innerText}`);
      }
    });
  });

  // FAQ Accordion Behavior
  document.querySelectorAll('.faq-question').forEach(question => {
    question.addEventListener('click', () => {
      const parent = question.closest('.faq-item');
      const isActive = parent.classList.contains('active');

      // Close other items
      document.querySelectorAll('.faq-item').forEach(item => {
        item.classList.remove('active');
      });

      if (!isActive) {
        parent.classList.add('active');
      }
    });
  });

  // Global Toast Function
  window.showToast = function(message) {
    let toast = document.getElementById('globalToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'globalToast';
      toast.className = 'toast-msg';
      document.body.appendChild(toast);
    }

    toast.innerHTML = `<span>✓</span> <span>${message}</span>`;
    toast.classList.add('show');

    setTimeout(() => {
      toast.classList.remove('show');
    }, 3200);
  };
});
