/**
 * iSmart Messenger - Official Branch Portal JS (Apple Minimalist Standard)
 * Ultra-fast vanilla JavaScript for navigation, chapter seek, and toast notifications
 */

document.addEventListener('DOMContentLoaded', () => {
  // Mobile Navigation Toggle
  const mobileToggle = document.getElementById('mobileToggle');
  const navLinks = document.getElementById('navLinks') || document.getElementById('navMenu');

  if (mobileToggle && navLinks) {
    mobileToggle.addEventListener('click', () => {
      navLinks.classList.toggle('open');
      const isOpen = navLinks.classList.contains('open');
      mobileToggle.innerHTML = isOpen ? '&#10005;' : '&#9776;';
    });
  }

  // Copy Server IP Address Feature
  const copyButtons = [
    document.getElementById('btnCopyIp'),
    document.getElementById('btnCopyIp2'),
    document.getElementById('copyServerBtn')
  ].filter(Boolean);

  copyButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const ipBox = document.getElementById('serverIpBox') || document.getElementById('serverIpCode');
      const textToCopy = ipBox ? ipBox.innerText.trim() : 'http://192.168.1.100:7070';
      
      if (navigator.clipboard) {
        navigator.clipboard.writeText(textToCopy).then(() => {
          showAppleToast('تم نسخ عنوان السيرفر بنجاح!');
        }).catch(() => {
          fallbackCopy(textToCopy);
        });
      } else {
        fallbackCopy(textToCopy);
      }
    });
  });

  function fallbackCopy(text) {
    const input = document.createElement('input');
    input.value = text;
    document.body.appendChild(input);
    input.select();
    document.execCommand('copy');
    document.body.removeChild(input);
    showAppleToast('تم نسخ عنوان السيرفر بنجاح!');
  }

  // Video Chapter Seeking (Pills)
  const chapterButtons = document.querySelectorAll('.chapter-btn, .timeline-chip');
  chapterButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetTime = parseFloat(btn.getAttribute('data-time'));
      const videoId = btn.getAttribute('data-video');
      const video = document.getElementById(videoId);

      if (video && !isNaN(targetTime)) {
        video.currentTime = targetTime;
        video.play();
        video.scrollIntoView({ behavior: 'smooth', block: 'center' });
        showAppleToast(`تم الانتقال إلى الدقيقة ${btn.innerText.trim()}`);
      }
    });
  });

  // FAQ Accordion Behavior
  const faqQuestions = document.querySelectorAll('.faq-q, .faq-question');
  faqQuestions.forEach(q => {
    q.addEventListener('click', () => {
      const parentRow = q.closest('.faq-row, .faq-item');
      if (!parentRow) return;

      const isActive = parentRow.classList.contains('active');

      // Close all others
      document.querySelectorAll('.faq-row, .faq-item').forEach(row => {
        row.classList.remove('active');
      });

      if (!isActive) {
        parentRow.classList.add('active');
      }
    });
  });

  // Toast Function
  window.showAppleToast = function(message) {
    let toast = document.getElementById('appleToast') || document.getElementById('globalToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'appleToast';
      toast.className = 'apple-toast';
      document.body.appendChild(toast);
    }

    toast.innerText = message;
    toast.classList.add('show');

    setTimeout(() => {
      toast.classList.remove('show');
    }, 2800);
  };
});
