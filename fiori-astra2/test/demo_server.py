"""Loopback fixture only: never deploy. No SAP connection, credentials or FI writes.
Run from any directory: python test/demo_server.py. Requires openpyxl.
Only the canonical template and the synthetic DEMO posting are supported here.
"""
import csv, io, json, re, secrets, threading, uuid, zipfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
from openpyxl import load_workbook

BASE='/sap/opu/odata4/sap/zfi_assign_upload/srvd/sap/zfi_assign_upload/0001/'
WEB=Path(__file__).resolve().parents[1]/'webapp'
META=Path(__file__).with_name('metadata.xml').read_bytes()
LIMIT=20971520
HEADERS=['Document Number','Fiscal Year','Line Item','Document Type','Posting Date','G/L Account','KODE PROJECT','Source Data']
# Deliberately independent of live identities; fixture has one company and one posted item.
POSTED=('0000000042','2022','001','SA','20220131','4000')
RUNS={}; LOCK=threading.Lock(); QUEUE=ThreadPoolExecutor(max_workers=1); TOKEN=secrets.token_urlsafe(24)

def preview(body):
    with zipfile.ZipFile(io.BytesIO(body)) as package:
        if sum(f.file_size for f in package.infolist())>128*1024*1024: raise ValueError('expanded')
    book=load_workbook(io.BytesIO(body),read_only=True,data_only=True)
    try:
        sheet=book.worksheets[0]; sheet.reset_dimensions(); records=sheet.iter_rows(values_only=True)
        headers=[str(v or '').strip() for v in next(records,())]; required=HEADERS[:-1]
        if len(set(headers))!=len(headers) or not set(required)<=set(headers): raise ValueError('headers')
        rows=[]; keys=Counter()
        for number,record in enumerate(records,2):
            if not any(v is not None and str(v).strip() for v in record): continue
            if len(rows)>=50000: raise ValueError('row limit')
            cells=dict(zip(headers,record)); val=lambda n:str(cells.get(n) if cells.get(n) is not None else '').strip()
            doc,year,item=val(HEADERS[0]).zfill(10),val(HEADERS[1]),val(HEADERS[2]).zfill(3)
            target=val('KODE PROJECT'); date=cells.get('Posting Date'); date=date.strftime('%Y%m%d') if hasattr(date,'strftime') else str(date).replace('-','')
            ok=(doc,year,item,val('Document Type').upper(),date,val('G/L Account').lstrip('0'))==POSTED and 0<len(target)<=18 and val('Source Data').upper() in ('','BEBAN')
            status=('SKIPPED_ALREADY_SET' if target=='OLD' else 'PLANNED') if ok else 'ERROR'
            keys[doc,year,item]+=1
            rows.append(dict(RowNo=number,Document=doc,Year=year,Item=item,OldAssignment='OLD' if ok else '',TargetAssignment=target,Status=status,Field='' if ok else 'Input',Message='' if ok else 'No matching authorized fixture row or invalid input'))
        if not rows: raise ValueError('empty')
        for r in rows:
            if keys[r['Document'],r['Year'],r['Item']]>1:r.update(Status='ERROR',OldAssignment='',Field='Item',Message='Duplicate normalized key')
        return rows
    finally: book.close()

def validate(key,body):
    try: rows=preview(body);state='READY'
    except Exception:rows=[];state='FAILED'
    with LOCK:RUNS[key].update(State=state, rows=rows, revision=3, RowCount=len(rows), PlannedCount=sum(r['Status']=='PLANNED' for r in rows),ErrorCount=sum(r['Status']=='ERROR' for r in rows))

