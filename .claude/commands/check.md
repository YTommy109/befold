# /check — 品質チェック

以下を順番に実行して結果を報告してください。

1. **ビルド**
   ```bash
   cd BefoldApp && swift build
   ```

2. **Swift テスト**
   ```bash
   cd BefoldApp && swift test
   ```

3. **JS テスト**（viewer.js / viewer.html 用）
   ```bash
   cd BefoldApp && [ -d node_modules ] || npm ci
   cd BefoldApp && npx jest
   ```
   `node_modules` が無い環境では先に `npm ci` が必要（`npx jest` の都度取得を避ける）。

問題が見つかった場合は修正してから再実行してください。すべて通過したら「✅ チェック完了」と報告してください。
