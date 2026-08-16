import { describe, expect, it } from 'vitest'
import { summarizeLang } from '../src/lib/lang'

describe('summarizeLang', () => {
  it('日本語・英語はそのまま、それ以外は other に畳む', () => {
    expect(summarizeLang('ja')).toBe('ja')
    expect(summarizeLang('en')).toBe('en')
    expect(summarizeLang('de')).toBe('other')
  })

  it('地域つきタグは言語部分だけを見る', () => {
    // en-US と en-GB を分けても LP は同じ英語しか出さないため、内訳の
    // カーディナリティを増やすだけで読み手に何も伝わらない。
    expect(summarizeLang('en-US')).toBe('en')
    expect(summarizeLang('en-GB')).toBe('en')
    expect(summarizeLang('zh-Hans-TW')).toBe('other')
  })

  it('複数候補は先頭（第一希望）だけを見る', () => {
    expect(summarizeLang('ja,en-US;q=0.9,en;q=0.8')).toBe('ja')
    expect(summarizeLang('en-US,en;q=0.9,ja;q=0.8')).toBe('en')
  })

  it('大文字・前後の空白を含んでいても判定できる', () => {
    expect(summarizeLang(' JA-JP , en;q=0.9 ')).toBe('ja')
  })

  it('ヘッダが無い・空・希望が無い場合は null', () => {
    // ヘッダを送らないクライアント（Sparkle）と、どの言語でもよいという
    // 表明（*）を、どちらも「言語設定なし」として扱う。
    expect(summarizeLang(null)).toBeNull()
    expect(summarizeLang('')).toBeNull()
    expect(summarizeLang('*')).toBeNull()
  })
})
