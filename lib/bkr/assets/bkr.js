/*!
 * bkr.js - small interactive widgets for EPUB 3 books made with bkr.
 *
 * Dependency-free, no network access, plain ES5 so it runs in old reading
 * systems too. Everything is progressive enhancement: when scripting is
 * disabled (many readers do that), the markup below still reads as normal
 * content. Chapters are XHTML, so boolean-looking attributes need a value:
 * write data-bkr-hidden="" (not just data-bkr-hidden).
 *
 * ---------------------------------------------------------------------------
 * Reveal: hides part of a block behind a button.
 *
 *   <div data-bkr="reveal" data-bkr-label="Show the answer">
 *     <p>What is the capital of France?</p>
 *     <div data-bkr-hidden="">
 *       <p>Paris.</p>
 *     </div>
 *   </div>
 *
 *   data-bkr-label       optional, button text when hidden (default "Show")
 *   data-bkr-hide-label  optional, button text when shown (default "Hide")
 *   Every element with data-bkr-hidden inside the block gets its own button.
 *
 * ---------------------------------------------------------------------------
 * Quiz: a multiple choice question with instant feedback.
 *
 *   <div data-bkr="quiz">
 *     <p>Which planet is the largest?</p>
 *     <ol>
 *       <li>Mars</li>
 *       <li data-bkr-correct="">Jupiter</li>
 *       <li>Venus</li>
 *     </ol>
 *     <p data-bkr-explanation="">Jupiter is more than 11 times wider than Earth.</p>
 *   </div>
 *
 *   The first <ol> or <ul> holds the options; mark the right one(s) with
 *   data-bkr-correct. The optional data-bkr-explanation element is hidden
 *   until the reader finds the answer.
 *   data-bkr-right  optional, message for a right answer (default "Correct!")
 *   data-bkr-wrong  optional, message for a wrong answer (default "Not quite, try again.")
 *
 * ---------------------------------------------------------------------------
 * Steps: shows a list one item at a time.
 *
 *   <ol data-bkr="steps" data-bkr-label="Next step">
 *     <li>Crack the eggs.</li>
 *     <li>Whisk them.</li>
 *     <li>Cook gently.</li>
 *   </ol>
 *
 *   data-bkr-label  optional, button text (default "Next step")
 *
 * ---------------------------------------------------------------------------
 * Once the script runs, the <html> element gets the class "bkr-js" so styles
 * can target the enhanced version only.
 */
(function () {
  "use strict";

  var counter = 0;

  function each(list, callback) {
    Array.prototype.forEach.call(list, callback);
  }

  function attr(element, name, fallback) {
    var value = element.getAttribute(name);
    return value === null || value === "" ? fallback : value;
  }

  function uniqueId(element, prefix) {
    if (!element.id) {
      counter += 1;
      element.id = "bkr-" + prefix + "-" + counter;
    }
    return element.id;
  }

  function makeButton(text, className) {
    var button = document.createElement("button");
    button.setAttribute("type", "button");
    button.className = className;
    button.textContent = text;
    return button;
  }

  function setHidden(element, hidden) {
    if (hidden) {
      element.setAttribute("hidden", "hidden");
    } else {
      element.removeAttribute("hidden");
    }
  }

  function enhanced(element) {
    if (element.getAttribute("data-bkr-ready") === "true") {
      return true;
    }
    element.setAttribute("data-bkr-ready", "true");
    return false;
  }

  /* Reveal ---------------------------------------------------------------- */

  function initReveal(block) {
    if (enhanced(block)) {
      return;
    }
    var showLabel = attr(block, "data-bkr-label", "Show");
    var hideLabel = attr(block, "data-bkr-hide-label", "Hide");

    each(block.querySelectorAll("[data-bkr-hidden]"), function (panel) {
      var button = makeButton(showLabel, "bkr-reveal-button");
      button.setAttribute("aria-expanded", "false");
      button.setAttribute("aria-controls", uniqueId(panel, "reveal"));
      setHidden(panel, true);

      button.addEventListener("click", function () {
        var open = button.getAttribute("aria-expanded") !== "true";
        button.setAttribute("aria-expanded", open ? "true" : "false");
        button.textContent = open ? hideLabel : showLabel;
        setHidden(panel, !open);
      });

      panel.parentNode.insertBefore(button, panel);
    });
  }

  /* Quiz ------------------------------------------------------------------ */

  function firstList(block) {
    var lists = block.querySelectorAll("ol, ul");
    return lists.length > 0 ? lists[0] : null;
  }

  function initQuiz(block) {
    if (enhanced(block)) {
      return;
    }
    var list = firstList(block);
    if (!list) {
      return;
    }
    var rightText = attr(block, "data-bkr-right", "Correct!");
    var wrongText = attr(block, "data-bkr-wrong", "Not quite, try again.");
    var explanations = block.querySelectorAll("[data-bkr-explanation]");
    var buttons = [];

    var feedback = document.createElement("p");
    feedback.className = "bkr-quiz-feedback";
    feedback.setAttribute("aria-live", "polite");
    feedback.setAttribute("role", "status");
    list.parentNode.insertBefore(feedback, list.nextSibling);

    each(explanations, function (explanation) {
      setHidden(explanation, true);
    });

    function finish() {
      each(buttons, function (button) {
        button.disabled = true;
      });
      each(explanations, function (explanation) {
        setHidden(explanation, false);
      });
    }

    each(list.children, function (item) {
      if (item.nodeName.toLowerCase() !== "li") {
        return;
      }
      var correct = item.hasAttribute("data-bkr-correct");
      var button = makeButton("", "bkr-quiz-option");

      // Move the option's content into the button, keeping its markup.
      while (item.firstChild) {
        button.appendChild(item.firstChild);
      }
      item.appendChild(button);
      buttons.push(button);

      button.addEventListener("click", function () {
        if (correct) {
          item.className += " bkr-quiz-right";
          feedback.className = "bkr-quiz-feedback bkr-quiz-feedback-right";
          feedback.textContent = rightText;
          finish();
        } else {
          item.className += " bkr-quiz-wrong";
          feedback.className = "bkr-quiz-feedback bkr-quiz-feedback-wrong";
          feedback.textContent = wrongText;
          button.disabled = true;
        }
      });
    });

    block.className += " bkr-quiz-ready";
  }

  /* Steps ----------------------------------------------------------------- */

  function initSteps(list) {
    if (enhanced(list)) {
      return;
    }
    var items = [];
    each(list.children, function (item) {
      if (item.nodeName.toLowerCase() === "li") {
        items.push(item);
      }
    });
    if (items.length < 2) {
      return;
    }

    var shown = 1;
    var button = makeButton(attr(list, "data-bkr-label", "Next step"), "bkr-steps-button");
    button.setAttribute("aria-controls", uniqueId(list, "steps"));

    each(items, function (item, index) {
      setHidden(item, index >= shown);
    });

    button.addEventListener("click", function () {
      var next = items[shown];
      setHidden(next, false);
      next.setAttribute("tabindex", "-1");
      next.focus();
      shown += 1;
      if (shown >= items.length) {
        setHidden(button, true);
      }
    });

    list.parentNode.insertBefore(button, list.nextSibling);
  }

  /* Boot ------------------------------------------------------------------ */

  var widgets = {
    reveal: initReveal,
    quiz: initQuiz,
    steps: initSteps
  };

  function init() {
    var root = document.documentElement;
    if (root.classList) {
      root.classList.add("bkr-js");
    }
    each(document.querySelectorAll("[data-bkr]"), function (element) {
      var widget = widgets[element.getAttribute("data-bkr")];
      if (widget) {
        widget(element);
      }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
