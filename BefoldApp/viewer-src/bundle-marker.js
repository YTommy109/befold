// index.js から import される最小モジュール。存在意義はモジュール解決が
// 実際に行われることの確認であり、viewer の振る舞いには関与しない。
export const bundleMarker = Object.freeze({ name: "befold-viewer-bundle" });
