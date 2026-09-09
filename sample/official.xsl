<?xml version="1.0" encoding="UTF-8"?>
<!--
  sample.xml の表示用スタイルシート（XSLT 1.0）。
  ファイル名が sample.xsl でないのは、同名フォールバックではなく
  sample.xml の xml-stylesheet 処理命令が解決されていることを示すため。
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" encoding="UTF-8"/>

  <xsl:template match="/公文書">
    <div class="official-document">
      <style>
        .official-document { line-height: 1.8; }
        .official-document .header { text-align: right; font-size: 0.9em; opacity: 0.8; }
        .official-document h1 { text-align: center; font-size: 1.4em; border: none; }
        .official-document table { border-collapse: collapse; margin: 1em auto; }
        .official-document th, .official-document td {
          border: 1px solid currentColor; padding: 0.4em 1em; text-align: left;
        }
        .official-document .note { margin-top: 2em; font-size: 0.9em; opacity: 0.8; }
      </style>

      <div class="header">
        <div><xsl:value-of select="ヘッダ/文書番号"/></div>
        <div><xsl:value-of select="ヘッダ/発出日"/></div>
        <div><xsl:value-of select="ヘッダ/発出者"/></div>
      </div>

      <h1><xsl:value-of select="件名"/></h1>

      <xsl:for-each select="本文/段落">
        <p><xsl:value-of select="."/></p>
      </xsl:for-each>

      <p style="text-align: center;">記</p>
      <table>
        <xsl:for-each select="記載事項/項目">
          <tr>
            <th><xsl:value-of select="名称"/></th>
            <td><xsl:value-of select="値"/></td>
          </tr>
        </xsl:for-each>
      </table>

      <p class="note"><xsl:value-of select="備考"/></p>

      <!--
        サニタイズの確認用。変換結果は markdown と同じ DOMPurify 経路を通してから
        差し込むため、この script は取り除かれる。画面に「サニタイズされていません」
        が出たら、その経路が壊れている。
      -->
      <script>
        document.currentScript.insertAdjacentText('beforebegin', 'サニタイズされていません');
      </script>
    </div>
  </xsl:template>
</xsl:stylesheet>
