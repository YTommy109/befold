// Jest から viewer-src/ の ES モジュールを require() で読み込むための変換設定
// （TASK-432.2）。本番のバンドルは esbuild が作るため、babel が関わるのは
// テスト実行時だけ。ここで CommonJS へ落とすことで、既存の require ベースの
// テスト（417 ケース）をそのままの形で維持できる。
module.exports = {
  presets: [
    ["@babel/preset-env", { targets: { node: "current" } }],
  ],
};
