/* Standalone host only; the Fiori launchpad starts Component.js directly. */
sap.ui.getCore().attachInit(function () {
  'use strict';
  sap.ui.require(['sap/ui/core/Component','sap/ui/core/ComponentContainer'], function (Component, ComponentContainer) {
    Component.create({name:'astra.fi.assign',url:'./',manifest:true}).then(function (app) {
      new ComponentContainer('astra-shell',{component:app,height:'100%',width:'100%',lifecycle:'Container'}).placeAt('app');
    }).catch(function (error) {
      console.error('FI upload component startup failed',error);
      document.getElementById('app').textContent='FI assignment upload could not start.';
    });
  });
});
