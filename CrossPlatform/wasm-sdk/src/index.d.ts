/*
 * VieLotusIM (Sen Việt) — WebAssembly SDK TypeScript Declarations
 * License: MIT
 */

export declare const ACTION: Readonly<{
  PASSTHROUGH: 0;
  CONSUMED: 1;
  REPLACE: 2;
  COMMIT: 3;
  RESET: 4;
}>;

export type ActionCode = (typeof ACTION)[keyof typeof ACTION];

export declare const INPUT_METHOD: Readonly<{
  TELEX: 0;
  VNI: 1;
}>;

export type InputMethodOption = "telex" | "vni" | 0 | 1;

export declare const GRAMMAR_PROFILE: Readonly<{
  CLASSIC: 0;
  SEN_FLEX: 1;
}>;

export type GrammarProfileOption = "classic" | "senFlex" | 0 | 1;

export interface EngineOptions {
  inputMethod?: InputMethodOption;
  grammarProfile?: GrammarProfileOption;
  smartBilingual?: boolean;
  modernOrthography?: boolean;
  quickTelex?: boolean;
  relaxedCoda?: boolean;
  macroEnabled?: boolean;
  macros?: Record<string, string> | string;
  /** Instantiate an isolated WebAssembly.Instance instead of sharing the 32-slot pool. */
  isolate?: boolean;
  /** External loader only: custom URL to `vielotus-core.wasm`. */
  wasmUrl?: string | URL;
  /** External loader only: preloaded WASM bytes. */
  wasmBinary?: Uint8Array | ArrayBuffer;
}

export interface ResolvedEngineOptions {
  inputMethod: "telex" | "vni";
  grammarProfile: "classic" | "senFlex";
  smartBilingual: boolean;
  modernOrthography: boolean;
  quickTelex: boolean;
  relaxedCoda: boolean;
  macroEnabled: boolean;
}

export interface EngineResult {
  action: ActionCode;
  backspaces: number;
  text: string;
  isOverride: boolean;
  composing: boolean;
  composingText: string;
  rawText: string;
}

export interface TypeStringOptions {
  interpretBackspace?: boolean;
  commit?: boolean;
}

export declare class VieLotusEngine {
  feed(charOrCodepoint: string | number): EngineResult;
  backspace(): EngineResult;
  commitWord(): EngineResult;
  reset(): void;
  resetContext(): void;
  setOptions(partial?: Partial<EngineOptions>): void;
  getOptions(): ResolvedEngineOptions;
  appendContext(word: string): void;
  syncContext(beforeText: string): void;
  loadMacros(macros: Record<string, string> | string): boolean;
  resetDefaultMacros(): void;
  typeString(sequence: string, options?: TypeStringOptions): string;
  readonly isComposing: boolean;
  readonly composingText: string;
  readonly rawText: string;
  readonly version: string;
  readonly buildStamp: string;
  readonly destroyed: boolean;
  readonly activeSessions: number;
  readonly maxSessions: number;
  destroy(): void;
}

export type ForeignImeReason =
  | "compositionstart"
  | "key-composing"
  | "key-diacritic"
  | "input-diacritic"
  | "persisted";

export interface AttachOptions extends EngineOptions {
  enabled?: boolean;
  yieldToSystemIme?: boolean;
  persistForeignIme?: boolean;
  storageKey?: string;
  allowUnsafeTypes?: boolean;
  toggleKey?: false | ((event: KeyboardEvent) => boolean);
  onForeignIme?: (info: { reason: ForeignImeReason; element: HTMLElement }) => void;
  onStateChange?: (info: {
    enabled: boolean;
    yielded: boolean;
    reason: string;
    element: HTMLElement;
  }) => void;
  onKeyProcessed?: (info: {
    key: string;
    result: EngineResult;
    elapsedUs: number;
  }) => void;
}

export interface AttachedController {
  readonly element: HTMLElement;
  readonly engine: VieLotusEngine | null;
  readonly isBlocked: boolean;
  isEnabled(): boolean;
  isYielded(): boolean;
  setEnabled(enabled: boolean): void;
  setOptions(partial?: Partial<EngineOptions>): void;
  getOptions(): ResolvedEngineOptions | null;
  reset(): void;
  resetContext?(): void;
  destroy(): void;
}

export declare function isEligibleElement(
  element: unknown,
  options?: { allowUnsafeTypes?: boolean }
): boolean;

export declare function createEngine(options?: EngineOptions): Promise<VieLotusEngine>;

export declare function attach(
  element: HTMLElement,
  options?: AttachOptions
): Promise<AttachedController>;

export declare function getWasmBytes(options?: {
  wasmUrl?: string | URL;
  wasmBinary?: Uint8Array | ArrayBuffer;
}): Promise<Uint8Array>;
