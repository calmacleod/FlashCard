function bind() {
  const slider = document.getElementById("detail-slider");
  const label = document.getElementById("detail-label");
  const hidden = document.getElementById("detail-level-hidden");

  if (!slider || !label || !hidden) return;
  if (slider.dataset.bound === "true") return;
  slider.dataset.bound = "true";

  const levels = {
    "1": "low",
    "2": "medium",
    "3": "high"
  };

  const toSliderValue = (level) => {
    if (level === "low") return "1";
    if (level === "high") return "3";
    return "2";
  };

  const update = () => {
    const level = levels[slider.value] || "medium";
    hidden.value = level;
    label.textContent = level.toUpperCase();
  };

  // Initialize slider from hidden field (server default)
  slider.value = toSliderValue(hidden.value);
  update();

  slider.addEventListener("input", update);
  slider.addEventListener("change", update);
}

document.addEventListener("turbo:load", bind);
document.addEventListener("DOMContentLoaded", bind);

