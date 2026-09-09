<?xml version="1.0" encoding="UTF-8"?>
<!--
  same-named.xml の表示用スタイルシート（XSLT 1.0）。
  同名フォールバックで選ばれるため、xml 側に処理命令は要らない。
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" encoding="UTF-8"/>

  <xsl:template match="/週報">
    <div class="weekly-report">
      <style>
        .weekly-report { line-height: 1.8; }
        .weekly-report ul { list-style: none; padding-left: 0; }
        .weekly-report li { margin: 0.3em 0; }
        .weekly-report .state {
          display: inline-block; min-width: 5em; margin-right: 0.8em;
          padding: 0 0.5em; border: 1px solid currentColor; border-radius: 4px;
          font-size: 0.85em; text-align: center;
        }
        .weekly-report .done { opacity: 0.6; }
      </style>

      <h1>週報 <xsl:value-of select="@週"/></h1>
      <p><xsl:value-of select="担当"/></p>

      <ul>
        <xsl:for-each select="進捗/項目">
          <li>
            <xsl:if test="@状態 = '完了'">
              <xsl:attribute name="class">done</xsl:attribute>
            </xsl:if>
            <span class="state"><xsl:value-of select="@状態"/></span>
            <xsl:value-of select="."/>
          </li>
        </xsl:for-each>
      </ul>

      <p><xsl:value-of select="所感"/></p>
    </div>
  </xsl:template>
</xsl:stylesheet>
