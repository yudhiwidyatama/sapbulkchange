sap.ui.define([], function () {
  'use strict';
  const PAGE = 100;
  const MAX_BYTES = 20 * 1024 * 1024;
  const GUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
  function validFile(file) {
    return !!file && /\.xlsx$/i.test(file.name) && Number.isSafeInteger(file.size) && file.size > 0 && file.size <= MAX_BYTES;
  }
  function runPath(id) {
    if (!GUID.test(id)) throw new Error('Invalid run key');
    return `Runs(${id})`;
  }
  function canApply(run) {
    return !!run && run.State === 'READY' && run.ApplyAllowed === true && run.PlannedCount > 0 && !!run['@odata.etag'];
  }
  class RunClient {
    constructor(root, transport) {
      this.root = root.endsWith('/') ? root : root + '/';
      this.transport = transport || window.fetch.bind(window);
    }
    async request(path, options = {}) {
      const response = await this.transport(this.root + path, {credentials: 'same-origin', cache: 'no-store', redirect: 'error', ...options});
      if (!response.ok) throw new Error(`Request failed (${response.status})`);
      return response;
    }
    async token() {
      const response = await this.request('$metadata', {headers: {'X-CSRF-Token':'Fetch'}});
      const token = response.headers.get('X-CSRF-Token');
      if (!token || /^(fetch|required)$/i.test(token)) throw new Error('Missing CSRF token');
      return token;
    }
    async stage(company, file) {
      if (!/^[A-Z0-9]{4}$/.test(company) || !validFile(file)) throw new Error('Invalid upload');
      const csrf = await this.token();
      const created = await (await this.request('Runs', {method:'POST', headers:{'Content-Type':'application/json','X-CSRF-Token':csrf},body:JSON.stringify({CompanyCode:company})})).json();
      const key = runPath(created.RunId);
      // A run starts validation ONLY when its immutable stream is completely received.
      await this.request(key + '/Workbook/$value', {method:'PUT', headers:{'Content-Type':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','X-CSRF-Token':csrf,'If-Match':created['@odata.etag']},body:file});
      return created.RunId;
    }
    async status(id) { return (await this.request(runPath(id), {headers:{Accept:'application/json'}})).json(); }
    async rows(id, skip) {
      if (!Number.isSafeInteger(skip) || skip < 0) throw new Error('Invalid offset');
      return (await (await this.request(`${runPath(id)}/Rows?$orderby=RowNo&$top=${PAGE}&$skip=${skip}`, {headers:{Accept:'application/json'}})).json()).value;
    }
    async apply(run) {
      if (!canApply(run)) throw new Error('Plan not eligible');
      const csrf = await this.token();
      await this.request(runPath(run.RunId)+'/ZFI_ASSIGN_UPLOAD.Apply', {method:'POST',headers:{'X-CSRF-Token':csrf,'If-Match':run['@odata.etag'],'Content-Type':'application/json'},body:'{}'});
    }
    async errors(id) { return (await this.request(runPath(id)+'/ErrorCsv/$value')).blob(); }
    async companies() {return (await (await this.request('CompanyCodes?$orderby=CompanyCode', {headers:{Accept:'application/json'}})).json()).value;}
  }
  return {RunClient, validFile, canApply, PAGE, MAX_BYTES};
});
