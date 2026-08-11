(() => {
  // viewer-src/bundle-marker.js
  var bundleMarker = Object.freeze({ name: "befold-viewer-bundle" });

  // viewer-src/index.js
  globalThis.__befoldBundle = bundleMarker;
})();
