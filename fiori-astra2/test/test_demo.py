import io, json, os, time, unittest, urllib.request, urllib.error
from pathlib import Path
from openpyxl import load_workbook, Workbook
from demo_server import HEADERS, BASE, preview

ROW=['42','2022','1','SA','20220131','4000','NEW','BEBAN']
def sample(n):
    wb=Workbook(write_only=True);ws=wb.create_sheet('Assignments');ws.append(HEADERS)
    for i in range(n):ws.append(ROW)
    b=io.BytesIO();wb.save(b);return b.getvalue()
class Integration(unittest.TestCase):
    def test_template(self):
        wb=load_workbook(os.environ.get('TEST_TEMPLATE','/tmp/astra2-template.xlsx'));self.assertEqual(wb.active.title,'Assignments');self.assertEqual(list(next(wb.active.values)),HEADERS);self.assertEqual(wb.active.column_dimensions['A'].number_format,'@');wb.close()
    def test_capacity(self):
        rows=preview(sample(50000));self.assertEqual(len(rows),50000);self.assertTrue(all(r['Status']=='ERROR' and r['Message']=='Duplicate normalized key' for r in rows));
        with self.assertRaisesRegex(ValueError,'row limit'):preview(sample(50001))
    def test_http(self):
        root='http://127.0.0.1:8080'+BASE
        def req(path,method='GET',body=None,headers=None):return urllib.request.urlopen(urllib.request.Request(root+path,data=body,headers=headers or {},method=method),timeout=10)
        csrf=req('$metadata').headers['X-CSRF-Token'];auth={'X-CSRF-Token':csrf}
        run=json.load(req('Runs','POST',b'{"CompanyCode":"DEMO"}',auth));key='Runs('+run['RunId']+')';headers={**auth,'If-Match':run['@odata.etag']};content=sample(1)
        self.assertEqual(req(key+'/Workbook/$value','PUT',content,headers).status,204)
        with self.assertRaises(urllib.error.HTTPError) as err:req(key+'/Workbook/$value','PUT',content,headers)
        self.assertEqual(err.exception.code,412)
        for i in range(100):
            record=json.load(req(key));
            if record['State']=='READY':break
            time.sleep(.05)
        self.assertEqual(record['State'],'READY');self.assertFalse(record['ApplyAllowed']);self.assertEqual(record['PlannedCount'],1)
        self.assertEqual(json.load(req(key+'/Rows?$top=100&$skip=0'))['value'][0]['Item'],'001')
        with self.assertRaises(urllib.error.HTTPError) as err:req(key+'/ZFI_ASSIGN_UPLOAD.Apply','POST',b'{}',auth)
        self.assertEqual(err.exception.code,403)
if __name__=='__main__':unittest.main()