def etag(run):return 'W/"%d"'%run['revision']
def expose(run):return {**{k:v for k,v in run.items() if k not in ('revision','rows')},'@odata.etag':etag(run),'ApplyAllowed':False}
class Handler(BaseHTTPRequestHandler):
    def reply(self,status,data=b'',kind='application/json',extra=None):
        if not isinstance(data,bytes):data=json.dumps(data).encode()
        self.send_response(status);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.send_header('OData-Version','4.0')
        for k,v in (extra or {}).items():self.send_header(k,v)
        self.end_headers();self.wfile.write(data)
    def route(self):
        url=urlsplit(self.path); path=url.path; query=parse_qs(url.query)
        if not path.startswith(BASE):
            if self.command!='GET':return self.reply(405)
            if path.startswith('/resources/'):
                self.send_response(302);self.send_header('Location','https://ui5.sap.com/1.108/resources/'+path[len('/resources/'):]);self.end_headers();return
            file=(WEB/(path.strip('/') or 'index.html')).resolve()
            if WEB not in file.parents or not file.is_file():return self.reply(404)
            import mimetypes
            return self.reply(200,file.read_bytes(),mimetypes.guess_type(file.name)[0] or 'application/octet-stream')
        endpoint=path[len(BASE):]
        if self.command=='GET' and endpoint=='$metadata':return self.reply(200,META,'application/xml',{'X-CSRF-Token':TOKEN})
        if self.command!='GET' and self.headers.get('X-CSRF-Token')!=TOKEN:return self.reply(403)
        if self.command=='GET' and endpoint=='CompanyCodes':return self.reply(200,{'value':[{'CompanyCode':'DEMO','Name':'Synthetic test company'}]})
        try: length=int(self.headers.get('Content-Length','0'))
        except ValueError:return self.reply(400)
        if length<0 or length>LIMIT:return self.reply(413)
        if self.command=='POST' and endpoint=='Runs':
            try: payload=json.loads(self.rfile.read(length))
            except ValueError:return self.reply(400)
            if payload!={'CompanyCode':'DEMO'}:return self.reply(403)
            key=str(uuid.uuid4());run=dict(RunId=key,CompanyCode='DEMO',State='NEW',RowCount=0,PlannedCount=0,ErrorCount=0,revision=1,rows=[])
            with LOCK:RUNS[key]=run
            return self.reply(201,expose(run))
        match=re.fullmatch(r'Runs\(([0-9a-f-]{36})\)(/.*)?',endpoint)
        if not match:return self.reply(404)
        key,sub=match.groups()
        with LOCK:
            run=RUNS.get(key)
            if not run:return self.reply(404)
            if self.command=='GET' and not sub:return self.reply(200,expose(run))
            if self.command=='PUT' and sub=='/Workbook/$value':
                if run['State']!='NEW' or self.headers.get('If-Match')!=etag(run):return self.reply(412)
                if length==0:return self.reply(400)
                body=self.rfile.read(length);run.update(State='VALIDATE_QUEUED',revision=2);QUEUE.submit(validate,key,body);return self.reply(204)
            if self.command=='GET' and sub=='/Rows':
                try:skip=max(0,int(query.get('$skip',['0'])[0]));top=min(100,max(0,int(query.get('$top',['100'])[0])))
                except ValueError:return self.reply(400)
                return self.reply(200,{'value':run['rows'][skip:skip+top]})
            if self.command=='GET' and sub=='/ErrorCsv/$value':
                stream=io.StringIO();writer=csv.writer(stream);writer.writerow(['Row','Field','Message']);writer.writerows((r['RowNo'],r['Field'],r['Message']) for r in run['rows'] if r['Status']=='ERROR');return self.reply(200,stream.getvalue().encode('utf-8-sig'),'text/csv')
            if self.command=='POST' and sub=='/ZFI_ASSIGN_UPLOAD.Apply':return self.reply(403,{'error':{'message':'Demo has no write adapter'}})
        return self.reply(404)
    do_GET=do_POST=do_PUT=route
if __name__=='__main__':
    print('Synthetic data only: http://127.0.0.1:8080',flush=True);ThreadingHTTPServer(('127.0.0.1',8080),Handler).serve_forever()
