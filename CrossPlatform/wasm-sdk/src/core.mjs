/*
 * VieLotusIM (Sen Việt) — WebAssembly SDK Core & DOM Adapter
 * License: MIT
 */

export const ACTION = Object.freeze({
  PASSTHROUGH: 0,
  CONSUMED: 1,
  REPLACE: 2,
  COMMIT: 3,
  RESET: 4,
});

export const INPUT_METHOD = Object.freeze({
  TELEX: 0,
  VNI: 1,
});

export const GRAMMAR_PROFILE = Object.freeze({
  CLASSIC: 0,
  SEN_FLEX: 1,
});

const BLOCKED_INPUT_TYPES = new Set([
  "password",
  "email",
  "url",
  "number",
  "tel",
  "date",
  "datetime-local",
  "month",
  "week",
  "time",
  "color",
  "file",
  "hidden",
  "range",
  "checkbox",
  "radio",
  "button",
  "submit",
  "reset",
  "image",
]);

const NAV_RESET_KEYS = new Set([
  "ArrowLeft",
  "ArrowRight",
  "ArrowUp",
  "ArrowDown",
  "Home",
  "End",
  "PageUp",
  "PageDown",
  "Escape",
]);

// Matches precomposed Vietnamese diacritics (Latin-1 accented vowels, đ/Đ, ă/Ă, ơ/Ơ, ư/Ư, Latin Extended Additional)
const VIETNAMESE_DIACRITIC_RE = /[\u00C0-\u00FF\u0102\u0103\u0110\u0111\u0128\u0129\u0168\u0169\u01A0\u01A1\u01AF\u01B0\u1EA0-\u1EF9]/;

const DEFAULT_STORAGE_KEY = "vielotus.foreignIme";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder("utf-8");

const moduleCache = new WeakMap();
const sharedInstanceCache = new WeakMap();

function normalizeInputMethod(value) {
  if (value === 1 || value === "vni" || value === "VNI") return INPUT_METHOD.VNI;
  return INPUT_METHOD.TELEX;
}

function normalizeGrammarProfile(value) {
  if (value === 0 || value === "classic" || value === "CLASSIC") return GRAMMAR_PROFILE.CLASSIC;
  return GRAMMAR_PROFILE.SEN_FLEX;
}

function normalizeOptions(options = {}) {
  return {
    inputMethod: normalizeInputMethod(options.inputMethod ?? INPUT_METHOD.TELEX),
    grammarProfile: normalizeGrammarProfile(options.grammarProfile ?? GRAMMAR_PROFILE.SEN_FLEX),
    smartBilingual: options.smartBilingual ?? true,
    modernOrthography: options.modernOrthography ?? true,
    quickTelex: options.quickTelex ?? false,
    relaxedCoda: options.relaxedCoda ?? false,
    macroEnabled: options.macroEnabled ?? false,
  };
}

