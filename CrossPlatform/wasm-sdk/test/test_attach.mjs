#!/usr/bin/env node
/*
 * VieLotusIM (Sen Việt) — DOM Adapter (attach) & OS-IME Auto-Yield Test Suite
 * Exercises <input>, <textarea>, contenteditable, input type guardrails,
 * Ctrl+Space toggle, selection replacement, and 4-layer OS-IME auto-yield.
 */

import assert from "node:assert/strict";
import { attach, isEligibleElement } from "../dist/vielotus.mjs";

// Minimal localStorage mock
function createMockStorage() {
  const map = new Map();
  return {
    getItem: (k) => (map.has(k) ? map.get(k) : null),
    setItem: (k, v) => map.set(k, String(v)),
    removeItem: (k) => map.delete(k),
    clear: () => map.clear(),
  };
}

class MockInputElement {
  constructor(tagName = "INPUT", type = "text") {
    this.tagName = tagName.toUpperCase();
    this.type = type;
    this.value = "";
    this.selectionStart = 0;
    this.selectionEnd = 0;
    this.listeners = new Map();
    this.inputEvents = 0;
  }

  addEventListener(type, fn) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type).add(fn);
  }

  removeEventListener(type, fn) {
    this.listeners.get(type)?.delete(fn);
  }

  listenerCount() {
    let n = 0;
    for (const set of this.listeners.values()) n += set.size;
    return n;
  }

  dispatchEvent(evt) {
    if (evt.type === "input") this.inputEvents++;
    const set = this.listeners.get(evt.type);
    if (set) {
      for (const fn of [...set]) fn(evt);
    }
    return !evt.defaultPrevented;
  }

  setRangeText(replacement, start, end, selectMode = "end") {
    this.value = this.value.slice(0, start) + replacement + this.value.slice(end);
    const nextPos = start + replacement.length;
    if (selectMode === "end") {
      this.selectionStart = nextPos;
      this.selectionEnd = nextPos;
    }
  }

  setSelectionRange(start, end) {
    this.selectionStart = start;
    this.selectionEnd = end;
  }
}

function makeKeyEvent(key, extra = {}) {
  return {
    type: "keydown",
    key,
    code: extra.code ?? (key === " " ? "Space" : key),
    ctrlKey: Boolean(extra.ctrlKey),
    metaKey: Boolean(extra.metaKey),
    altKey: Boolean(extra.altKey),
    shiftKey: Boolean(extra.shiftKey),
    isComposing: Boolean(extra.isComposing),
    keyCode: extra.keyCode ?? 0,
    defaultPrevented: false,
    preventDefault() {
      this.defaultPrevented = true;
    },
  };
}

function simulateTyping(el, sequence) {
  for (const ch of sequence) {
    if (ch === "<") {
      const evt = makeKeyEvent("Backspace");
      el.dispatchEvent(evt);
      if (!evt.defaultPrevented) {
        if (el.selectionStart !== el.selectionEnd) {
          el.setRangeText("", el.selectionStart, el.selectionEnd, "end");
        } else if (el.selectionStart > 0) {
          el.setRangeText("", el.selectionStart - 1, el.selectionStart, "end");
        }
      }
    } else {
      const evt = makeKeyEvent(ch);
      el.dispatchEvent(evt);
      if (!evt.defaultPrevented) {
        el.setRangeText(ch, el.selectionStart, el.selectionEnd, "end");
        el.dispatchEvent({ type: "input", inputType: "insertText", data: ch });
      }
    }
  }
}

// Mock contenteditable with Text node & Selection/Range
function createMockContentEditable() {
  const textNode = {
    nodeType: 3,
    data: "",
    deleteData(offset, count) {
      this.data = this.data.slice(0, offset) + this.data.slice(offset + count);
    },
    insertData(offset, str) {
      this.data = this.data.slice(0, offset) + str + this.data.slice(offset);
    },
  };

  let activeRange = {
    startContainer: textNode,
    startOffset: 0,
    collapsed: true,
    deleteContents() {
      this.collapsed = true;
    },
    setStart(node, offset) {
      this.startContainer = node;
      this.startOffset = offset;
    },
    collapse(flag) {
      this.collapsed = Boolean(flag);
    },
  };

  const selection = {
    rangeCount: 1,
    getRangeAt: () => activeRange,
    removeAllRanges: () => {},
    addRange: (r) => {
      activeRange = r;
    },
  };

  const el = {
    tagName: "DIV",
    isContentEditable: true,
    listeners: new Map(),
    ownerDocument: {
      defaultView: { getSelection: () => selection },
      createTextNode: (t) => ({ ...textNode, data: t }),
    },
    addEventListener(type, fn) {
      if (!this.listeners.has(type)) this.listeners.set(type, new Set());
      this.listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      this.listeners.get(type)?.delete(fn);
    },
    dispatchEvent(evt) {
      const set = this.listeners.get(evt.type);
      if (set) {
        for (const fn of [...set]) fn(evt);
      }
      return !evt.defaultPrevented;
    },
  };

  const typeCE = (seq) => {
    for (const ch of seq) {
      const evt = makeKeyEvent(ch);
      el.dispatchEvent(evt);
      if (!evt.defaultPrevented) {
        textNode.insertData(activeRange.startOffset, ch);
        activeRange.startOffset += ch.length;
      }
    }
  };

  return { el, textNode, typeCE };
}

