// Jest から viewer-src/ の ES モジュールを require() で読み込むための変換設定
// （TASK-432.2）。本番のバンドルは esbuild が作るため、babel が関わるのは
// テスト実行時だけ。ここで CommonJS へ落とすことで、既存の require ベースの
// テスト（417 ケース）をそのままの形で維持できる。
// preset-typescript は型注釈を落とすだけで型検査はしない（TASK-432.4）。
// 型検査は npm run typecheck:viewer（tsc --noEmit）が単独で担当する。
module.exports = {
  presets: [['@babel/preset-env', { targets: { node: 'current' } }], '@babel/preset-typescript'],
};
