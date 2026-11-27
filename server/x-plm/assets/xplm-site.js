/* Enhancements only: every form and link continues to work without this file. */
(() => {
  'use strict';
  // Keep validation/captcha/restore feedback on screen after server round-trips.
  const message = document.querySelector('.xp-signup .err, .xp-signup .ok, .xp-signup #resend-mail, .xp-promo .err, .xp-promo .ok');
  if (message) message.scrollIntoView({ block: 'center', behavior: 'instant' });

  // The backend's existing referral and gift dialogs keep their IDs and requests.
  // Add keyboard containment and return focus to the control that opened them.
  for (const name of ['ref', 'gift']) {
    const modal = document.getElementById(`${name}-modal`);
    const opener = document.getElementById(`open-${name}`);
    if (!modal || !opener) continue;
    const sheet = modal.querySelector('.sheet');
    const focusable = () => [...sheet.querySelectorAll('a[href], button, input, select, textarea, [tabindex="0"]')]
      .filter(el => !el.disabled && !el.closest('[hidden]') && el.getClientRects().length);
    modal.addEventListener('keydown', event => {
      if (event.key !== 'Tab' || modal.hidden) return;
      const items = focusable();
      if (!items.length) return;
      const first = items[0], last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    });
    new MutationObserver(() => {
      if (!modal.hidden) {
        modal.dataset.returnFocus = 'true';
        document.body.style.overflow = 'hidden';
      } else if (modal.dataset.returnFocus === 'true') {
        delete modal.dataset.returnFocus;
        document.body.style.overflow = '';
        // The referral signup shortcut deliberately transfers focus to email.
        if (!document.activeElement?.matches('#contact')) opener.focus();
      }
    }).observe(modal, { attributes: true, attributeFilter: ['hidden'] });
  }
})();