// Install clean mock storage
globalThis.localStorage = createMockStorage();

// 1. Element eligibility guardrails
{
  assert.equal(isEligibleElement(new MockInputElement("INPUT", "text")), true);
  assert.equal(isEligibleElement(new MockInputElement("INPUT", "search")), true);
  assert.equal(isEligibleElement(new MockInputElement("TEXTAREA")), true);
  assert.equal(isEligibleElement(new MockInputElement("INPUT", "password")), false);
  assert.equal(isEligibleElement(new MockInputElement("INPUT", "email")), false);
  assert.equal(isEligibleElement(new MockInputElement("INPUT", "number")), false);
  assert.equal(isEligibleElement(new MockInputElement("INPUT", "tel")), false);
  assert.equal(isEligibleElement(new MockInputElement("INPUT", "url")), false);

  const pwd = new MockInputElement("INPUT", "password");
  const ctrl = await attach(pwd);
  assert.equal(ctrl.isBlocked, true);
  assert.equal(ctrl.isEnabled(), false);
  assert.equal(pwd.listenerCount(), 0);
  simulateTyping(pwd, "Vieejt");
  assert.equal(pwd.value, "Vieejt", "Password field must never be transformed");
  ctrl.destroy();
  console.log("[PASS] Guardrails: password/email/number/tel/url blocked, text/search/textarea eligible");
}

// 2. <input type="text"> Telex + Bilingual + Parity + Destroy cleanup
{
  const input = new MockInputElement("INPUT", "text");
  const ctrl = await attach(input, { persistForeignIme: false });
  assert.equal(ctrl.isBlocked, false);
  assert.equal(ctrl.isEnabled(), true);

  simulateTyping(input, "Vieejt Nam — DDawsk Lawsk, Kroong Pawcs, chi as, same as, towio, dongdof, github ");
  assert.equal(input.value, "Việt Nam — Đắk Lắk, Krông Pắc, chi á, same as, tôi, đồng, github ");
  assert.ok(input.inputEvents > 0, "Should emit DOM input events for framework reactivity");

  // Enter commits override cleanly
  input.value = "";
  input.setSelectionRange(0, 0);
  ctrl.resetContext();
  simulateTyping(input, "same as");
  const enterEvt = makeKeyEvent("Enter");
  input.dispatchEvent(enterEvt);
  assert.equal(enterEvt.defaultPrevented, false, "Enter default submission must not be blocked");
  assert.equal(input.value, "same as");

  // Destroy removes all listeners and frees WASM session slot
  const activeBefore = ctrl.engine.activeSessions;
  assert.equal(activeBefore, 1);
  ctrl.destroy();
  assert.equal(input.listenerCount(), 0, "destroy() must remove all DOM event listeners");
  console.log("[PASS] <input type=text>: Telex, Smart Bilingual, Enter commit, listener & session cleanup OK");
}

// 3. <textarea> VNI + Backspace + Selection replacement + Arrow reset
{
  const ta = new MockInputElement("TEXTAREA");
  const ctrl = await attach(ta, { inputMethod: "vni", persistForeignIme: false });

  simulateTyping(ta, "Tie61ng Vie65t ");
  assert.equal(ta.value, "Tiếng Việt ");

  // Switch live to Telex and verify Backspace recovery
  ctrl.setOptions({ inputMethod: "telex" });
  ta.value = "";
  ta.setSelectionRange(0, 0);
  ctrl.resetContext();
  simulateTyping(ta, "hoa downw< ");
  assert.equal(ta.value, "hoa dơn ");

  // ArrowLeft resets composition
  ta.value = "";
  ta.setSelectionRange(0, 0);
  ctrl.resetContext();
  simulateTyping(ta, "a");
  ta.dispatchEvent(makeKeyEvent("ArrowLeft"));
  assert.equal(ctrl.engine.isComposing, false);
  simulateTyping(ta, "a");
  assert.equal(ta.value, "aa", "After ArrowLeft reset, second 'a' must not combine into 'â'");

  // Replacing selected text with Vietnamese word ('ddi ' -> 'đi ', partial selection 'Vieejt ' -> 'hello Việt ')
  ta.value = "hello";
  ta.setSelectionRange(0, 5);
  simulateTyping(ta, "ddi ");
  assert.equal(ta.value, "đi ");

  ta.value = "hello world";
  ta.setSelectionRange(6, 11);
  simulateTyping(ta, "Vieejt ");
  assert.equal(ta.value, "hello Việt ");

  ctrl.destroy();
  console.log("[PASS] <textarea>: VNI, Backspace recovery, Arrow reset, selection replacement OK");
}