export function decodeBase64(base64) {
  if (typeof Buffer !== "undefined") {
    const buf = Buffer.from(base64, "base64");
    return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  }
  const bin = atob(base64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function getWasmInstance(wasmSource, isolate = false) {
  let mod;
  if (wasmSource instanceof WebAssembly.Module) {
    mod = wasmSource;
  } else {
    const bytes = wasmSource instanceof Uint8Array ? wasmSource : new Uint8Array(wasmSource);
    let modPromise = moduleCache.get(bytes);
    if (!modPromise) {
      modPromise = WebAssembly.compile(bytes);
      moduleCache.set(bytes, modPromise);
    }
    mod = await modPromise;
  }
  if (isolate) {
    return WebAssembly.instantiate(mod, {});
  }
  let instPromise = sharedInstanceCache.get(mod);
  if (!instPromise) {
    instPromise = WebAssembly.instantiate(mod, {});
    sharedInstanceCache.set(mod, instPromise);
  }
  return instPromise;
}

function readCStr(exports, ptr) {
  if (!ptr) return "";
  const u8 = new Uint8Array(exports.memory.buffer, ptr);
  let end = 0;
  while (u8[end] !== 0) end++;
  return textDecoder.decode(u8.subarray(0, end));
}

function writeCStr(exports, str) {
  const encoded = textEncoder.encode(str);
  const total = encoded.length + 1;
  const ptr = exports.vielotus_wasm_alloc(total);
  if (!ptr) {
    const cap = exports.vielotus_wasm_scratch_capacity ? exports.vielotus_wasm_scratch_capacity() : 65536;
    throw new RangeError(`String exceeds WASM scratch capacity (${total} > ${cap} bytes)`);
  }
  const mem = new Uint8Array(exports.memory.buffer, ptr, total);
  mem.set(encoded, 0);
  mem[encoded.length] = 0;
  return ptr;
}

export class VieLotusEngine {
  #exp;
  #session;
  #options;
  #destroyed = false;

  constructor(exports, options = {}) {
    this.#exp = exports;
    this.#options = normalizeOptions(options);
    this.#session = this.#createRawSession();
    if (options.macros !== undefined) {
      this.loadMacros(options.macros);
    }
  }

  #createRawSession() {
    const max = this.#exp.vielotus_wasm_max_sessions ? this.#exp.vielotus_wasm_max_sessions() : 32;
    const active = this.#exp.vielotus_wasm_active_sessions ? this.#exp.vielotus_wasm_active_sessions() : 0;
    if (active >= max) {
      throw new RangeError(
        `VieLotus WASM session pool exhausted (${active}/${max}). Call engine.destroy() or pass { isolate: true }.`
      );
    }
    const handle = this.#exp.vielotus_create_session();
    this.#applyOptionsTo(handle, this.#options);
    return handle;
  }

  #applyOptionsTo(handle, opts) {
    this.#exp.vielotus_set_input_method(handle, opts.inputMethod);
    this.#exp.vielotus_set_grammar_profile(handle, opts.grammarProfile);
    this.#exp.vielotus_set_smart_bilingual(handle, opts.smartBilingual ? 1 : 0);
    this.#exp.vielotus_set_modern_orthography(handle, opts.modernOrthography ? 1 : 0);
    this.#exp.vielotus_set_quick_telex(handle, opts.quickTelex ? 1 : 0);
    this.#exp.vielotus_set_relaxed_coda(handle, opts.relaxedCoda ? 1 : 0);
    this.#exp.vielotus_set_macro_enabled(handle, opts.macroEnabled ? 1 : 0);
  }

  #assertAlive() {
    if (this.#destroyed) {
      throw new Error("VieLotusEngine instance has already been destroyed.");
    }
  }

  #readResult(action) {
    const s = this.#session;
    const backspaces = this.#exp.vielotus_get_last_backspaces(s);
    const text = readCStr(this.#exp, this.#exp.vielotus_get_last_text(s));
    const isOverride = Boolean(this.#exp.vielotus_get_last_is_override(s));
    const composing = Boolean(this.#exp.vielotus_is_composing(s));
    return {
      action,
      backspaces,
      text,
      isOverride,
      composing,
      composingText: composing ? readCStr(this.#exp, this.#exp.vielotus_get_composing_text(s)) : "",
      rawText: composing ? readCStr(this.#exp, this.#exp.vielotus_get_raw_text(s)) : "",
    };
  }

  feed(charOrCodepoint) {
    this.#assertAlive();
    const cp =
      typeof charOrCodepoint === "number"
        ? charOrCodepoint
        : typeof charOrCodepoint === "string" && charOrCodepoint.length > 0
          ? charOrCodepoint.codePointAt(0)
          : 0;
    if (!cp) {
      return this.#readResult(ACTION.PASSTHROUGH);
    }
    const action = this.#exp.vielotus_feed_char(this.#session, cp >>> 0);
    return this.#readResult(action);
  }

  backspace() {
    this.#assertAlive();
    const action = this.#exp.vielotus_feed_backspace(this.#session);
    return this.#readResult(action);
  }

  commitWord() {
    this.#assertAlive();
    const action = this.#exp.vielotus_commit_word(this.#session);
    return this.#readResult(action);
  }

  reset() {
    this.#assertAlive();
    this.#exp.vielotus_reset_session(this.#session);
  }

  resetContext() {
    this.#assertAlive();
    this.#exp.vielotus_destroy_session(this.#session);
    this.#session = this.#createRawSession();
  }

  setOptions(partial = {}) {
    this.#assertAlive();
    const next = {
      ...this.#options,
      ...(partial.inputMethod !== undefined ? { inputMethod: normalizeInputMethod(partial.inputMethod) } : {}),
      ...(partial.grammarProfile !== undefined ? { grammarProfile: normalizeGrammarProfile(partial.grammarProfile) } : {}),
      ...(partial.smartBilingual !== undefined ? { smartBilingual: Boolean(partial.smartBilingual) } : {}),
      ...(partial.modernOrthography !== undefined ? { modernOrthography: Boolean(partial.modernOrthography) } : {}),
      ...(partial.quickTelex !== undefined ? { quickTelex: Boolean(partial.quickTelex) } : {}),
      ...(partial.relaxedCoda !== undefined ? { relaxedCoda: Boolean(partial.relaxedCoda) } : {}),
      ...(partial.macroEnabled !== undefined ? { macroEnabled: Boolean(partial.macroEnabled) } : {}),
    };
    this.#options = next;
    this.#applyOptionsTo(this.#session, next);
    if (partial.macros !== undefined) {
      this.loadMacros(partial.macros);
    }
  }

  getOptions() {
    return {
      inputMethod: this.#options.inputMethod === INPUT_METHOD.VNI ? "vni" : "telex",
      grammarProfile: this.#options.grammarProfile === GRAMMAR_PROFILE.CLASSIC ? "classic" : "senFlex",
      smartBilingual: this.#options.smartBilingual,
      modernOrthography: this.#options.modernOrthography,
      quickTelex: this.#options.quickTelex,
      relaxedCoda: this.#options.relaxedCoda,
      macroEnabled: this.#options.macroEnabled,
    };
  }

  appendContext(word) {
    this.#assertAlive();
    if (!word) return;
    const ptr = writeCStr(this.#exp, String(word));
    this.#exp.vielotus_append_context(this.#session, ptr);
  }

  syncContext(beforeText) {
    this.#assertAlive();
    const ptr = writeCStr(this.#exp, String(beforeText ?? ""));
    this.#exp.vielotus_sync_armed_word(this.#session, ptr);
  }

  loadMacros(macros) {
    this.#assertAlive();
    const json = typeof macros === "string" ? macros : JSON.stringify(macros);
    const ptr = writeCStr(this.#exp, json);
    return Boolean(this.#exp.vielotus_load_macros_json(ptr));
  }

  resetDefaultMacros() {
    this.#assertAlive();
    this.#exp.vielotus_reset_default_macros();
  }

  typeString(sequence, { interpretBackspace = false, commit = true } = {}) {
    this.#assertAlive();
    const buf = [];
    for (const ch of sequence) {
      if (interpretBackspace && ch === "<") {
        const res = this.backspace();
        if (res.action === ACTION.REPLACE) {
          buf.splice(Math.max(0, buf.length - res.backspaces), res.backspaces, ...Array.from(res.text));
        } else if (res.action === ACTION.PASSTHROUGH && buf.length > 0) {
          buf.pop();
        }
      } else {
        const res = this.feed(ch);
        if (res.action === ACTION.REPLACE) {
          buf.splice(Math.max(0, buf.length - res.backspaces), res.backspaces, ...Array.from(res.text));
        } else if (res.action === ACTION.COMMIT) {
          if (res.isOverride) {
            buf.splice(Math.max(0, buf.length - res.backspaces), res.backspaces, ...Array.from(res.text));
          }
          buf.push(ch);
        } else if (res.action === ACTION.PASSTHROUGH) {
          buf.push(ch);
        }
      }
    }
    if (commit && this.isComposing) {
      const res = this.commitWord();
      if (res.action === ACTION.COMMIT && res.isOverride) {
        buf.splice(Math.max(0, buf.length - res.backspaces), res.backspaces, ...Array.from(res.text));
      }
    }
    return buf.join("");
  }

  get isComposing() {
    if (this.#destroyed) return false;
    return Boolean(this.#exp.vielotus_is_composing(this.#session));
  }

  get composingText() {
    if (this.#destroyed) return "";
    return readCStr(this.#exp, this.#exp.vielotus_get_composing_text(this.#session));
  }

  get rawText() {
    if (this.#destroyed) return "";
    return readCStr(this.#exp, this.#exp.vielotus_get_raw_text(this.#session));
  }

  get version() {
    return readCStr(this.#exp, this.#exp.vielotus_get_version());
  }

  get buildStamp() {
    return readCStr(this.#exp, this.#exp.vielotus_get_build_stamp());
  }

  get destroyed() {
    return this.#destroyed;
  }

  get activeSessions() {
    return this.#exp.vielotus_wasm_active_sessions ? this.#exp.vielotus_wasm_active_sessions() : 0;
  }

  get maxSessions() {
    return this.#exp.vielotus_wasm_max_sessions ? this.#exp.vielotus_wasm_max_sessions() : 32;
  }

  destroy() {
    if (this.#destroyed) return;
    this.#exp.vielotus_destroy_session(this.#session);
    this.#session = 0;
    this.#destroyed = true;
  }
}

export async function createEngineFromSource(wasmSource, options = {}) {
  const instance = await getWasmInstance(wasmSource, Boolean(options.isolate));
  return new VieLotusEngine(instance.exports, options);
}

export async function createEngineFromBytes(wasmBytes, options = {}) {
  return createEngineFromSource(wasmBytes, options);
}

export function isEligibleElement(element, { allowUnsafeTypes = false } = {}) {
  if (!element || typeof element !== "object") return false;
  const tag = String(element.tagName ?? "").toUpperCase();
  if (tag === "TEXTAREA") return true;
  if (tag === "INPUT") {
    if (allowUnsafeTypes) return true;
    const type = String(element.type ?? "text").toLowerCase();
    return !BLOCKED_INPUT_TYPES.has(type);
  }
  if (
    element.isContentEditable === true ||
    element.getAttribute?.("contenteditable") === "true" ||
    element.getAttribute?.("contenteditable") === ""
  ) {
    return true;
  }
  return false;
}

function isTextControl(element) {
  const tag = String(element?.tagName ?? "").toUpperCase();
  return tag === "INPUT" || tag === "TEXTAREA";
}

function safeStorageGet(key) {
  try {
    return globalThis.localStorage?.getItem?.(key) ?? null;
  } catch {
    return null;
  }
}

function safeStorageSet(key, val) {
  try {
    if (val === null) {
      globalThis.localStorage?.removeItem?.(key);
    } else {
      globalThis.localStorage?.setItem?.(key, val);
    }
  } catch {
    // Ignore private-mode / sandboxed storage errors
  }
}

function dispatchInputEvent(element) {
  if (typeof element.dispatchEvent !== "function") return;
  try {
    if (typeof Event === "function") {
      element.dispatchEvent(new Event("input", { bubbles: true }));
    } else {
      element.dispatchEvent({ type: "input", bubbles: true });
    }
  } catch {
    // Minimal mock environment fallback
  }
}

function replaceTextInTextControl(element, backspaces, insertText) {
  const value = String(element.value ?? "");
  const selStart = typeof element.selectionStart === "number" ? element.selectionStart : value.length;
  const selEnd = typeof element.selectionEnd === "number" ? element.selectionEnd : selStart;
  const start = Math.max(0, selStart - backspaces);
  const end = Math.max(start, selEnd);

  if (typeof element.setRangeText === "function") {
    element.setRangeText(insertText, start, end, "end");
  } else {
    element.value = value.slice(0, start) + insertText + value.slice(end);
    const caret = start + insertText.length;
    if (typeof element.setSelectionRange === "function") {
      element.setSelectionRange(caret, caret);
    } else {
      element.selectionStart = caret;
      element.selectionEnd = caret;
    }
  }
  dispatchInputEvent(element);
}

function replaceTextInContentEditable(element, backspaces, insertText) {
  const doc = element.ownerDocument ?? globalThis.document;
  const sel = doc?.defaultView?.getSelection?.() ?? globalThis.getSelection?.();
  if (!sel || sel.rangeCount === 0) return false;
  const range = sel.getRangeAt(0);
  if (!range.collapsed) {
    range.deleteContents();
  }

  let targetNode = range.startContainer;
  let offset = range.startOffset;

  if (targetNode && targetNode.nodeType !== 3 && offset > 0 && targetNode.childNodes) {
    const prev = targetNode.childNodes[offset - 1];
    if (prev && prev.nodeType === 3) {
      targetNode = prev;
      offset = prev.data.length;
    }
  }

  if (targetNode && targetNode.nodeType === 3) {
    const del = Math.min(backspaces, offset);
    if (del > 0) targetNode.deleteData(offset - del, del);
    const insertAt = offset - del;
    if (insertText.length > 0) targetNode.insertData(insertAt, insertText);
    const newOffset = insertAt + insertText.length;
    range.setStart(targetNode, newOffset);
    range.collapse(true);
    sel.removeAllRanges();
    sel.addRange(range);
  } else if (doc && typeof doc.createTextNode === "function") {
    const textNode = doc.createTextNode(insertText);
    range.insertNode(textNode);
    range.setStart(textNode, insertText.length);
    range.collapse(true);
    sel.removeAllRanges();
    sel.addRange(range);
  } else {
    return false;
  }

  dispatchInputEvent(element);
  return true;
}

function matchesDefaultToggleKey(event) {
  return (
    Boolean(event.ctrlKey) &&
    !event.metaKey &&
    !event.altKey &&
    !event.shiftKey &&
    (event.code === "Space" || event.key === " ")
  );
}

function createBlockedController(element) {
  return {
    element,
    engine: null,
    isBlocked: true,
    isEnabled: () => false,
    isYielded: () => false,
    setEnabled: () => {},
    setOptions: () => {},
    getOptions: () => null,
    reset: () => {},
    destroy: () => {},
  };
}

export async function attachWithLoader(loadWasmSource, element, options = {}) {
  if (!element || typeof element.addEventListener !== "function") {
    throw new TypeError("attach() requires a valid DOM element with addEventListener().");
  }

  if (!isEligibleElement(element, { allowUnsafeTypes: Boolean(options.allowUnsafeTypes) })) {
    return createBlockedController(element);
  }

  const wasmSource = await loadWasmSource(options);
  const engine = await createEngineFromSource(wasmSource, options);

  const yieldToSystemIme = options.yieldToSystemIme ?? true;
  const persistForeignIme = options.persistForeignIme ?? true;
  const storageKey = options.storageKey ?? DEFAULT_STORAGE_KEY;
  const toggleMatcher =
    options.toggleKey === false
      ? null
      : typeof options.toggleKey === "function"
        ? options.toggleKey
        : matchesDefaultToggleKey;

  let enabled = options.enabled ?? true;
  let yielded = false;
  let isApplying = false;
  let destroyed = false;

  if (yieldToSystemIme && persistForeignIme && safeStorageGet(storageKey) === "1") {
    yielded = true;
    enabled = false;
    options.onForeignIme?.({ reason: "persisted", element });
  }

  const notifyState = (reason) => {
    options.onStateChange?.({ enabled, yielded, reason, element });
  };

  const triggerYield = (reason) => {
    if (!yieldToSystemIme || yielded) return;
    yielded = true;
    enabled = false;
    engine.reset();
    if (persistForeignIme) safeStorageSet(storageKey, "1");
    options.onForeignIme?.({ reason, element });
    notifyState(reason);
  };

  const applyEdit = (backspaces, insertText) => {
    isApplying = true;
    try {
      if (isTextControl(element)) {
        replaceTextInTextControl(element, backspaces, insertText);
      } else {
        replaceTextInContentEditable(element, backspaces, insertText);
      }
    } finally {
      isApplying = false;
    }
  };

  const hasNonCollapsedSelection = () => {
    if (isTextControl(element)) {
      return (
        typeof element.selectionStart === "number" &&
        typeof element.selectionEnd === "number" &&
        element.selectionStart !== element.selectionEnd
      );
    }
    const doc = element.ownerDocument ?? globalThis.document;
    const sel = doc?.defaultView?.getSelection?.() ?? globalThis.getSelection?.();
    return Boolean(sel && sel.rangeCount > 0 && !sel.getRangeAt(0).collapsed);
  };

  const setEnabled = (nextEnabled, reason = "api") => {
    if (destroyed) return;
    const next = Boolean(nextEnabled);
    if (next) {
      yielded = false;
      if (persistForeignIme) safeStorageSet(storageKey, null);
    }
    enabled = next;
    engine.reset();
    notifyState(reason);
  };

  const onCompositionStart = () => {
    if (destroyed) return;
    triggerYield("compositionstart");
  };

  const onInput = (event) => {
    if (destroyed || isApplying) return;
    const inputType = String(event?.inputType ?? "");
    // Ignore paste, drop, and history undo/redo so pasting Vietnamese never trips OS-IME detection
    if (
      inputType === "insertFromPaste" ||
      inputType === "insertFromDrop" ||
      inputType === "historyUndo" ||
      inputType === "historyRedo"
    ) {
      engine.reset();
      return;
    }
    if (enabled && yieldToSystemIme && typeof event?.data === "string" && VIETNAMESE_DIACRITIC_RE.test(event.data)) {
      triggerYield("input-diacritic");
    }
  };

  const onKeyDown = (event) => {
    if (destroyed || event.defaultPrevented) return;

    if (toggleMatcher && toggleMatcher(event)) {
      event.preventDefault();
      setEnabled(!enabled, "toggle-key");
      return;
    }

    if (!enabled) return;

    if (event.isComposing || event.keyCode === 229 || event.key === "Process" || event.key === "Dead") {
      triggerYield("key-composing");
      return;
    }

    // Never hijack OS shortcuts (Cmd/Ctrl/Alt chords)
    if (event.ctrlKey || event.metaKey || event.altKey) {
      const k = String(event.key ?? "").toLowerCase();
      if (k === "v" || k === "x" || k === "z" || k === "y" || k === "a") {
        engine.reset();
      }
      return;
    }

    const key = event.key;
    if (typeof key !== "string" || key.length === 0) return;

    if (NAV_RESET_KEYS.has(key)) {
      engine.reset();
      return;
    }

    if (key === "Enter" || key === "Tab") {
      if (engine.isComposing) {
        const res = engine.commitWord();
        if (res.action === ACTION.COMMIT && res.isOverride) {
          applyEdit(res.backspaces, res.text);
        }
        options.onKeyProcessed?.({ key, result: res, elapsedUs: 0 });
      }
      return;
    }

    if (key === "Backspace") {
      if (hasNonCollapsedSelection()) {
        engine.reset();
        return;
      }
      const t0 = typeof performance !== "undefined" ? performance.now() : 0;
      const res = engine.backspace();
      const elapsedUs = typeof performance !== "undefined" ? (performance.now() - t0) * 1000 : 0;
      if (res.action === ACTION.REPLACE) {
        event.preventDefault();
        applyEdit(res.backspaces, res.text);
      } else if (res.action === ACTION.CONSUMED) {
        event.preventDefault();
      }
      options.onKeyProcessed?.({ key, result: res, elapsedUs });
      return;
    }

    if (key.length === 1) {
      const cp = key.codePointAt(0);
      if (cp >= 0x80 && VIETNAMESE_DIACRITIC_RE.test(key)) {
        triggerYield("key-diacritic");
        return;
      }
      if (cp < 0x20 || cp > 0x7e) {
        engine.reset();
        return;
      }

      if (hasNonCollapsedSelection()) {
        engine.reset();
      }

      const t0 = typeof performance !== "undefined" ? performance.now() : 0;
      const res = engine.feed(cp);
      const elapsedUs = typeof performance !== "undefined" ? (performance.now() - t0) * 1000 : 0;

      if (res.action === ACTION.REPLACE) {
        event.preventDefault();
        applyEdit(res.backspaces, res.text);
      } else if (res.action === ACTION.COMMIT) {
        if (res.isOverride) {
          event.preventDefault();
          applyEdit(res.backspaces, res.text + key);
        }
      } else if (res.action === ACTION.CONSUMED) {
        event.preventDefault();
      }

      options.onKeyProcessed?.({ key, result: res, elapsedUs });
    }
  };

  const onResetBoundary = () => {
    if (!destroyed) engine.reset();
  };

  element.addEventListener("compositionstart", onCompositionStart);
  element.addEventListener("input", onInput);
  element.addEventListener("keydown", onKeyDown);
  element.addEventListener("mousedown", onResetBoundary);
  element.addEventListener("blur", onResetBoundary);
  element.addEventListener("paste", onResetBoundary);
  element.addEventListener("cut", onResetBoundary);

  return {
    element,
    engine,
    isBlocked: false,
    isEnabled: () => enabled,
    isYielded: () => yielded,
    setEnabled: (v) => setEnabled(v, "api"),
    setOptions: (opts) => engine.setOptions(opts),
    getOptions: () => engine.getOptions(),
    reset: () => engine.reset(),
    resetContext: () => engine.resetContext(),
    destroy: () => {
      if (destroyed) return;
      destroyed = true;
      element.removeEventListener("compositionstart", onCompositionStart);
      element.removeEventListener("input", onInput);
      element.removeEventListener("keydown", onKeyDown);
      element.removeEventListener("mousedown", onResetBoundary);
      element.removeEventListener("blur", onResetBoundary);
      element.removeEventListener("paste", onResetBoundary);
      element.removeEventListener("cut", onResetBoundary);
      engine.destroy();
    },
  };
}
