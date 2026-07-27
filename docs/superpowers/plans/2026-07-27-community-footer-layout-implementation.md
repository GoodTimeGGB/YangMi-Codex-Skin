# Community Footer Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the community footer so WeChat is primary and auxiliary links stay aligned on desktop and mobile.

**Architecture:** Keep the existing `#community` section and known external URLs. Modify only `site/index.html` card structure and `site/pink-support.css` presentation rules.

**Tech Stack:** Static HTML5, CSS3, Git, PowerShell.

---

### Task 1: Restructure Community Markup

**Files:**
- Modify: `site/index.html` community section
- Test: static structure check

- [ ] **Step 1: Verify the present cards**

Run: `rg -n 'community-links|wechat-card|wechat-copy|qr-inline|social-card' site/index.html`

Expected: the section contains a WeChat card and three social-link cards.

- [ ] **Step 2: Add a feature-card wrapper**

Replace the current `community-links` outer container with this hierarchy while retaining the three existing anchor cards and their URLs inside `community-links`:

```html
<div class="community-panel">
  <article class="social-card wechat-card">
    <div class="wechat-copy">
      <img src="assets/icon-wechat.svg" alt="微信" />
      <div>
        <p class="social-kicker">FOLLOW ON WECHAT</p>
        <strong>微信公众号</strong>
        <small>宁的AI小站 · 微信扫一扫关注</small>
      </div>
    </div>
    <div class="qr-wrap">
      <img class="qr-inline" src="assets/wechat-public-account-qr-web.png" alt="宁的AI小站微信公众号二维码" />
      <span>扫码关注</span>
    </div>
  </article>
  <div class="community-links">...</div>
</div>
```

- [ ] **Step 3: Confirm the static structure**

Run: `rg -n 'community-panel|social-kicker|qr-wrap|community-links' site/index.html`

Expected: all four classes occur once.

- [ ] **Step 4: Commit markup**

Run: `git add site/index.html; git commit -m "feat: promote WeChat community card"`

### Task 2: Implement Card Layout

**Files:**
- Modify: `site/pink-support.css` community card rules
- Test: static CSS constraints check

- [ ] **Step 1: Implement desktop layout**

Replace the current community card layout with the following rules:

```css
.community{grid-template-columns:.78fr 1.22fr;gap:56px;align-items:start}
.community-panel{display:grid;grid-template-columns:minmax(260px,.94fr) minmax(0,1.06fr);gap:14px;align-items:stretch}
.community-links{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}
.wechat-card{display:flex;min-height:244px;flex-direction:column;justify-content:space-between;align-items:stretch;gap:22px;padding:22px!important;background:#fff!important}
.social-kicker{margin:0 0 7px;color:#a55170;font-size:11px;font-weight:700;letter-spacing:.08em}
.qr-wrap{display:flex;align-items:center;gap:12px;padding-top:14px;border-top:1px solid #f0dce4}
.qr-inline{width:104px!important;height:104px!important;justify-self:auto;padding:5px;border:1px solid #e4c7d3;background:#fff;image-rendering:pixelated}
.qr-wrap span{font-size:12px;color:#684b60}
.community-links .social-card{min-height:115px;padding:17px}
```

- [ ] **Step 2: Implement mobile layout**

Inside the existing `@media(max-width:760px)` block add:

```css
.community-panel{grid-template-columns:1fr}
.wechat-card{min-height:auto}
.community-links{grid-template-columns:1fr}
.qr-wrap{justify-content:flex-start}
```

- [ ] **Step 3: Run static CSS checks**

Run: `rg -n 'community-panel|grid-template-columns:1fr|qr-inline' site/pink-support.css; git diff --check`

Expected: all required selectors appear and no whitespace errors are printed.

- [ ] **Step 4: Commit styling**

Run: `git add site/pink-support.css; git commit -m "style: rebalance community footer layout"`

### Task 3: Review and Publish

**Files:**
- Verify: `site/index.html`
- Verify: `site/pink-support.css`

- [ ] **Step 1: Verify links and remove stale QR UI**

Run: `rg -n 'my.feishu.cn/share/base/form/shrcn0kDoXdfxhI3hcE8OBdmimd|xiaohongshu.com/user/profile/5da45e7f0000000001002cc2|github.com/GoodTimeGGB/YangMi-Codex-Skin' site/index.html; rg -n 'details|qr-popover' site/index.html site/pink-support.css`

Expected: all three known URLs are found; no deprecated popover markup is found.

- [ ] **Step 2: Push the finished work**

Run: `git diff --check; git status --short; git push origin main`

Expected: no diff errors, clean status after commits, and a successful `origin/main` push.
