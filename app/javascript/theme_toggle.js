const STORAGE_KEY = "cards.theme";
const UI_THEME_KEY = "cards.uiTheme";
const SIDEBAR_KEY = "cards.sidebar";

function safeGetItem(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function safeSetItem(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // ignore
  }
}

function safeRemoveItem(key) {
  try {
    localStorage.removeItem(key);
  } catch {
    // ignore
  }
}

function osPrefersDark() {
  return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
}

function getEffectiveTheme() {
  const explicit = document.documentElement.dataset.theme;
  if (explicit === "light" || explicit === "dark") return explicit;
  return osPrefersDark() ? "dark" : "light";
}

function setTheme(theme) {
  if (theme === "light" || theme === "dark") {
    document.documentElement.dataset.theme = theme;
    safeSetItem(STORAGE_KEY, theme);
  } else {
    delete document.documentElement.dataset.theme;
    safeRemoveItem(STORAGE_KEY);
  }
}

function applySavedThemeEarly() {
  const saved = safeGetItem(STORAGE_KEY);
  if (saved === "light" || saved === "dark") {
    document.documentElement.dataset.theme = saved;
  }
}

function applySavedUiThemeEarly() {
  const saved = safeGetItem(UI_THEME_KEY);
  if (saved === "retro") {
    document.documentElement.dataset.uiTheme = "retro";
  } else {
    document.documentElement.dataset.uiTheme = "modern";
  }
}

function setUiTheme(theme) {
  if (theme === "retro") {
    document.documentElement.dataset.uiTheme = "retro";
    safeSetItem(UI_THEME_KEY, "retro");
  } else {
    document.documentElement.dataset.uiTheme = "modern";
    safeSetItem(UI_THEME_KEY, "modern");
  }
}

function bindUiThemeSelector() {
  const select = document.getElementById("ui-theme");
  if (!select) return;

  const current = document.documentElement.dataset.uiTheme || "modern";
  select.value = current === "retro" ? "retro" : "modern";

  if (select.dataset.bound === "true") return;
  select.dataset.bound = "true";

  select.addEventListener("change", () => {
    setUiTheme(select.value);
  });
}

function applySavedSidebarEarly() {
  const saved = safeGetItem(SIDEBAR_KEY);
  if (saved === "closed") {
    document.documentElement.dataset.sidebar = "closed";
  } else {
    document.documentElement.dataset.sidebar = "open";
  }
}

function setSidebar(state) {
  if (state === "closed") {
    document.documentElement.dataset.sidebar = "closed";
    safeSetItem(SIDEBAR_KEY, "closed");
  } else {
    document.documentElement.dataset.sidebar = "open";
    safeSetItem(SIDEBAR_KEY, "open");
  }
}

function bindSidebarToggle() {
  const closeButton = document.getElementById("sidebar-toggle");
  const openButton = document.getElementById("sidebar-toggle-open");

  if (closeButton && closeButton.dataset.bound !== "true") {
    closeButton.dataset.bound = "true";
    closeButton.addEventListener("click", () => setSidebar("closed"));
  }

  if (openButton && openButton.dataset.bound !== "true") {
    openButton.dataset.bound = "true";
    openButton.addEventListener("click", () => setSidebar("open"));
  }
}

function updateButton(button) {
  const theme = getEffectiveTheme();
  button.textContent = theme === "dark" ? "Light mode" : "Dark mode";
  button.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
}

function bind() {
  const button = document.getElementById("theme-toggle");
  bindSidebarToggle();

  if (!button) {
    bindUiThemeSelector();
    return;
  }

  updateButton(button);

  if (button.dataset.bound === "true") return;
  button.dataset.bound = "true";

  button.addEventListener("click", () => {
    const theme = getEffectiveTheme();
    setTheme(theme === "dark" ? "light" : "dark");
    updateButton(button);
  });

  bindUiThemeSelector();
  bindSidebarToggle();
}

applySavedThemeEarly();
applySavedUiThemeEarly();
applySavedSidebarEarly();
document.addEventListener("turbo:load", bind);
document.addEventListener("DOMContentLoaded", bind);

