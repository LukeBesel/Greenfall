/* Greenfall website behaviour. Reads window.GREENFALL_CONFIG (config.js).
   No dependencies; every feature degrades to plain HTML without JS. */
(function () {
  'use strict';
  var doc = document.documentElement;
  doc.classList.add('js');
  var C = window.GREENFALL_CONFIG || {};
  var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var onIndex = !!document.getElementById('newsletter');

  function $(s, root) { return (root || document).querySelector(s); }
  function $$(s, root) { return Array.prototype.slice.call((root || document).querySelectorAll(s)); }
  function get(path) {
    return path.split('.').reduce(function (o, k) { return o == null ? undefined : o[k]; }, C);
  }
  function loadScript(src, cb) {
    var s = document.createElement('script');
    s.src = src; s.defer = true; s.onload = cb || null;
    document.head.appendChild(s);
  }
  function external(a) { a.target = '_blank'; a.rel = 'noopener'; }

  /* ---------- config bindings ---------- */
  $$('[data-cfg]').forEach(function (el) {
    var v = get(el.getAttribute('data-cfg'));
    if (v) el.textContent = v;
  });
  $$('[data-cfg-href]').forEach(function (el) {
    var v = get(el.getAttribute('data-cfg-href'));
    if (v) el.href = v; else if (el.hasAttribute('data-hide-empty')) el.hidden = true;
  });
  $$('[data-cfg-mailto]').forEach(function (el) {
    var v = get(el.getAttribute('data-cfg-mailto'));
    if (v) { el.href = 'mailto:' + v; if (el.textContent.indexOf('@') !== -1) el.textContent = v; }
  });
  $$('[data-year]').forEach(function (el) { el.textContent = new Date().getFullYear(); });

  /* ---------- Steam links ---------- */
  var steam = C.steam || {};
  var steamUrl = steam.url || (steam.appId ? 'https://store.steampowered.com/app/' + steam.appId + '/' : '');
  $$('[data-steam]').forEach(function (a) {
    if (steamUrl) { a.href = steamUrl; external(a); }
    else { a.href = onIndex ? '#newsletter' : 'index.html#newsletter'; }
  });
  $$('[data-steam-note]').forEach(function (el) { el.hidden = !!steamUrl; });

  /* ---------- Verdance meter (scroll progress) ---------- */
  var meter = $('.verdance');
  var meterLabel = $('.verdance-label b');
  if (meter) {
    var ticking = false;
    var update = function () {
      ticking = false;
      var max = Math.max(1, doc.scrollHeight - window.innerHeight);
      var p = Math.min(1, Math.max(0, window.scrollY / max));
      meter.style.setProperty('--p', p.toFixed(4));
      if (meterLabel) meterLabel.textContent = Math.round(p * 100) + '%';
    };
    window.addEventListener('scroll', function () { if (!ticking) { ticking = true; requestAnimationFrame(update); } }, { passive: true });
    update();
  }

  /* ---------- scroll reveal ---------- */
  var revealEls = $$('.reveal, .sprout-line');
  if ('IntersectionObserver' in window && !reduceMotion) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add('in'); });
  }

  /* ---------- hero slideshow / trailer ---------- */
  var trailer = $('.trailer');
  if (trailer) {
    var slides = $$('.slides li', trailer);
    var dotsBox = $('.dots', trailer);
    var toggle = $('[data-slideshow-toggle]', trailer);
    var idx = 0, timer = null, playing = !reduceMotion;
    slides.forEach(function (_, i) {
      var d = document.createElement('span');
      if (i === 0) d.className = 'on';
      dotsBox && dotsBox.appendChild(d);
    });
    var dots = dotsBox ? $$('span', dotsBox) : [];
    var show = function (n) {
      slides[idx].classList.remove('on'); dots[idx] && dots[idx].classList.remove('on');
      idx = (n + slides.length) % slides.length;
      slides[idx].classList.add('on'); dots[idx] && dots[idx].classList.add('on');
    };
    var setPlaying = function (on) {
      playing = on;
      clearInterval(timer);
      if (on) timer = setInterval(function () { show(idx + 1); }, 4800);
      if (toggle) {
        toggle.setAttribute('aria-label', on ? 'Pause slideshow' : 'Play slideshow');
        toggle.innerHTML = on
          ? '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="5" width="4" height="14"/><rect x="14" y="5" width="4" height="14"/></svg>'
          : '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 5l12 7-12 7z"/></svg>';
      }
    };
    if (slides.length > 1) {
      setPlaying(playing);
      toggle && toggle.addEventListener('click', function () { setPlaying(!playing); });
      document.addEventListener('visibilitychange', function () {
        if (document.hidden) clearInterval(timer); else if (playing) setPlaying(true);
      });
    }

    var t = C.trailer || {};
    if (t.youtubeId || t.videoUrl) {
      var label = $('[data-trailer-label]', trailer);
      if (label) label.textContent = 'Watch the trailer';
      var btn = document.createElement('button');
      btn.type = 'button'; btn.className = 'play-big';
      btn.setAttribute('aria-label', 'Play the Greenfall trailer');
      btn.innerHTML = '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6 4l15 8-15 8z"/></svg>';
      trailer.appendChild(btn);
      btn.addEventListener('click', function () {
        var el;
        if (t.youtubeId) {
          el = document.createElement('iframe');
          el.src = 'https://www.youtube-nocookie.com/embed/' + encodeURIComponent(t.youtubeId) + '?autoplay=1&rel=0&modestbranding=1';
          el.title = 'Greenfall trailer';
          el.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen';
          el.allowFullscreen = true;
        } else {
          el = document.createElement('video');
          el.src = t.videoUrl; el.controls = true; el.autoplay = true; el.playsInline = true;
        }
        setPlaying(false);
        btn.remove();
        trailer.appendChild(el);
        el.focus && el.focus();
      });
    }
  }

  /* ---------- before / after slider ---------- */
  $$('.compare').forEach(function (box) {
    var input = $('input', box);
    var set = function () { box.style.setProperty('--pos', input.value + '%'); };
    input.addEventListener('input', set); set();
  });

  /* ---------- lightbox ---------- */
  var links = $$('a[data-lightbox]');
  var lb = $('#lightbox');
  if (links.length && lb && typeof lb.showModal === 'function') {
    var img = $('img', lb), cap = $('.lb-text', lb), count = $('.count', lb);
    var cur = 0, opener = null;
    var open = function (i) {
      cur = (i + links.length) % links.length;
      var a = links[cur], thumb = $('img', a);
      img.src = a.getAttribute('href');
      img.alt = thumb ? thumb.alt : '';
      cap.textContent = thumb ? thumb.alt : '';
      count.textContent = (cur + 1) + ' / ' + links.length;
      // warm the next image
      var next = links[(cur + 1) % links.length];
      if (next) { var pre = new Image(); pre.src = next.getAttribute('href'); }
    };
    links.forEach(function (a, i) {
      a.addEventListener('click', function (e) {
        e.preventDefault();
        opener = a;
        open(i);
        lb.showModal();
      });
    });
    $('.lb-prev', lb).addEventListener('click', function () { open(cur - 1); });
    $('.lb-next', lb).addEventListener('click', function () { open(cur + 1); });
    $('.lb-close', lb).addEventListener('click', function () { lb.close(); });
    lb.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowLeft') { e.preventDefault(); open(cur - 1); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); open(cur + 1); }
    });
    lb.addEventListener('click', function (e) { if (e.target === lb || e.target.classList.contains('lb-stage')) lb.close(); });
    lb.addEventListener('close', function () { img.removeAttribute('src'); if (opener) opener.focus(); });
    var x0 = null;
    lb.addEventListener('touchstart', function (e) { x0 = e.touches[0].clientX; }, { passive: true });
    lb.addEventListener('touchend', function (e) {
      if (x0 === null) return;
      var dx = e.changedTouches[0].clientX - x0; x0 = null;
      if (Math.abs(dx) > 50) open(cur + (dx < 0 ? 1 : -1));
    });
  }

  /* ---------- newsletter ---------- */
  var form = $('#signup-form');
  if (form) {
    var n = C.newsletter || {};
    var msg = $('.form-msg', form.parentNode);
    var email = $('input[type="email"]', form);
    var say = function (text, cls) { msg.textContent = text; msg.className = 'form-msg ' + (cls || ''); };
    if (n.action) {
      form.action = n.action;
      email.name = n.emailField || 'email';
      Object.keys(n.extraFields || {}).forEach(function (k) {
        var h = document.createElement('input');
        h.type = 'hidden'; h.name = k; h.value = n.extraFields[k];
        form.appendChild(h);
      });
    }
    form.addEventListener('submit', function (e) {
      var trap = $('.hp input', form);
      if (trap && trap.value) { e.preventDefault(); form.reset(); say('Thanks! Check your inbox to confirm.', 'ok'); return; }
      if (!n.action) { e.preventDefault(); say('Signups open very soon. Please check back, or follow us on Steam.', 'warn'); return; }
      // Posts into the hidden iframe (no CORS needed); the visitor stays here.
      var btn = $('button[type="submit"]', form);
      btn.disabled = true;
      say('Sending…');
      var done = false;
      var finish = function () {
        if (done) return; done = true;
        btn.disabled = false; form.reset();
        say('Thanks! Check your inbox to confirm your subscription.', 'ok');
      };
      $('#nl-sink').addEventListener('load', finish, { once: true });
      setTimeout(finish, 2500);
    });
  }

  /* ---------- buy direct ---------- */
  var buy = $('#buy-slot');
  if (buy) {
    var b = C.buyDirect || {};
    var chip = $('#buy-status');
    var note = $('#buy-note');
    if (b.enabled) {
      chip.textContent = 'Available now'; chip.classList.add('live');
      if (b.priceNote && note) note.textContent = b.priceNote;
      var label = b.label || 'Buy direct';
      if (b.provider === 'itch' && b.itchGameId) {
        buy.innerHTML = '';
        var f = document.createElement('iframe');
        f.className = 'itch-frame'; f.title = 'Buy Greenfall on itch.io'; f.loading = 'lazy';
        f.src = 'https://itch.io/embed/' + encodeURIComponent(b.itchGameId) + '?linkback=true&bg_color=16171a&fg_color=e6e6de&link_color=9edba8&border_color=2a2b2e';
        buy.appendChild(f);
      } else if (b.provider === 'paddle' && b.paddleClientToken && b.paddlePriceId) {
        buy.innerHTML = '<button type="button" class="btn btn-green">' + label + '</button>';
        var pbtn = $('button', buy);
        pbtn.disabled = true;
        loadScript('https://cdn.paddle.com/paddle/v2/paddle.js', function () {
          if (b.paddleEnvironment === 'sandbox') window.Paddle.Environment.set('sandbox');
          window.Paddle.Initialize({ token: b.paddleClientToken });
          pbtn.disabled = false;
        });
        pbtn.addEventListener('click', function () {
          window.Paddle.Checkout.open({ items: [{ priceId: b.paddlePriceId, quantity: 1 }] });
        });
      } else if (b.url) {
        buy.innerHTML = '';
        var a = document.createElement('a');
        a.className = 'btn btn-green'; a.href = b.url; a.textContent = label;
        if (b.provider === 'lemonsqueezy') {
          a.classList.add('lemonsqueezy-button');
          loadScript('https://assets.lemonsqueezy.com/lemon.js', function () {
            if (window.createLemonSqueezy) window.createLemonSqueezy();
          });
        } else { external(a); }
        buy.appendChild(a);
      }
    }
  }

  /* ---------- demo ---------- */
  var demo = $('#demo-btn');
  if (demo) {
    var d = C.demo || {};
    if (d.url) {
      demo.href = d.url; demo.removeAttribute('aria-disabled'); demo.classList.add('btn-green');
      demo.textContent = d.label || 'Download the demo';
      external(demo);
      var dchip = $('#demo-status');
      if (dchip) { dchip.textContent = 'Free demo'; dchip.classList.add('live'); }
    } else {
      demo.addEventListener('click', function (e) { e.preventDefault(); });
    }
  }

  /* ---------- socials ---------- */
  var names = { discord: 'Discord', bluesky: 'Bluesky', x: 'X', youtube: 'YouTube', tiktok: 'TikTok', reddit: 'Reddit', itch: 'itch.io', mastodon: 'Mastodon' };
  $$('[data-socials]').forEach(function (ul) {
    var s = C.socials || {};
    Object.keys(names).forEach(function (k) {
      if (!s[k]) return;
      var li = document.createElement('li');
      var a = document.createElement('a');
      a.href = s[k]; a.textContent = names[k]; a.className = 'btn btn-small';
      if (k === 'mastodon') a.rel = 'me noopener'; else a.rel = 'noopener';
      a.target = '_blank';
      li.appendChild(a); ul.appendChild(li);
    });
    if (steamUrl) {
      var li2 = document.createElement('li');
      li2.innerHTML = '<a class="btn btn-small" target="_blank" rel="noopener">Steam</a>';
      li2.firstChild.href = steamUrl;
      ul.insertBefore(li2, ul.firstChild);
    }
  });
})();
