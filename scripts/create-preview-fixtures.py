"""只生成虚构正文联调文件；标准库、固定内容和时间，无真实卷宗。"""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

target = Path(__file__).resolve().parent.parent / 'client/tool/fixtures'
target.mkdir(parents=True, exist_ok=True)
text = 'Fictional preview document only'
stream = f'BT /F1 14 Tf 40 700 Td ({text}) Tj ET'
objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    f'<< /Length {len(stream)} >>\nstream\n{stream}\nendstream',
]
pdf = '%PDF-1.7\n'
offsets = []
for index, obj in enumerate(objects, 1):
    offsets.append(len(pdf))
    pdf += f'{index} 0 obj\n{obj}\nendobj\n'
xref = len(pdf)
pdf += 'xref\n0 6\n0000000000 65535 f \n'
pdf += ''.join(f'{offset:010d} 00000 n \n' for offset in offsets)
pdf += f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'
(target / 'fictional-preview.pdf').write_bytes(pdf.encode('ascii'))

parts = {
    '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    '_rels/.rels': '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/document.xml': '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' + ''.join(
        f'<w:p><w:r><w:t>{line}</w:t></w:r></w:p>' for line in [
            '法律服务合同', '(2026)虚构民初90号', '本文件仅用于虚构联调。'
        ]) + '</w:body></w:document>',
}
with ZipFile(target / 'fictional-preview.docx', 'w') as archive:
    for name, value in parts.items():
        info = ZipInfo(name, (2026, 10, 26, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        archive.writestr(info, '<?xml version="1.0" encoding="UTF-8"?>' + value)
print('PASS 已生成两份固定虚构正文文件，无真实数据')
