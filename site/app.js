(() => {
  const storageKey = "yangmi-site-theme";
  const toggle = document.querySelector("[data-theme-toggle]");

  const applyTheme = (theme) => {
    document.body.dataset.theme = theme;
    if (toggle) {
      const isNight = theme === "night";
      const isEnglish = document.documentElement.lang === "en";
      toggle.textContent = isNight ? (isEnglish ? "Light" : "明") : (isEnglish ? "Dark" : "夜");
      toggle.title = isNight ? (isEnglish ? "Switch to light skin" : "切换浅色皮肤") : (isEnglish ? "Switch to night skin" : "切换夜间皮肤");
    }
  };

  applyTheme(localStorage.getItem(storageKey) || "light");

  toggle?.addEventListener("click", () => {
    const nextTheme = document.body.dataset.theme === "night" ? "light" : "night";
    localStorage.setItem(storageKey, nextTheme);
    applyTheme(nextTheme);
  });
})();
