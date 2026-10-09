;(function () {
  'use strict'

  // 動きを減らす設定のときは自動再生を止め、操作できる状態にする（ポスターに結果の 1 コマが入っている）。
  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
  var video = document.querySelector('.quicklook-video')
  if (!video) return
  video.removeAttribute('autoplay')
  video.pause()
  video.setAttribute('controls', '')
})()
