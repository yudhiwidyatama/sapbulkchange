sap.ui.define([
	"sap/ui/export/Spreadsheet",
	"sap/ui/export/library"
], function (Spreadsheet, exportLibrary) {
	"use strict";

	var EdmType = exportLibrary.EdmType;

	/**
	 * Template columns. The labels MUST match the header aliases accepted by
	 * ZCL_FI_UPLOAD_PARSER (see design section 3). Fixed English names, not translated.
	 */
	var COLUMNS = [
		{ label: "Document Number", property: "DocumentNumber", length: 10, example: "1900000001" },
		{ label: "Fiscal Year", property: "FiscalYear", length: 4, example: "2026" },
		{ label: "Line Item", property: "LineItem", length: 3, example: "1" },
		{ label: "Document Type", property: "DocumentType", length: 2, example: "SA" },
		{ label: "Posting Date", property: "PostingDate", length: 10, example: "2026-01-31" },
		{ label: "G/L Account", property: "GLAccount", length: 10, example: "6000000" },
		{ label: "KODE PROJECT", property: "KodeProject", length: 18, example: "PRJ-EXAMPLE-001" },
		{ label: "Source Data", property: "SourceData", length: 6, example: "BEBAN" }
	];

	function getColumns() {
		return COLUMNS.map(function (oColumn) {
			return {
				label: oColumn.label,
				property: oColumn.property,
				type: EdmType.String,
				width: Math.max(oColumn.label.length, oColumn.length) + 2
			};
		});
	}

	function getExampleRow() {
		var oRow = {};
		COLUMNS.forEach(function (oColumn) {
			oRow[oColumn.property] = oColumn.example;
		});
		return oRow;
	}

	/**
	 * Custom action handler (List Report toolbar). Builds the .xlsx in the browser.
	 * One example row is included so the export has a data source; it fails validation
	 * harmlessly (DOC_NOT_FOUND) if it is uploaded unchanged.
	 */
	function download() {
		var oSheet = new Spreadsheet({
			workbook: { columns: getColumns() },
			dataSource: [getExampleRow()],
			fileName: "FI_Assignment_Upload_Template.xlsx"
		});
		return oSheet.build().finally(function () {
			oSheet.destroy();
		});
	}

	return {
		COLUMNS: COLUMNS,
		getColumns: getColumns,
		getExampleRow: getExampleRow,
		download: download
	};
});
