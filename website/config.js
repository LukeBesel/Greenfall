/* ==========================================================================
   GREENFALL WEBSITE CONFIG — the only file you need to edit to go live.
   --------------------------------------------------------------------------
   Every link, id and switch the site uses lives here. index.html,
   presskit.html and privacy.html read it on load (js/main.js).

   Rules of thumb
   * Leave a value as '' (empty) to hide that thing. Empty social links are
     not shown; an empty demo link shows "Coming soon"; an empty Steam app id
     makes the Wishlist button scroll to the newsletter instead.
   * Valve's rule: never sell for less than on Steam (price, bundles or
     launch discounts). Keep buyDirect.priceNote in line with the Steam page.
   * The Open Graph / Twitter tags in each HTML <head> cannot read this file
     (crawlers don't run JavaScript). When you have a domain, search and
     replace "https://greenfall.example" in the three HTML files.
   ========================================================================== */
window.GREENFALL_CONFIG = {
  /* Public site address, no trailing slash (used for share links). */
  siteUrl: 'https://greenfall.example',

  /* Studio / developer name shown in the footer and the press kit. */
  developer: 'Greenfall team',
  developerUrl: '',
  basedIn: 'TBA',

  /* ---- Steam ------------------------------------------------------------
     appId: the number in your store URL store.steampowered.com/app/<appId>/
     When set, the Wishlist buttons open the Steam page. */
  steam: {
    appId: '',
    // Optional: override the URL (e.g. with UTM-free short links). Leave '' to build it from appId.
    url: ''
  },

  /* ---- Trailer ----------------------------------------------------------
     Until one of these is set, the hero shows a looping screenshot slideshow.
     youtubeId: the id from youtube.com/watch?v=<id> (loaded from
       youtube-nocookie.com, and only after the visitor presses play).
     videoUrl: a direct .mp4/.webm file instead (self-hosted or Steam CDN). */
  trailer: {
    youtubeId: '',
    videoUrl: ''
  },

  /* ---- Newsletter -------------------------------------------------------
     action: the form endpoint of your provider. Examples:
       Buttondown:  https://buttondown.com/api/emails/embed-subscribe/<username>
       Mailchimp:   https://<dc>.list-manage.com/subscribe/post?u=<u>&id=<id>
       Kit (ConvertKit): https://app.kit.com/forms/<formId>/subscriptions
     emailField: the input name the provider expects:
       Buttondown 'email', Mailchimp 'EMAIL', Kit 'email_address'.
     extraFields: hidden fields some providers want, e.g. Buttondown
       { tag: 'website' } or Mailchimp { tags: '1234' }.
     While action is '', the form explains that signups open soon. */
  newsletter: {
    provider: 'buttondown',
    action: '',
    emailField: 'email',
    extraFields: {}
  },

  /* ---- Buy direct -------------------------------------------------------
     enabled: false shows a disabled "Coming soon" button.
     provider: 'lemonsqueezy' | 'paddle' | 'itch' | 'link'
       lemonsqueezy: url = your checkout link (https://<store>.lemonsqueezy.com/buy/<id>);
                     opens as an overlay via lemon.js.
       paddle:       paddleClientToken + paddlePriceId (Paddle Billing, Paddle.js v2);
                     set paddleEnvironment to 'sandbox' while testing.
       itch:         itchGameId = the number from your itch.io embed widget
                     (itch.io dashboard > Distribute > Embed game); shows the widget.
       link:         url = any checkout page.
     label / priceNote: button text and the small line under it. Keep the
     price the same as Steam. */
  buyDirect: {
    enabled: false,
    provider: 'lemonsqueezy',
    url: '',
    label: 'Buy DRM-free',
    priceNote: 'Same price as on Steam. Includes a Steam key and DRM-free builds for Windows, macOS and Linux.',
    paddleClientToken: '',
    paddlePriceId: '',
    paddleEnvironment: 'production',
    itchGameId: ''
  },

  /* ---- Demo -------------------------------------------------------------
     url: itch.io page or Steam demo link. '' shows "Demo coming soon". */
  demo: {
    url: '',
    label: 'Download the demo'
  },

  /* ---- Facts (also used by the press kit) ------------------------------- */
  releaseDate: 'TBA',
  price: 'TBA',
  platforms: 'Windows, macOS, Linux, Steam Deck',

  /* ---- Press kit downloads ---------------------------------------------- */
  press: {
    screenshotsZip: 'assets/press/greenfall-screenshots.zip',
    // Optional: a link to a folder with raw PNG/4K shots (Drive, Dropbox, ...).
    hiResFolder: ''
  },

  /* ---- Contact (use a role address, not a personal one) ----------------- */
  contactEmail: 'press@greenfall.example',

  /* ---- Socials: full URLs, '' hides the icon ----------------------------- */
  socials: {
    discord: '',
    bluesky: '',
    x: '',
    youtube: '',
    tiktok: '',
    reddit: '',
    itch: '',
    mastodon: ''
  }
};
