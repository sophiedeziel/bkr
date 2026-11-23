document.addEventListener("DOMContentLoaded", function () {
  document.querySelectorAll(".bkr-demo").forEach(function (button) {
    button.addEventListener("click", function () {
      button.textContent = "Clicked!";
    });
  });
});
