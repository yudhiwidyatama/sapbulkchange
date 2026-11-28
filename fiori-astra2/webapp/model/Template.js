sap.ui.define([], function () {
  'use strict';
  // Fixed, data-free OOXML package. ZIP STORE avoids a client-side ZIP dependency.
  const headers = ['Document Number','Fiscal Year','Line Item','Document Type','Posting Date','G/L Account','KODE PROJECT','Source Data'];
  const types = 'http://schemas.openxmlformats.org/package/2006/content-types';
  const pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';
  const rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const sheet = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.';
  function crc32(bytes) {
    let value = -1;
    for (const byte of bytes) {value ^= byte; for (let bit=0;bit<8;bit++) value = (value >>> 1) ^ (0xedb88320 & -(value & 1));}
    return (value ^ -1) >>> 0;
  }
  function record(size,fields) {
    const bytes=new Uint8Array(size), view=new DataView(bytes.buffer);
    for (const [offset,width,value] of fields) {if(width===4)view.setUint32(offset,value,true);else view.setUint16(offset,value,true);}
    return bytes;
  }
  function workbook() {
    const files = {
      '[Content_Types].xml':`<Types xmlns="${types}"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/xl/workbook.xml" ContentType="${mime}sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="${mime}worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="${mime}styles+xml"/></Types>`,
      '_rels/.rels':`<Relationships xmlns="${pkg}"><Relationship Id="r1" Type="${rel}/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
      'xl/workbook.xml':`<workbook xmlns="${sheet}" xmlns:r="${rel}"><sheets><sheet name="Assignments" sheetId="1" r:id="r1"/></sheets></workbook>`,
      'xl/_rels/workbook.xml.rels':`<Relationships xmlns="${pkg}"><Relationship Id="r1" Type="${rel}/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Type="${rel}/styles" Target="styles.xml"/></Relationships>`,
      'xl/styles.xml':`<styleSheet xmlns="${sheet}"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`,
      'xl/worksheets/sheet1.xml':`<worksheet xmlns="${sheet}"><cols><col min="1" max="8" width="20" style="1" customWidth="1"/></cols><sheetData><row r="1">${headers.map((h,i)=>`<c r="${String.fromCharCode(65+i)}1" t="inlineStr"><is><t>${h}</t></is></c>`).join('')}</row></sheetData></worksheet>`
    };
    const enc=new TextEncoder(), parts=[], directory=[];let offset=0, dirSize=0;
    for(const [path,xml] of Object.entries(files)) {
      const name=enc.encode(path), data=enc.encode(xml), crc=crc32(data);
      const local=record(30,[[0,4,0x04034b50],[4,2,20],[12,2,33],[14,4,crc],[18,4,data.length],[22,4,data.length],[26,2,name.length]]);
      const central=record(46,[[0,4,0x02014b50],[4,2,20],[6,2,20],[14,2,33],[16,4,crc],[20,4,data.length],[24,4,data.length],[28,2,name.length],[42,4,offset]]);
      parts.push(local,name,data);directory.push(central,name);offset+=local.length+name.length+data.length;dirSize+=central.length+name.length;
    }
    const count=Object.keys(files).length;
    return new Blob([...parts,...directory,record(22,[[0,4,0x06054b50],[8,2,count],[10,2,count],[12,4,dirSize],[16,4,offset]])],{type:mime+'sheet'});
  }
  return {workbook};
});
