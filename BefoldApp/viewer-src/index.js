// バンドル経路を通すための最小エントリ（TASK-432.1）。
// viewer.html からはまだ読み込まれていない。実際の viewer ロジックの移行は
// 後続サブタスクで行う。ここではモジュール解決（import）を 1 つ含めることで、
// 「ソース → esbuild → 成果物」の経路が実際にバンドルとして機能することを担保する。
import { bundleMarker } from "./bundle-marker.js";

globalThis.__befoldBundle = bundleMarker;
