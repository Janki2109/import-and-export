import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a minimal, valid Word Open XML (.docx) document — a .docx is just a ZIP archive
/// of a handful of required XML parts. This hand-rolls those parts rather than pulling in
/// a heavyweight templating package, since the report only needs a title, a labeled field
/// table, and a footer — well within what raw OOXML can express directly.
class RfqDocxField {
  final String label;
  final String value;
  const RfqDocxField(this.label, this.value);
}

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

Uint8List buildRfqDocx({
  required String title,
  required String companyName,
  required String rfqNumber,
  required String issueDate,
  required List<RfqDocxField> fields,
  required String termsAndConditions,
  required String footer,
}) {
  final rows = fields
      .map((f) => '''
    <w:tr>
      <w:tc>
        <w:tcPr><w:tcW w:w="3000" w:type="dxa"/><w:shd w:val="clear" w:fill="EFF6E9"/></w:tcPr>
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">${_escapeXml(f.label)}</w:t></w:r></w:p>
      </w:tc>
      <w:tc>
        <w:tcPr><w:tcW w:w="6000" w:type="dxa"/></w:tcPr>
        <w:p><w:r><w:t xml:space="preserve">${_escapeXml(f.value)}</w:t></w:r></w:p>
      </w:tc>
    </w:tr>''')
      .join();

  final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:xml="http://www.w3.org/XML/1998/namespace">
  <w:body>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="20"/></w:rPr><w:t xml:space="preserve">${_escapeXml(companyName)}</w:t></w:r></w:p>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t xml:space="preserve">${_escapeXml(title)}</w:t></w:r></w:p>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">RFQ No. ${_escapeXml(rfqNumber)}  |  Issued: ${_escapeXml(issueDate)}</w:t></w:r></w:p>
    <w:p/>
    <w:tbl>
      <w:tblPr><w:tblW w:w="9000" w:type="dxa"/><w:tblBorders>
        <w:top w:val="single" w:sz="4" w:color="CCCCCC"/><w:left w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/><w:right w:val="single" w:sz="4" w:color="CCCCCC"/>
        <w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>
      </w:tblBorders></w:tblPr>
      $rows
    </w:tbl>
    <w:p/>
    <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Terms &amp; Conditions</w:t></w:r></w:p>
    <w:p><w:r><w:t xml:space="preserve">${_escapeXml(termsAndConditions)}</w:t></w:r></w:p>
    <w:p/>
    <w:p><w:r><w:t xml:space="preserve">Authorized Signature: ____________________        Company Stamp: ____________________</w:t></w:r></w:p>
    <w:p/>
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:sz w:val="16"/><w:color w:val="6B7280"/></w:rPr><w:t xml:space="preserve">${_escapeXml(footer)}</w:t></w:r></w:p>
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>
    </w:sectPr>
  </w:body>
</w:document>''';

  const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

  const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  const documentRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';

  ArchiveFile file(String path, String xml) {
    final bytes = utf8.encode(xml);
    return ArchiveFile(path, bytes.length, bytes);
  }

  final archive = Archive()
    ..addFile(file('[Content_Types].xml', contentTypesXml))
    ..addFile(file('_rels/.rels', rootRelsXml))
    ..addFile(file('word/document.xml', documentXml))
    ..addFile(file('word/_rels/document.xml.rels', documentRelsXml));

  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped!);
}
