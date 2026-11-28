/* Node smoke test for ext/Template.js (no UI5 runtime needed).
 * Run: node webapp/test/Template.test.js
 */
"use strict";
var assert = require("assert");
var path = require("path");

var built = [];
function SpreadsheetStub(mSettings) {
	this.settings = mSettings;
	built.push(this);
}
SpreadsheetStub.prototype.build = function () {
	return Promise.resolve();
};
SpreadsheetStub.prototype.destroy = function () {
	this.destroyed = true;
};

global.sap = {
	ui: {
		define: function (aDeps, fnFactory) {
			var mModules = {
				"sap/ui/export/Spreadsheet": SpreadsheetStub,
				"sap/ui/export/library": { EdmType: { String: "String" } }
			};
			global.__module = fnFactory.apply(null, aDeps.map(function (s) { return mModules[s]; }));
		}
	}
};

require(path.join(__dirname, "..", "ext", "Template.js"));
var Template = global.__module;

// 1. headers must equal the parser's required header names, in order
var aExpected = ["Document Number", "Fiscal Year", "Line Item", "Document Type",
	"Posting Date", "G/L Account", "KODE PROJECT", "Source Data"];
assert.deepStrictEqual(Template.getColumns().map(function (c) { return c.label; }), aExpected);

// 2. all columns are strings with a width that fits the field length
Template.getColumns().forEach(function (c, i) {
	assert.strictEqual(c.type, "String");
	assert.ok(c.width >= Template.COLUMNS[i].length);
});

// 3. example row has a value for every column and respects field lengths
var oRow = Template.getExampleRow();
Template.COLUMNS.forEach(function (c) {
	assert.ok(oRow[c.property], "example missing for " + c.label);
	assert.ok(oRow[c.property].length <= c.length, "example too long for " + c.label);
});

// 4. download builds a workbook with the right file name and destroys the instance
Template.download().then(function () {
	assert.strictEqual(built.length, 1);
	assert.strictEqual(built[0].settings.fileName, "FI_Assignment_Upload_Template.xlsx");
	assert.strictEqual(built[0].settings.dataSource.length, 1);
	assert.strictEqual(built[0].destroyed, true);
	console.log("Template.test.js: all assertions passed");
});