// 4. contenteditable editing
{
  const { el, textNode, typeCE } = createMockContentEditable();
  const ctrl = await attach(el, { persistForeignIme: false });
  typeCE("Sen Vieejt treen WebAssembly ");
  assert.equal(textNode.data, "Sen Việt trên WebAssembly ");
  ctrl.destroy();
  console.log("[PASS] contenteditable: Text node range replacement OK");
}

// 5. Ctrl+Space toggle
{
  const input = new MockInputElement("INPUT", "text");
  const ctrl = await attach(input, { persistForeignIme: false });

  simulateTyping(input, "vieejt ");
  assert.equal(input.value, "việt ");

  // Press Ctrl+Space -> disable
  const toggleOff = makeKeyEvent(" ", { ctrlKey: true, code: "Space" });
  input.dispatchEvent(toggleOff);
  assert.equal(toggleOff.defaultPrevented, true);
  assert.equal(ctrl.isEnabled(), false);

  simulateTyping(input, "vieejt ");
  assert.equal(input.value, "việt vieejt ");

  // Press Ctrl+Space -> re-enable
  const toggleOn = makeKeyEvent(" ", { ctrlKey: true, code: "Space" });
  input.dispatchEvent(toggleOn);
  assert.equal(ctrl.isEnabled(), true);

  simulateTyping(input, "nam ");
  assert.equal(input.value, "việt vieejt nam ");
  ctrl.destroy();
  console.log("[PASS] Ctrl+Space toggle: disables & re-enables cleanly OK");
}

// 6. 4-layer OS-IME Auto-Yield + Paste immunity + Persistence + Recovery
{
  globalThis.localStorage.clear();
  const reasons = [];

  // 6a. Pasting Vietnamese must NOT trigger yield
  const input1 = new MockInputElement("INPUT", "text");
  const ctrl1 = await attach(input1, {
    yieldToSystemIme: true,
    persistForeignIme: true,
    onForeignIme: ({ reason }) => reasons.push(reason),
  });
  input1.dispatchEvent({ type: "input", inputType: "insertFromPaste", data: "Tiếng Việt" });
  assert.equal(ctrl1.isEnabled(), true, "Pasting Vietnamese must not falsely trigger OS-IME yield");
  assert.equal(ctrl1.isYielded(), false);

  // 6b. compositionstart triggers yield + persists to localStorage
  input1.dispatchEvent({ type: "compositionstart" });
  assert.equal(ctrl1.isEnabled(), false);
  assert.equal(ctrl1.isYielded(), true);
  assert.equal(reasons.at(-1), "compositionstart");
  assert.equal(globalThis.localStorage.getItem("vielotus.foreignIme"), "1");
  ctrl1.destroy();

  // 6c. New attach() respects persisted foreignIme flag, then Ctrl+Space clears it
  const input2 = new MockInputElement("INPUT", "text");
  const ctrl2 = await attach(input2, {
    yieldToSystemIme: true,
    persistForeignIme: true,
    onForeignIme: ({ reason }) => reasons.push(reason),
  });
  assert.equal(ctrl2.isEnabled(), false);
  assert.equal(ctrl2.isYielded(), true);
  assert.equal(reasons.at(-1), "persisted");

  input2.dispatchEvent(makeKeyEvent(" ", { ctrlKey: true, code: "Space" }));
  assert.equal(ctrl2.isEnabled(), true);
  assert.equal(ctrl2.isYielded(), false);
  assert.equal(globalThis.localStorage.getItem("vielotus.foreignIme"), null);

  // 6d. keyCode 229 / isComposing triggers yield
  input2.dispatchEvent(makeKeyEvent("Process", { keyCode: 229, isComposing: true }));
  assert.equal(ctrl2.isYielded(), true);
  assert.equal(reasons.at(-1), "key-composing");

  // 6e. Precomposed Vietnamese keydown triggers yield (macOS/Windows CGEvent IMEs)
  ctrl2.setEnabled(true);
  input2.dispatchEvent(makeKeyEvent("ắ"));
  assert.equal(ctrl2.isYielded(), true);
  assert.equal(reasons.at(-1), "key-diacritic");

  // 6f. Unmarked foreign input event with Vietnamese char triggers yield
  ctrl2.setEnabled(true);
  input2.dispatchEvent({ type: "input", inputType: "insertText", data: "ệ" });
  assert.equal(ctrl2.isYielded(), true);
  assert.equal(reasons.at(-1), "input-diacritic");

  ctrl2.destroy();
  console.log("[PASS] OS-IME Auto-Yield: paste-safe, 4-layer detection, localStorage persistence, Ctrl+Space recovery OK");
}

console.log("ALL DOM ADAPTER TESTS PASSED.");
