sap.ui.define([
  'sap/fe/core/PageController', 'sap/ui/model/json/JSONModel', 'sap/m/MessageBox',
  'sap/m/SelectDialog', 'sap/m/StandardListItem', '../model/RunClient', '../model/Template'
], function (PageController, JSONModel, MessageBox, SelectDialog, StandardListItem, api, template) {
  'use strict';
  const initial = () => ({company:'', id:'', rows:[], message:'', messageType:'Information', summary:'', busy:false, canValidate:false, canApply:false, canExport:false, previous:false, next:false});
  function download(blob, name) {
    const url = URL.createObjectURL(blob), link = document.createElement('a');
    link.href=url; link.download=name; document.body.appendChild(link); link.click(); link.remove();
    window.setTimeout(()=>URL.revokeObjectURL(url), 30000);
  }
  return PageController.extend('astra.fi.assign.controller.Upload', {
    onInit: function () {
      PageController.prototype.onInit.apply(this, arguments);
      this.vm = new JSONModel(initial()); this.getView().setModel(this.vm,'run');
      const service=this.getView().getModel().getServiceUrl();
      this.client = new api.RunClient(service); this.epoch=0; this.offset=0;
      try {const id=sessionStorage.getItem('astra.fi.assign.run'); if(id){this.vm.setProperty('/id',id);this.refreshRun();}} catch (_) { /* storage optional */ }
    },
    text: function (key,args) {return this.getView().getModel('i18n').getResourceBundle().getText(key,args);},
    remember: function (id) {try {if(id)sessionStorage.setItem('astra.fi.assign.run',id);else sessionStorage.removeItem('astra.fi.assign.run');} catch (_) {}},
    clearPlan: function (company) {
      this.epoch++; this.plan=null;this.offset=0;this.remember('');
      this.vm.setData({...initial(),company,canValidate:/^[A-Z0-9]{4}$/.test(company)&&api.validFile(this.file)});
    },
    resetPlan: function(e) {this.clearPlan(e.getParameter('value') || '');},
    chooseFile: function(e) {
      this.file=(e.getParameter('files') || [])[0];this.clearPlan(this.vm.getProperty('/company'));
      if(this.file&&!api.validFile(this.file))this.invalidFile();
    },
    invalidFile: function() {this.file=null;this.clearPlan(this.vm.getProperty('/company'));this.byId('workbook').clear();this.message('badFile','Error');},
    message: function(key,type){this.vm.setProperty('/message',this.text(key));this.vm.setProperty('/messageType',type);},
    work: async function(task) {
      if(this.vm.getProperty('/busy'))return;
      const epoch=this.epoch;this.vm.setProperty('/busy',true);
      try {await task(()=>this.epoch===epoch);} catch (_) {if(this.epoch===epoch){this.plan=null;this.vm.setProperty('/canApply',false);this.vm.setProperty('/canExport',false);this.vm.setProperty('/rows',[]);this.message('failed','Error');}}
      finally {if(this.epoch===epoch)this.vm.setProperty('/busy',false);}
    },
    chooseCompany: function(){return this.work(async current=>{
      const companies=await this.client.companies();if(!current())return;
      const dialog=new SelectDialog({title:this.text('company'),confirm:e=>{const item=e.getParameter('selectedItem');if(item)this.clearPlan(item.getTitle());},afterClose:()=>dialog.destroy()});
      companies.forEach(c=>dialog.addItem(new StandardListItem({title:c.CompanyCode,description:c.Name})));this.getView().addDependent(dialog);dialog.open();
    });},
    downloadTemplate: function(){download(template.workbook(),'FI-assignment-template.xlsx');},
    validate: function(){if(!this.vm.getProperty('/canValidate'))return;return this.work(async current=>{
      this.plan=null;this.vm.setProperty('/canApply',false);const id=await this.client.stage(this.vm.getProperty('/company'),this.file);
      if(!current())return;this.offset=0;this.vm.setProperty('/id',id);this.remember(id);await this.load(current);
    });},
    load: async function(current){
      const id=this.vm.getProperty('/id'); if(!id)return;
      const run=await this.client.status(id);if(!current())return;if(run.RunId!==id)throw new Error('Run mismatch');
      const pageReady=['READY','COMPLETED','FAILED','PARTIAL'].includes(run.State);
      const rows=pageReady?await this.client.rows(id,this.offset):[];if(!current())return;
      this.plan=run;const allowed=api.canApply(run);const previous=this.vm.getData();
      this.vm.setData({...previous,company:run.CompanyCode,rows,canValidate:false,canApply:allowed,canExport:pageReady&&run.ErrorCount>0,previous:pageReady&&this.offset>0,next:pageReady&&this.offset+rows.length<run.RowCount&&rows.length>0,summary:this.text('summary',[id,run.State,run.RowCount,run.PlannedCount])});
      this.message(!pageReady?'waiting':allowed?'review':run.State==='READY'?'blocked':'finished',run.State==='FAILED'?'Error':'Information');
    },
    refreshRun: function(){return this.work(current=>this.load(current));},
    previousPage: function(){this.offset=Math.max(0,this.offset-api.PAGE);return this.refreshRun();},
    nextPage: function(){this.offset+=api.PAGE;return this.refreshRun();},
    confirmApply: function(){const plan=this.plan,epoch=this.epoch;if(!api.canApply(plan))return;
      MessageBox.confirm(this.text('confirm',[plan.CompanyCode]),{onClose:answer=>{
        if(answer!==MessageBox.Action.OK||epoch!==this.epoch||this.plan!==plan)return;
        this.work(async current=>{this.plan=null;this.vm.setProperty('/canApply',false);await this.client.apply(plan);if(current())await this.load(current);});
      }});
    },
    errors: function(){return this.work(async current=>{const blob=await this.client.errors(this.vm.getProperty('/id'));if(current())download(blob,'FI-assignment-errors.csv');});},
    onExit: function(){this.epoch++;if(PageController.prototype.onExit)PageController.prototype.onExit.apply(this,arguments);}
  });
});
