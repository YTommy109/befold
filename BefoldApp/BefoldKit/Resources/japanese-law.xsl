<?xml version="1.0" encoding="UTF-8"?>
<!--
  法令標準XML（XMLSchemaForJapaneseLaw v3）を読める形へ変換する内蔵スタイルシート。
  TASK-597。e-Gov が配布する法令XMLには表示用 XSL が同梱されないため、befold が持つ。

  出力は #diagram-wrap へ差し込む HTML 断片で、DOMPurify を通る。見た目は
  style.css の `.xslt-body .law-*` が持ち、ここでは構造とクラス名だけを決める
  （<style> はサニタイズの対象で、通っても通らなくても見た目が二重管理になる）。

  スキーマ: https://laws.e-gov.go.jp/file/XMLSchemaForJapaneseLaw_v3.xsd
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" encoding="UTF-8" indent="no"/>
  <xsl:strip-space elements="Law LawBody TOC MainProvision SupplProvision Preamble
    Part Chapter Section Subsection Division Article Paragraph Item
    Subitem1 Subitem2 Subitem3 Subitem4 Subitem5 Subitem6 Subitem7 Subitem8 Subitem9 Subitem10
    ParagraphSentence ItemSentence Subitem1Sentence Subitem2Sentence Subitem3Sentence
    Subitem4Sentence Subitem5Sentence Subitem6Sentence Subitem7Sentence Subitem8Sentence
    Subitem9Sentence Subitem10Sentence Column
    TableStruct Table TableRow TableHeaderRow TableColumn TableHeaderColumn
    AppdxTable AppdxStyle AppdxNote AppdxFig AppdxFormat Appdx
    SupplProvisionAppdxTable SupplProvisionAppdxStyle SupplProvisionAppdx
    StyleStruct Style NoteStruct Note FormatStruct Format FigStruct
    Remarks List ListSentence QuoteStruct ArithFormula AmendProvision"/>

  <!-- ルート ================================================================ -->

  <xsl:template match="/Law">
    <div class="law">
      <xsl:apply-templates select="LawBody/LawTitle"/>
      <p class="law-num"><xsl:value-of select="LawNum"/></p>
      <xsl:apply-templates select="LawBody/*[not(self::LawTitle)]"/>
    </div>
  </xsl:template>

  <xsl:template match="LawTitle">
    <h1 class="law-title"><xsl:apply-templates/></h1>
  </xsl:template>

  <xsl:template match="EnactStatement">
    <p class="law-enact"><xsl:apply-templates/></p>
  </xsl:template>

  <!-- 目次 ================================================================== -->

  <xsl:template match="TOC">
    <nav class="law-toc">
      <xsl:apply-templates/>
    </nav>
  </xsl:template>

  <xsl:template match="TOCLabel">
    <h2 class="law-toc-label"><xsl:apply-templates/></h2>
  </xsl:template>

  <xsl:template match="TOCPart | TOCChapter | TOCSection | TOCSubsection | TOCDivision
                     | TOCArticle | TOCSupplProvision | TOCPreambleLabel | TOCAppdxTableLabel">
    <div class="law-toc-entry"><xsl:apply-templates/></div>
  </xsl:template>

  <!-- 編・章・節・款・目 ==================================================== -->

  <xsl:template match="Preamble">
    <section class="law-preamble"><xsl:apply-templates/></section>
  </xsl:template>

  <xsl:template match="MainProvision">
    <section class="law-main"><xsl:apply-templates/></section>
  </xsl:template>

  <xsl:template match="Part | Chapter | Section | Subsection | Division">
    <section class="law-division"><xsl:apply-templates/></section>
  </xsl:template>

  <xsl:template match="PartTitle">
    <h2 class="law-heading law-part-title"><xsl:apply-templates/></h2>
  </xsl:template>

  <xsl:template match="ChapterTitle">
    <h3 class="law-heading law-chapter-title"><xsl:apply-templates/></h3>
  </xsl:template>

  <xsl:template match="SectionTitle">
    <h4 class="law-heading law-section-title"><xsl:apply-templates/></h4>
  </xsl:template>

  <xsl:template match="SubsectionTitle">
    <h5 class="law-heading law-subsection-title"><xsl:apply-templates/></h5>
  </xsl:template>

  <xsl:template match="DivisionTitle">
    <h6 class="law-heading law-division-title"><xsl:apply-templates/></h6>
  </xsl:template>

  <xsl:template match="ArticleRange">
    <span class="law-article-range"><xsl:apply-templates/></span>
  </xsl:template>

  <!-- 条・項・号 ============================================================ -->

  <!--
    条名（ArticleTitle）はここでは出さず、最初の項の本文の頭へ差し込む
    （Paragraph の規則を参照）。ここでも出すと同じ条名が 2 回並ぶ。
  -->
  <xsl:template match="Article">
    <article class="law-article">
      <xsl:apply-templates select="*[not(self::ArticleTitle)]"/>
    </article>
  </xsl:template>

  <xsl:template match="ArticleCaption | ParagraphCaption">
    <p class="law-caption"><xsl:apply-templates/></p>
  </xsl:template>

  <!-- 条見出しは本文の直前に置かれるため、条名だけの行にする。 -->
  <xsl:template match="ArticleTitle">
    <span class="law-article-title"><xsl:apply-templates/></span>
  </xsl:template>

  <!--
    項は「項番号 + 本文」を 1 行で始める。第 1 項の ParagraphNum は空要素なので、
    その場合に条名（第一条）が本文の頭に来るよう Article 側の ArticleTitle を
    最初の項へ差し込む。
  -->
  <xsl:template match="Paragraph">
    <div class="law-paragraph">
      <xsl:apply-templates select="ParagraphCaption"/>
      <p class="law-paragraph-body">
        <xsl:if test="not(preceding-sibling::Paragraph)">
          <xsl:apply-templates select="../ArticleTitle"/>
          <xsl:if test="../ArticleTitle"><xsl:text>　</xsl:text></xsl:if>
        </xsl:if>
        <!--
          項番号は ParagraphNum を使う。ただし日本国憲法のように全項で
          ParagraphNum が空の法令があり（実測: kenpo.xml は 1 件も値を持たない）、
          そのままだと第 2 項以降が番号なしで前の項と地続きに見える。
          空のときは @Num を使い、第 1 項だけは番号を出さない。
        -->
        <xsl:choose>
          <xsl:when test="string(ParagraphNum)">
            <span class="law-paragraph-num"><xsl:value-of select="ParagraphNum"/></span>
            <xsl:text>　</xsl:text>
          </xsl:when>
          <xsl:when test="@Num and @Num != '1'">
            <span class="law-paragraph-num"><xsl:value-of select="@Num"/></span>
            <xsl:text>　</xsl:text>
          </xsl:when>
        </xsl:choose>
        <xsl:apply-templates select="ParagraphSentence"/>
      </p>
      <xsl:apply-templates select="*[not(self::ParagraphCaption or self::ParagraphNum
        or self::ParagraphSentence or self::ArticleTitle)]"/>
    </div>
  </xsl:template>

  <!-- 号・細分は入れ子の深さで字下げする（CSS の子孫セレクタ）。種別ごとのクラスは持たせない。 -->
  <xsl:template match="Item | Subitem1 | Subitem2 | Subitem3 | Subitem4 | Subitem5
                     | Subitem6 | Subitem7 | Subitem8 | Subitem9 | Subitem10">
    <div class="law-item">
      <p class="law-item-body">
        <xsl:if test="string(*[substring(local-name(), string-length(local-name()) - 4) = 'Title'])">
          <span class="law-item-title">
            <xsl:value-of select="*[substring(local-name(), string-length(local-name()) - 4) = 'Title']"/>
          </span>
          <xsl:text>　</xsl:text>
        </xsl:if>
        <xsl:apply-templates
          select="*[substring(local-name(), string-length(local-name()) - 7) = 'Sentence']"/>
      </p>
      <xsl:apply-templates select="*[substring(local-name(), string-length(local-name()) - 4) != 'Title'
        and substring(local-name(), string-length(local-name()) - 7) != 'Sentence']"/>
    </div>
  </xsl:template>

  <!-- 本文 ================================================================== -->

  <xsl:template match="ParagraphSentence | ItemSentence | ClassSentence | ListSentence
                     | AmendProvisionSentence | SupplNote
                     | Subitem1Sentence | Subitem2Sentence | Subitem3Sentence
                     | Subitem4Sentence | Subitem5Sentence | Subitem6Sentence
                     | Subitem7Sentence | Subitem8Sentence | Subitem9Sentence
                     | Subitem10Sentence">
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="Sentence">
    <xsl:apply-templates/>
  </xsl:template>

  <!-- 欄（Column）は横並びの区画。1 つ目以外の前に区切りの余白を入れる。 -->
  <xsl:template match="Column">
    <span class="law-column"><xsl:apply-templates/></span>
  </xsl:template>

  <xsl:template match="Ruby">
    <ruby><xsl:apply-templates select="node()[not(self::Rt)]"/><xsl:apply-templates select="Rt"/></ruby>
  </xsl:template>

  <xsl:template match="Rt">
    <rt><xsl:apply-templates/></rt>
  </xsl:template>

  <xsl:template match="Sup">
    <sup><xsl:apply-templates/></sup>
  </xsl:template>

  <xsl:template match="Sub">
    <sub><xsl:apply-templates/></sub>
  </xsl:template>

  <xsl:template match="Line">
    <span class="law-line"><xsl:apply-templates/></span>
  </xsl:template>

  <xsl:template match="QuoteStruct">
    <blockquote class="law-quote"><xsl:apply-templates/></blockquote>
  </xsl:template>

  <xsl:template match="ArithFormula">
    <div class="law-formula"><xsl:apply-templates/></div>
  </xsl:template>

  <xsl:template match="ArithFormulaNum">
    <span class="law-formula-num"><xsl:apply-templates/></span>
  </xsl:template>

  <xsl:template match="List">
    <div class="law-list"><xsl:apply-templates/></div>
  </xsl:template>

  <xsl:template match="Class">
    <div class="law-class"><xsl:apply-templates/></div>
  </xsl:template>

  <xsl:template match="ClassTitle">
    <span class="law-class-title"><xsl:apply-templates/></span>
  </xsl:template>

  <!--
    図は元データが別ファイル（`./pict/*.pdf` 等）への参照で、法令XML単体には
    含まれない。取得もしない（リモート・兄弟ファイル読み出しの両方を避ける）ため、
    どこを参照しているかだけを出す。
  -->
  <xsl:template match="Fig">
    <p class="law-fig">［図：<xsl:value-of select="@src"/>］</p>
  </xsl:template>

  <!-- 表 ==================================================================== -->

  <xsl:template match="TableStruct | NoteStruct | StyleStruct | FormatStruct | FigStruct">
    <div class="law-struct"><xsl:apply-templates/></div>
  </xsl:template>

  <xsl:template match="TableStructTitle | NoteStructTitle | StyleStructTitle
                     | FormatStructTitle | FigStructTitle">
    <p class="law-struct-title"><xsl:apply-templates/></p>
  </xsl:template>

  <xsl:template match="Note | Style | Format">
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="Table">
    <div class="law-table-scroll">
      <table class="law-table"><tbody><xsl:apply-templates/></tbody></table>
    </div>
  </xsl:template>

  <xsl:template match="TableRow | TableHeaderRow">
    <tr><xsl:apply-templates/></tr>
  </xsl:template>

  <xsl:template match="TableHeaderColumn">
    <th class="law-table-cell"><xsl:apply-templates/></th>
  </xsl:template>

  <xsl:template match="TableColumn">
    <td>
      <xsl:attribute name="class">law-table-cell<xsl:if
        test="@BorderTop = 'none'"><xsl:text> law-no-border-top</xsl:text></xsl:if><xsl:if
        test="@BorderBottom = 'none'"><xsl:text> law-no-border-bottom</xsl:text></xsl:if><xsl:if
        test="@BorderLeft = 'none'"><xsl:text> law-no-border-left</xsl:text></xsl:if><xsl:if
        test="@BorderRight = 'none'"><xsl:text> law-no-border-right</xsl:text></xsl:if></xsl:attribute>
      <xsl:if test="@colspan"><xsl:attribute name="colspan"><xsl:value-of select="@colspan"/></xsl:attribute></xsl:if>
      <xsl:if test="@rowspan"><xsl:attribute name="rowspan"><xsl:value-of select="@rowspan"/></xsl:attribute></xsl:if>
      <xsl:apply-templates/>
    </td>
  </xsl:template>

  <xsl:template match="Remarks">
    <div class="law-remarks"><xsl:apply-templates/></div>
  </xsl:template>

  <xsl:template match="RemarksLabel">
    <p class="law-remarks-label"><xsl:apply-templates/></p>
  </xsl:template>

  <!-- 附則・別表 ============================================================ -->

  <xsl:template match="SupplProvision">
    <section class="law-suppl">
      <xsl:apply-templates select="SupplProvisionLabel"/>
      <xsl:if test="@AmendLawNum">
        <p class="law-suppl-amend"><xsl:value-of select="@AmendLawNum"/></p>
      </xsl:if>
      <xsl:apply-templates select="*[not(self::SupplProvisionLabel)]"/>
    </section>
  </xsl:template>

  <xsl:template match="SupplProvisionLabel">
    <h2 class="law-heading law-suppl-label"><xsl:apply-templates/></h2>
  </xsl:template>

  <xsl:template match="AppdxTable | AppdxStyle | AppdxNote | AppdxFig | AppdxFormat | Appdx
                     | SupplProvisionAppdxTable | SupplProvisionAppdxStyle | SupplProvisionAppdx">
    <section class="law-appdx"><xsl:apply-templates/></section>
  </xsl:template>

  <xsl:template match="AppdxTableTitle | AppdxStyleTitle | AppdxNoteTitle | AppdxFigTitle
                     | AppdxFormatTitle | SupplProvisionAppdxTableTitle
                     | SupplProvisionAppdxStyleTitle">
    <h3 class="law-heading law-appdx-title"><xsl:apply-templates/></h3>
  </xsl:template>

  <xsl:template match="RelatedArticleNum">
    <p class="law-related"><xsl:apply-templates/></p>
  </xsl:template>

  <!-- 改正規定 ============================================================== -->

  <xsl:template match="AmendProvision | NewProvision">
    <div class="law-amend"><xsl:apply-templates/></div>
  </xsl:template>

  <!--
    既定の規則。未対応の要素が来ても中身を落とさず出す（法令XMLは v3 で 100 種類
    ほどあり、上で名指ししていないものが必ず残る。落とすと本文が黙って消える）。
  -->
  <xsl:template match="*">
    <xsl:apply-templates/>
  </xsl:template>
</xsl:stylesheet>
